# frozen_string_literal: true

require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/features')
Sketchup.require('aicabinets/test_harness')
Sketchup.require('aicabinets/ui/dialog_console_bridge')

class TC_InsertBase_PreviewEmbed < TestUp::TestCase
  include TestUiPump

  DEFAULT_TIMEOUT = 8.0
  PREVIEW_READY_SCRIPT = <<~JAVASCRIPT
    (function () {
      var attempts = 0;

      function wait(resolve, reject) {
        var container = document.querySelector('[data-role="layout-preview-container"]');
        if (container && container.querySelector('svg')) {
          resolve(true);
          return;
        }

        attempts += 1;
        if (attempts > 600) {
          reject(new Error('Layout preview did not mount.'));
          return;
        }

        window.setTimeout(function () {
          wait(resolve, reject);
        }, 10);
      }

      return new Promise(function (resolve, reject) {
        wait(resolve, reject);
      });
    })()
  JAVASCRIPT
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
  PREVIEW_STATE_SCRIPT = <<~JAVASCRIPT
    (function () {
      var container = document.querySelector('[data-role="layout-preview-container"]');
      if (!container) {
        return null;
      }
      var root = container.querySelector('.lp-root');
      var bays = container.querySelectorAll('[data-role="bay"]');
      var activeId = null;
      var ariaSelectedTrue = [];
      for (var index = 0; index < bays.length; index += 1) {
        var node = bays[index];
        var id = node.getAttribute('data-id');
        if (node.classList.contains('is-active')) {
          activeId = id;
        }
        if (node.getAttribute('aria-selected') === 'true') {
          ariaSelectedTrue.push(id);
        }
      }
      return {
        bayCount: bays.length,
        activeId: activeId,
        ariaSelectedTrue: ariaSelectedTrue,
        scopeSingle: root ? root.classList.contains('scope-single') : false
      };
    })()
  JAVASCRIPT
  PREVIEW_FRONT_SHELF_STATE_SCRIPT = <<~JAVASCRIPT
    (function () {
      var container = document.querySelector('[data-role="layout-preview-container"]');
      if (!container) {
        return null;
      }

      var result = { doors: [], shelves: [] };

      var doorNodes = container.querySelectorAll('[data-role="front"][data-front="door"]');
      doorNodes.forEach(function (node) {
        var style = node.getAttribute('data-style') || null;
        var hinges = node.querySelectorAll('.lp-door-hinge').length;
        var gaps = node.querySelectorAll('.lp-door-gap').length;
        result.doors.push({ style: style, hingeCount: hinges, gapCount: gaps });
      });

      var shelfGroups = container.querySelectorAll('[data-role="bay-shelves"]');
      shelfGroups.forEach(function (group) {
        var bayId = group.getAttribute('data-bay-id') || null;
        var positions = [];
        group.querySelectorAll('line').forEach(function (line) {
          var y = Number(line.getAttribute('y1'));
          if (!Number.isNaN(y)) {
            positions.push(y);
          }
        });
        result.shelves.push({ bayId: bayId, yPositions: positions });
      });

      return result;
    })()
  JAVASCRIPT
  PREVIEW_DISABLED_STATE_SCRIPT = <<~JAVASCRIPT
    (function () {
      var pane = document.querySelector('[data-role="layout-preview-pane"]');
      var container = document.querySelector('[data-role="layout-preview-container"]');
      return {
        hasPreviewClass: document.body.classList.contains('has-layout-preview'),
        paneHidden: pane ? pane.hasAttribute('hidden') : true,
        svgCount: container ? container.querySelectorAll('svg').length : 0,
        cssLinks: document.querySelectorAll('link[data-layout-preview-css]').length,
        scriptHandles: document.querySelectorAll('script[data-layout-preview-script]').length
      };
    })()
  JAVASCRIPT
  private_constant :DEFAULT_TIMEOUT, :PREVIEW_READY_SCRIPT, :READY_SCRIPT,
                    :PREVIEW_STATE_SCRIPT, :PREVIEW_FRONT_SHELF_STATE_SCRIPT,
                    :PREVIEW_DISABLED_STATE_SCRIPT

  def setup
    @original_flag = AICabinets::Features.layout_preview?
    @dialog_handle = nil
    @dialog_ready = false
  end

  def teardown
    close_dialog
    restore_feature_flag
  end

  def test_preview_embed_smoke
    AICabinets::Features.enable_layout_preview!
    open_dialog
    ensure_dialog_ready
    await_js('AICabinetsTest.setPartitionMode("vertical")')
    await_js('AICabinetsTest.setTopCount(2)')
    pump_events
    await_js(PREVIEW_READY_SCRIPT)

    svg_count = fetch_svg_count
    assert(svg_count >= 1, 'Preview should render at least one <svg> element when enabled.')

    assert_equal(0, selected_bay_index, 'Initial selected bay should be the first bay.')

    initial_state = fetch_preview_state
    assert(initial_state['bayCount'] >= 3, 'Preview test expects at least three bays to exercise selection sync.')

    click_bay('bay-2')
    pump_events
    assert_equal(1, selected_bay_index, 'Preview click should update Ruby-selected bay index.')

    host = preview_host
    refute_nil(host, 'Preview host should be accessible while test mode is enabled.')
    assert(host.set_active_bay('bay-3', scope: :single), 'Ruby->JS setActiveBay should report success.')
    pump_events

    preview_state = fetch_preview_state
    refute_nil(preview_state, 'Preview state payload should be available.')
    assert_equal('bay-3', preview_state['activeId'])
    assert_includes(preview_state['ariaSelectedTrue'], 'bay-3', 'Active bay should advertise aria-selected=true.')
    assert(preview_state['scopeSingle'], 'Single-bay scope should add the scope-single class.')

    resize_dialog(560, 480)
    pump_events
    assert(fetch_svg_count >= 1, 'Preview should remain rendered after resizing the dialog.')

    assert_no_console_errors(@dialog_handle, 'Preview-enabled dialog interaction')

    close_dialog

    AICabinets::Features.disable_layout_preview!
    open_dialog
    ensure_dialog_ready

    disabled_state = await_js(PREVIEW_DISABLED_STATE_SCRIPT)
    refute_nil(disabled_state, 'Expected preview state payload when feature flag is disabled.')
    refute(disabled_state['hasPreviewClass'], 'Preview CSS hook should stay inactive when the feature is disabled.')
    assert(disabled_state['paneHidden'], 'Preview pane should remain hidden when the feature is disabled.')
    assert_equal(0, disabled_state['svgCount'], 'Preview assets should not render when disabled.')
    assert_equal(0, disabled_state['cssLinks'], 'Preview CSS should not load when the feature is disabled.')
    assert_equal(0, disabled_state['scriptHandles'], 'Preview scripts should not load when the feature is disabled.')

    assert_no_console_errors(@dialog_handle, 'Preview-disabled dialog boot')
  ensure
    close_dialog
  end

  def test_preview_updates_global_front_and_shelves_without_partitions
    AICabinets::Features.enable_layout_preview!
    open_dialog
    ensure_dialog_ready

    await_js('AICabinetsTest.setPartitionMode("none")')
    pump_events
    await_js(PREVIEW_READY_SCRIPT)

    await_js('AICabinetsTest.setTopFront("doors_right")')
    await_js('AICabinetsTest.setTopShelves(3)')
    pump_events
    await_js(PREVIEW_READY_SCRIPT)

    state = await_js(PREVIEW_FRONT_SHELF_STATE_SCRIPT)
    refute_nil(state, 'Expected preview state payload for cabinet configuration.')

    doors = Array(state['doors'])
    assert_equal(1, doors.length, 'Expected a single cabinet-wide door overlay.')
    door = doors.first
    assert_equal('doors_right', door['style'])
    assert_equal(1, door['hingeCount'])
    assert_equal(0, door['gapCount'])

    shelves = Array(state['shelves'])
    assert_equal(1, shelves.length, 'Expected cabinet shelf group to render.')
    cabinet = shelves.first
    assert_equal('cabinet', cabinet['bayId'])
    assert_equal(3, Array(cabinet['yPositions']).length, 'Expected three shelf indicators for the cabinet.')

    await_js('AICabinetsTest.setTopFront("doors_double")')
    await_js('AICabinetsTest.setTopShelves(1)')
    pump_events
    await_js(PREVIEW_READY_SCRIPT)

    updated = await_js(PREVIEW_FRONT_SHELF_STATE_SCRIPT)
    refute_nil(updated, 'Expected preview state payload after updating cabinet fronts and shelves.')

    updated_doors = Array(updated['doors'])
    assert_equal(1, updated_doors.length, 'Expected a single cabinet-wide door overlay after updates.')
    assert_equal('doors_double', updated_doors.first['style'])
    assert_equal(0, updated_doors.first['hingeCount'])
    assert_equal(1, updated_doors.first['gapCount'])

    updated_shelves = Array(updated['shelves'])
    assert_equal(1, updated_shelves.length, 'Expected cabinet shelf group to persist after updates.')
    assert_equal(1, Array(updated_shelves.first['yPositions']).length, 'Expected one shelf indicator after update.')

    stepped_value = await_js(<<~JAVASCRIPT)
      (function () {
        var input = document.querySelector('#field-shelves');
        if (!input) {
          throw new Error('Shelves input not found.');
        }
        if (typeof input.focus === 'function') {
          input.focus();
        }
        if (typeof input.stepUp === 'function') {
          input.stepUp();
        } else {
          var numeric = parseInt(input.value || '0', 10);
          if (!Number.isFinite(numeric)) {
            numeric = 0;
          }
          input.value = String(numeric + 1);
        }
        var event = new Event('input', { bubbles: true });
        input.dispatchEvent(event);
        return Number(input.value || 0);
      })()
    JAVASCRIPT
    assert_equal(2, stepped_value, 'Shelves stepper script should increment the input value.')
    pump_events
    await_js(PREVIEW_READY_SCRIPT)

    immediate = await_js(PREVIEW_FRONT_SHELF_STATE_SCRIPT)
    refute_nil(immediate, 'Expected preview state payload after shelf input event.')
    immediate_shelves = Array(immediate['shelves'])
    assert_equal(1, immediate_shelves.length, 'Expected cabinet shelf group to remain after input change.')
    assert_equal(2, Array(immediate_shelves.first['yPositions']).length,
                 'Shelf count should update immediately on input without blurring the field.')

    assert_no_console_errors(@dialog_handle, 'Global fronts and shelves synchronization')
  ensure
    close_dialog
  end

  private

  def open_dialog
    close_dialog
    @dialog_ready = false
    @dialog_handle = AICabinets::TestHarness.open_dialog_for_tests
  end

  def close_dialog
    return unless @dialog_handle

    begin
      @dialog_handle.close
    rescue StandardError
      # Ignore dialog close errors in teardown.
    ensure
      TestUiPump.teardown_html_dialog(nil)
      @dialog_handle = nil
      @dialog_ready = false
    end
  end

  def ensure_dialog_ready
    return if @dialog_ready

    await_js(READY_SCRIPT)
    @dialog_ready = true
  end

  def await_js(expression, timeout: DEFAULT_TIMEOUT)
    raise 'Dialog handle not available.' unless @dialog_handle

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

  def fetch_svg_count
    script = <<~JAVASCRIPT
      (function () {
        var container = document.querySelector('[data-role="layout-preview-container"]');
        return container ? container.querySelectorAll('svg').length : 0;
      })()
    JAVASCRIPT
    value = await_js(script)
    Integer(value || 0)
  end

  def fetch_preview_state
    value = await_js(PREVIEW_STATE_SCRIPT)
    value || {}
  end

  def click_bay(identifier)
    id_json = JSON.generate(identifier.to_s)
    script = <<~JAVASCRIPT
      (function () {
        var id = #{id_json};
        var selector = '[data-role="layout-preview-container"] [data-role="bay"][data-id="' + id + '"]';
        var nodes = document.querySelectorAll('[data-role="layout-preview-container"] [data-role="bay"]');
        var ids = [];
        for (var index = 0; index < nodes.length; index += 1) {
          ids.push(nodes[index].getAttribute('data-id'));
        }
        var element = document.querySelector(selector);
        if (!element) {
          return { ok: false, ids: ids };
        }
        element.dispatchEvent(new Event('click', { bubbles: true }));
        return { ok: true, ids: ids };
      })()
    JAVASCRIPT
    result = await_js(script)
    return true if result && result['ok']

    ids = result && result['ids'].is_a?(Array) ? result['ids'].compact : []
    description = ids.empty? ? 'no bays were located' : "available bays: #{ids.map(&:inspect).join(', ')}"
    message = "Preview bay #{identifier.inspect} was not found; unable to simulate click (#{description})."
    flunk(message)
  end

  def pump_events(delay = 0.1)
    with_modal_pump(timeout: delay + 0.25) do |_dialog, close_pump|
      UI.start_timer(delay, false) { close_pump.call }
    end
  end

  def resize_dialog(width, height)
    dialog = AICabinets::UI::Dialogs::InsertBaseCabinet.send(:ensure_dialog)
    return unless dialog

    dialog.set_size(width, height)
  end

  def selected_bay_index
    AICabinets::UI::Dialogs::InsertBaseCabinet.send(:selected_bay_index)
  end

  def preview_host
    AICabinets::UI::Dialogs::InsertBaseCabinet.send(:layout_preview_test_host)
  end

  def assert_no_console_errors(handle, phase)
    events = handle ? handle.drain_console_events : []
    errors = events.select { |event| event[:level] == 'error' }
    return if errors.empty?

    message = build_console_failure_message(errors, phase)
    flunk(message)
  end

  def build_console_failure_message(events, phase)
    details = events.map do |event|
      location = [event[:url], event[:line], event[:column]].compact.join(':')
      parts = []
      parts << "[#{event[:dialog_id] || 'unknown'}]"
      parts << event[:level]
      parts << (event[:message] || '(no message)')
      parts << "@ #{location}" unless location.empty?
      stack = event[:stack]
      stack ? "#{parts.compact.join(' ')}\n#{stack}" : parts.compact.join(' ')
    end

    <<~MESSAGE
      Expected no console errors during #{phase}.
      Captured events:
      #{details.join("\n\n")}
    MESSAGE
  end

  def restore_feature_flag
    AICabinets::Features.reset!
    case @original_flag
    when true
      AICabinets::Features.enable_layout_preview!
    when false
      AICabinets::Features.disable_layout_preview!
    end
  end
end
