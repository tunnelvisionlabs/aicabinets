# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/test_harness')

class TC_DialogPartitions < TestUp::TestCase
  include TestUiPump
  DEFAULT_TEST_TIMEOUT = 15.0
  READY_SCRIPT = <<~JAVASCRIPT
    (function () {
      var attempts = 0;

      function waitForApi(resolve, reject) {
        var api = window.AICabinetsTest;
        if (api && typeof api.ready === 'function') {
          try {
            var value = api.ready();
            if (value && typeof value.then === 'function') {
              value.then(resolve, reject);
            } else {
              resolve(value);
            }
          } catch (error) {
            reject(error);
          }
          return;
        }

        attempts += 1;
        if (attempts > 600) {
          reject(new Error('AICabinetsTest.ready() unavailable after waiting.'));
          return;
        }

        window.setTimeout(function () {
          waitForApi(resolve, reject);
        }, 10);
      }

      return new Promise(function (resolve, reject) {
        waitForApi(resolve, reject);
      });
    })()
  JAVASCRIPT

  def setup
    @dialog_handle = AICabinets::TestHarness.open_dialog_for_tests
    @dialog_ready = false
    @ready_result = nil
  end

  def teardown
    teardown_html_dialog(@dialog_handle)
    @dialog_handle = nil
  end

  def test_partition_mode_fieldset_accessibility
    run_dialog_test do
      state = dialog_state

      a11y = state.fetch('a11y')
      assert_equal('fieldset', a11y['partitionFieldsetTag'])
      assert_includes(a11y['partitionLegend'], 'Partition mode')
      assert_equal(
        ['None', 'Vertical (start left)', 'Horizontal (start top)'],
        a11y['radioLabels'],
        'Partition mode radios should surface human-readable labels.'
      )

      live_region = a11y['liveRegion']
      assert(live_region, 'Live region should be present')
      assert_equal('status', live_region['role'])
      assert_equal('polite', live_region['ariaLive'])
      assert_equal('true', live_region['ariaAtomic'])
    end
  end

  def test_partition_mode_gating_and_announcements
    run_dialog_test do
      none_state = dialog_state

      assert_equal('none', none_state['partition_mode'])
      gating = none_state.fetch('gating')
      assert(gating['globalsVisible'], 'Globals should be visible in none mode')
      refute(gating['baysVisible'], 'Bays should be hidden when partition mode is none')

      vertical_state = await_js('AICabinetsTest.setPartitionMode("vertical")')
      gating_vertical = vertical_state.fetch('gating')
      assert(gating_vertical['baysVisible'], 'Bays should be visible in vertical mode')
      refute(gating_vertical['globalsVisible'], 'Global fronts should be hidden in vertical mode')

      announcement_vertical = vertical_state.fetch('announcement')
      assert_includes(
        announcement_vertical,
        'Vertical',
        'Expected live region message for vertical mode'
      )

      horizontal_state = await_js('AICabinetsTest.setPartitionMode("horizontal")')
      gating_horizontal = horizontal_state.fetch('gating')
      assert(gating_horizontal['baysVisible'], 'Bays should be visible in horizontal mode')
      announcement_horizontal = horizontal_state.fetch('announcement')
      assert_includes(
        announcement_horizontal,
        'Horizontal',
        'Expected live region message for horizontal mode'
      )
    end
  end

  def test_bay_chips_count_and_first_click_selects
    run_dialog_test do
      await_js('AICabinetsTest.setPartitionMode("vertical")')
      state = await_js('AICabinetsTest.setTopCount(2)')

      chips = state['chips']
      assert_equal(3, chips.length, 'Expected count + 1 chips when count = 2')
      assert_equal(['Bay 1', 'Bay 2', 'Bay 3'], chips.map { |chip| chip['label'] })
      assert(chips.first['selected'], 'First chip should start selected')

      after_click = await_js('AICabinetsTest.clickBay(2)')
      assert_equal(2, after_click['selected_bay_index'])
      chip_selection = after_click['chips'].map { |chip| chip['selected'] }
      assert_equal([false, false, true], chip_selection, 'Expected the third chip to be selected after first click')

      tabs = after_click['a11y']['chipTabStops']
      assert_equal(0, tabs[2], 'Roving tabindex should move focus to the selected chip')
    end
  end

  def test_selection_clamped_when_count_decreases
    run_dialog_test do
      await_js('AICabinetsTest.setPartitionMode("vertical")')
      await_js('AICabinetsTest.setTopCount(3)')
      await_js('AICabinetsTest.clickBay(3)')

      reduced = await_js('AICabinetsTest.setTopCount(1)')
      assert_equal(1, reduced['selected_bay_index'], 'Selection should clamp to the last available bay')
      assert_equal(2, reduced['chips'].length, 'Count 1 should render two bays')
    end
  end

  def test_per_bay_editor_round_trip_preserves_fronts
    run_dialog_test do
      await_js('AICabinetsTest.setPartitionMode("vertical")')
      await_js('AICabinetsTest.setTopCount(1)')

      seed_fronts_script = <<~JAVASCRIPT
        (function () {
          var ctrl = window.AICabinets.UI.InsertBaseCabinet.controller;
          ctrl.ensureBayLength();
          ctrl.handleBayShelfChange(ctrl.selectedBayIndex, 4);
          ctrl.handleBayDoorChange(ctrl.selectedBayIndex, 'doors_left');
          return true;
        })()
      JAVASCRIPT
      await_js(seed_fronts_script)

      await_js('AICabinetsTest.toggleBayEditor("subpartitions")')
      await_js('AICabinetsTest.setNestedCount(2)')

      restored = await_js('AICabinetsTest.toggleBayEditor("fronts_shelves")')
      fronts = restored.dig('baySnapshot', 'selected', 'fronts_shelves_state')
      assert_equal(4, fronts['shelf_count'], 'Shelf count should survive bay editor toggles')
      assert_equal('doors_left', fronts['door_mode'], 'Door mode should survive bay editor toggles')
    end
  end

  def test_double_door_gating_and_live_region_announcements
    run_dialog_test do
      await_js('AICabinetsTest.setPartitionMode("vertical")')

      await_js('AICabinetsTest.setTopCount(5)')
      narrow_state = await_js('AICabinetsTest.requestDoubleValidity()')
      double_state = narrow_state.dig('baySnapshot', 'double')
      refute_nil(double_state, 'Expected double-door snapshot data')

      assert(double_state['disabled'], 'Double door option should be disabled for narrow bay')
      assert(double_state['hintVisible'], 'Hint should be visible when double doors are disabled')
      assert_includes(double_state['hint'], 'minimum', 'Hint should reference minimum leaf width')
      metadata = double_state['validity']
      refute_nil(metadata, 'Expected validity metadata for double doors')
      refute(metadata['allowed'], 'Metadata should mark double doors as not allowed')
      assert(metadata['leafWidthMm'] < metadata['minLeafWidthMm'], 'Leaf width should be below minimum')
      tab_index = double_state['tabIndex']
      assert(tab_index.nil? || tab_index <= -1, 'Disabled radio should not be focusable')
      assert_includes(
        narrow_state['announcement'],
        'Double doors disabled',
        'Live region should announce when double doors are unavailable'
      )

      await_js('AICabinetsTest.setTopCount(1)')
      wide_state = await_js('AICabinetsTest.requestDoubleValidity()')
      wide_double = wide_state.dig('baySnapshot', 'double')
      refute_nil(wide_double, 'Expected double-door snapshot data after widening bay')
      refute(wide_double['disabled'], 'Double door option should be enabled after widening bay')
      refute(wide_double['hintVisible'], 'Hint should hide when double doors become available')
      wide_metadata = wide_double['validity']
      assert(wide_metadata, 'Expected validity metadata when enabled')
      assert(wide_metadata['allowed'], 'Metadata should mark double doors as allowed')
      assert(wide_metadata['leafWidthMm'] >= wide_metadata['minLeafWidthMm'], 'Leaf width should meet minimum when enabled')
      assert_includes(
        wide_state['announcement'],
        'Double doors available',
        'Live region should announce when double doors become available'
      )
    end
  end

  private

  def run_dialog_test(&block)
    raise ArgumentError, 'run_dialog_test requires a block' unless block_given?

    ensure_dialog_ready
    instance_eval(&block)
  end

  def ensure_dialog_ready
    return if @dialog_ready

    result = await_js(READY_SCRIPT)
    @dialog_ready = true if result
    @ready_result = result
  end

  def await_js(expression, timeout: DEFAULT_TEST_TIMEOUT)
    result = nil

    reason = with_modal_pump(timeout: timeout) do |_pump, close_pump|
      @dialog_handle.eval_js_async(expression) do |payload|
        result = payload
        close_pump.call
      end
    end

    if result.nil?
      message = 'Timed out waiting for HtmlDialog eval.'
      raise AICabinets::TestHarness::TimeoutError, message if reason == :timeout

      raise AICabinets::TestHarness::EvalError, 'HtmlDialog eval ended without a payload.'
    end

    return result[:value] if result[:ok]

    raise AICabinets::TestHarness::EvalError, result[:error]
  end

  def dialog_state
    ensure_dialog_ready
    await_js('AICabinetsTest.getState()')
  end

end
