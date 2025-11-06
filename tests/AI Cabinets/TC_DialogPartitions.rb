# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/test_harness')

class TC_DialogPartitions < TestUp::TestCase
  def setup
    @dialog_handle = AICabinets::TestHarness.open_dialog_for_tests
    @dialog_ready = false
    @ready_result = nil
  end

  def teardown
    @dialog_handle&.close
    @dialog_handle = nil
  end

  def test_partition_mode_fieldset_accessibility
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
    assert_equal('status', live_region['role'])
    assert_equal('polite', live_region['ariaLive'])
    assert_equal('true', live_region['ariaAtomic'])
  end

  def test_partition_mode_gating_and_announcements
    none_state = dialog_state

    assert_equal('none', none_state['partition_mode'])
    gating = none_state.fetch('gating')
    assert(gating['globalsVisible'], 'Globals should be visible in none mode')
    refute(gating['baysVisible'], 'Bays should be hidden when partition mode is none')

    vertical_state = await_js('AICabinetsTest.setPartitionMode("vertical")')
    gating_vertical = vertical_state.fetch('gating')
    assert(gating_vertical['baysVisible'], 'Bays should be visible in vertical mode')
    refute(gating_vertical['globalsVisible'], 'Global fronts should be hidden in vertical mode')

    message = await_js('AICabinetsTest.lastLiveRegion()')
    assert_includes(message, 'Vertical', 'Expected live region message for vertical mode')

    horizontal_state = await_js('AICabinetsTest.setPartitionMode("horizontal")')
    gating_horizontal = horizontal_state.fetch('gating')
    assert(gating_horizontal['baysVisible'], 'Bays should be visible in horizontal mode')
    message_horizontal = await_js('AICabinetsTest.lastLiveRegion()')
    assert_includes(message_horizontal, 'Horizontal', 'Expected live region message for horizontal mode')
  end

  def test_bay_chips_count_and_first_click_selects
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

  def test_selection_clamped_when_count_decreases
    await_js('AICabinetsTest.setPartitionMode("vertical")')
    await_js('AICabinetsTest.setTopCount(3)')
    await_js('AICabinetsTest.clickBay(3)')

    reduced = await_js('AICabinetsTest.setTopCount(1)')
    assert_equal(1, reduced['selected_bay_index'], 'Selection should clamp to the last available bay')
    assert_equal(2, reduced['chips'].length, 'Count 1 should render two bays')
  end

  def test_per_bay_editor_round_trip_preserves_fronts
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

  private

  def ensure_dialog_ready
    return if @dialog_ready

    wait_for_ready
  end

  def wait_for_ready
    wait_for_async('AICabinetsTest.ready()') do |result|
      if result[:ok]
        @dialog_ready = true
        @ready_result = result[:value]
      end
    end
    flunk('Timed out waiting for HtmlDialog test namespace to become ready.') unless @dialog_ready
  end

  def await_js(expression)
    ensure_dialog_ready
    wait_for_async(expression) do |result|
      return result[:value] if result[:ok]

      raise AICabinets::TestHarness::EvalError, result[:error]
    end
    raise AICabinets::TestHarness::TimeoutError, 'Timed out waiting for HtmlDialog eval.'
  end

  def dialog_state
    ensure_dialog_ready
    await_js('AICabinetsTest.getState()')
  end

  def wait_for_async(expression)
    finished = false
    payload = nil

    @dialog_handle.eval_js_async(expression) do |result|
      payload = result
      finished = true
    end

    deadline = Time.now + 15.0
    until finished
      if Time.now > deadline
        return nil
      end

      sleep(0.01)
    end

    block_given? ? yield(payload) : payload
  end
end
