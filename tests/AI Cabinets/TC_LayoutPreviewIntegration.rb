# frozen_string_literal: true

require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/ui/dialog_console_bridge')

class TC_LayoutPreviewIntegration < TestUp::TestCase
  include TestUiPump

  HARNESS_PATH = File.expand_path('../../aicabinets/html/layout_preview/integration_harness.html', __dir__)
  DEFAULT_TIMEOUT = 4.0
  private_constant :HARNESS_PATH, :DEFAULT_TIMEOUT

  def setup
    skip('UI::HtmlDialog is unavailable in this SketchUp build.') unless defined?(UI::HtmlDialog)

    options = {
      dialog_title: 'Layout Preview Integration Harness',
      width: 480,
      height: 360,
      resizable: false,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    }

    @dialog = ::UI::HtmlDialog.new(options)
    AICabinets::UI::DialogConsoleBridge.register_dialog(@dialog)

    @requests = []
    @pending_eval = nil
    @eval_queue = []

    @dialog.add_action_callback('requestSelectBay') do |_context, bay_id|
      @requests << bay_id
    end
  end

  def teardown
    if defined?(AICabinets::UI::DialogConsoleBridge) && @dialog
      AICabinets::UI::DialogConsoleBridge.unregister_dialog(@dialog)
    end
    teardown_html_dialog(@dialog)
    @dialog = nil
  end

  def test_selection_round_trip_and_hygiene
    ensure_harness_ready
    AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)

    layout_model = {
      outer: { w_mm: 762, h_mm: 762 },
      bays: [
        { id: 'bay-left', role: 'bay', x_mm: 0,   y_mm: 0, w_mm: 254, h_mm: 762 },
        { id: 'bay-center', role: 'bay', x_mm: 254, y_mm: 0, w_mm: 254, h_mm: 762 },
        { id: 'bay-right', role: 'bay', x_mm: 508, y_mm: 0, w_mm: 254, h_mm: 762 }
      ],
      partitions: { orientation: 'vertical', positions_mm: [254, 508] },
      shelves: [],
      fronts: []
    }

    assert(render_layout(layout_model), 'Expected harness to render the layout model.')

    assert_request_select_bay('bay-center') do
      click_bay('bay-center')
    end

    assert(set_active_bay('bay-right', scope: :single), 'Expected setActiveBay to return true.')

    state = capture_preview_state
    refute_nil(state, 'Expected preview DOM state to be captured.')

    active_id = state[:activeId] || state['activeId']
    assert_equal('bay-right', active_id)

    scope_single = state[:scopeSingle].nil? ? state['scopeSingle'] : state[:scopeSingle]
    assert(scope_single, 'Expected single-bay scope to add scope-single class.')

    deemphasized = state[:deemphasizedCount] || state['deemphasizedCount']
    assert_equal(2, deemphasized, 'Expected non-active bays to be deemphasized in single scope.')

    aria_states = stringify_hash_keys(state[:ariaStates] || state['ariaStates'] || {})
    assert_equal('true', aria_states['bay-right'], 'Expected active bay aria-selected to be true.')
    assert_equal('false', aria_states['bay-left'], 'Expected inactive bay aria-selected to be false.')
    assert_equal('false', aria_states['bay-center'], 'Expected inactive bay aria-selected to be false.')

    events = AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)
    errors = events.select { |event| event[:level] == 'error' }
    assert_empty(errors, build_console_failure_message(errors))
  end

  private

  def ensure_harness_ready
    return if @harness_ready

    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @dialog.add_action_callback('__aicabinets_report_console_event') do |_context, payload|
        AICabinets::UI::DialogConsoleBridge.record_event(@dialog, payload)
        if @pending_eval
          pending = @pending_eval
          @pending_eval = nil
          pending.call
        end
      end

      @dialog.add_action_callback('layout_preview_integration_ready') do |_context, _payload|
        @harness_ready = true
        close_pump.call
      end

      @dialog.add_action_callback('layout_preview_integration_eval') do |_context, payload|
        store_eval_payload(payload)
        if @pending_eval
          pending = @pending_eval
          @pending_eval = nil
          pending.call
        end
      end

      @dialog.set_file(HARNESS_PATH)
      @dialog.show
    end

    flunk('Layout preview integration harness did not report ready state.') unless @harness_ready
  end

  def render_layout(model)
    ensure_harness_ready

    model_json = JSON.generate(model)
    await_eval(<<~JAVASCRIPT)
      (function () {
        var harness = window.AICabinetsLayoutPreview;
        if (!harness || typeof harness.renderLayout !== 'function') {
          return false;
        }
        return harness.renderLayout(#{model_json});
      })();
    JAVASCRIPT
  end

  def set_active_bay(bay_id, opts = {})
    ensure_harness_ready

    identifier_json = JSON.generate(bay_id.to_s)
    options_json = JSON.generate(opts || {})
    await_eval(<<~JAVASCRIPT)
      (function () {
        var harness = window.AICabinetsLayoutPreview;
        if (!harness || typeof harness.setActiveBay !== 'function') {
          return false;
        }
        return harness.setActiveBay(#{identifier_json}, #{options_json});
      })();
    JAVASCRIPT
  end

  def click_bay(bay_id)
    ensure_harness_ready

    identifier_json = JSON.generate(bay_id.to_s)
    await_eval(<<~JAVASCRIPT)
      (function () {
        var selector = '[data-role="bay"][data-id="' + #{identifier_json} + '"]';
        var element = document.querySelector(selector);
        if (!element) {
          return false;
        }
        var event = new MouseEvent('click', { bubbles: true });
        element.dispatchEvent(event);
        return true;
      })();
    JAVASCRIPT
  end

  def capture_preview_state
    ensure_harness_ready

    await_eval(<<~JAVASCRIPT)
      (function () {
        var root = document.querySelector('.lp-root');
        if (!root) {
          return null;
        }
        var result = {
          activeId: null,
          scopeSingle: root.classList.contains('scope-single'),
          deemphasizedCount: 0,
          ariaStates: {}
        };
        var active = root.querySelector('[data-role="bay"].is-active');
        if (active) {
          result.activeId = active.getAttribute('data-id') || null;
        }
        var bays = root.querySelectorAll('[data-role="bay"]');
        for (var index = 0; index < bays.length; index += 1) {
          var bay = bays[index];
          var id = bay.getAttribute('data-id') || String(index);
          if (bay.classList.contains('is-deemphasized')) {
            result.deemphasizedCount += 1;
          }
          result.ariaStates[id] = bay.getAttribute('aria-selected');
        }
        return result;
      })();
    JAVASCRIPT
  end

  def assert_request_select_bay(expected_id)
    ensure_harness_ready
    initial_count = @requests.length
    yield
    assert(@requests.length > initial_count, 'Expected requestSelectBay to be invoked.')
    assert_equal(expected_id.to_s, @requests.last.to_s)
  end

  def await_eval(expression)
    ensure_harness_ready

    payload = nil
    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @pending_eval = close_pump
      wrapped = <<~JAVASCRIPT
        (function () {
          var callback = window.sketchup && window.sketchup.layout_preview_integration_eval;
          if (!callback) {
            return;
          }
          try {
            var value = (function () { return #{expression}; })();
            callback(JSON.stringify({ ok: true, value: value }));
          } catch (error) {
            var message = error && error.message ? error.message : String(error);
            callback(JSON.stringify({ ok: false, message: message }));
          }
        })();
      JAVASCRIPT
      @dialog.execute_script(wrapped)
    end

    payload = @eval_queue.shift
    flunk('HtmlDialog eval did not return a payload.') unless payload
    return payload[:value] if payload[:ok]

    flunk("HtmlDialog eval failed: #{payload[:message]}")
  ensure
    @pending_eval = nil
  end

  def store_eval_payload(payload)
    data =
      if payload.is_a?(String) && !payload.empty?
        begin
          JSON.parse(payload, symbolize_names: true)
        rescue JSON::ParserError
          { ok: false, message: payload.to_s }
        end
      elsif payload.is_a?(Hash)
        payload.transform_keys { |key| key.to_sym rescue key }
      else
        { ok: true, value: payload }
      end
    @eval_queue << data
  end

  def build_console_failure_message(events)
    return 'No console events captured.' if events.empty?

    lines = ['Unexpected console errors:']
    events.each do |event|
      lines << "- [#{event[:level]}] #{event[:message]} (#{event[:dialog_id]})"
    end
    lines.join("\n")
  end

  def stringify_hash_keys(value)
    return {} unless value.is_a?(Hash)

    value.each_with_object({}) do |(key, entry), memo|
      memo[key.to_s] = entry
    end
  end
end
