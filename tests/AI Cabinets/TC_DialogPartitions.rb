# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/test_harness')

class TC_DialogPartitions < TestUp::TestCase
  include TestUiPump
  DEFAULT_TEST_TIMEOUT = 15.0

  def setup
    @dialog_handle = AICabinets::TestHarness.open_dialog_for_tests
    @dialog_ready = false
    @ready_result = nil
    @current_test_fiber = nil
    @async_done = false
    @async_error = nil
  end

  def teardown
    @dialog_handle&.close
    @dialog_handle = nil
    @current_test_fiber = nil
    @async_done = false
    @async_error = nil
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

      message = await_js('AICabinetsTest.lastLiveRegion()')
      assert_includes(message, 'Vertical', 'Expected live region message for vertical mode')

      horizontal_state = await_js('AICabinetsTest.setPartitionMode("horizontal")')
      gating_horizontal = horizontal_state.fetch('gating')
      assert(gating_horizontal['baysVisible'], 'Bays should be visible in horizontal mode')
      message_horizontal = await_js('AICabinetsTest.lastLiveRegion()')
      assert_includes(message_horizontal, 'Horizontal', 'Expected live region message for horizontal mode')
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

  private

  def run_dialog_test(timeout: DEFAULT_TEST_TIMEOUT, &block)
    raise ArgumentError, 'run_dialog_test requires a block' unless block_given?

    @async_done = false
    @async_error = nil

    fiber = Fiber.new do
      @current_test_fiber = Fiber.current
      begin
        ensure_dialog_ready
        instance_eval(&block)
      rescue StandardError => exception
        @async_error = exception
      ensure
        @async_done = true
        @current_test_fiber = nil
      end
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    fiber.resume

    until @async_done
      flunk('Timed out waiting for async dialog test to finish.') if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      process_ui_events
    end

    raise @async_error if @async_error
  ensure
    @current_test_fiber = nil
  end

  def ensure_dialog_ready
    return if @dialog_ready

    result = await_js('AICabinetsTest.ready()')
    @dialog_ready = true if result
    @ready_result = result
  end

  def await_js(expression, timeout: DEFAULT_TEST_TIMEOUT)
    fiber = @current_test_fiber
    raise 'await_js must be used within run_dialog_test' unless fiber.is_a?(Fiber)

    result = nil
    error = nil
    completed = false
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    @dialog_handle.eval_js_async(expression) do |payload|
      result = payload
      completed = true
      fiber.resume if fiber.alive?
    end

    timer = ::UI.start_timer(0.01, true) do
      next unless fiber.alive?

      if completed
        ::UI.stop_timer(timer)
      elsif Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        error = AICabinets::TestHarness::TimeoutError.new('Timed out waiting for HtmlDialog eval.')
        completed = true
        ::UI.stop_timer(timer)
        fiber.resume if fiber.alive?
      end
    end

    Fiber.yield

    ::UI.stop_timer(timer) if timer && ::UI.is_timer_running?(timer)

    raise error if error
    raise AICabinets::TestHarness::TimeoutError, 'Timed out waiting for HtmlDialog eval.' unless result

    return result[:value] if result[:ok]

    raise AICabinets::TestHarness::EvalError, result[:error]
  end

  def dialog_state
    ensure_dialog_ready
    await_js('AICabinetsTest.getState()')
  end

  def process_ui_events(interval = 0.01)
    super
  end
end
