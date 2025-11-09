# frozen_string_literal: true

require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/ui/dialog_console_bridge')
Sketchup.require('aicabinets/ui/layout_preview/dialog')

class TC_LayoutPreviewSelectionSync < TestUp::TestCase
  include TestUiPump

  DIALOG_PATH = File.expand_path('../../aicabinets/html/layout_preview/dialog.html', __dir__)
  DEFAULT_TIMEOUT = 4.0
  private_constant :DIALOG_PATH, :DEFAULT_TIMEOUT

  def setup
    skip('UI::HtmlDialog is unavailable in this SketchUp build.') unless defined?(UI::HtmlDialog)

    options = {
      dialog_title: 'Layout Preview Selection Sync',
      width: 420,
      height: 320,
      resizable: false,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    }

    @dialog = ::UI::HtmlDialog.new(options)
    AICabinets::UI::DialogConsoleBridge.register_dialog(@dialog)

    @form = RecordingForm.new
    @bridge = AICabinets::UI::LayoutPreview::SelectionSyncBridge.new(@dialog, form: @form)

    @pending_eval = nil
    @eval_queue = []
  end

  def teardown
    if defined?(AICabinets::UI::DialogConsoleBridge) && @dialog
      AICabinets::UI::DialogConsoleBridge.unregister_dialog(@dialog)
    end
    teardown_html_dialog(@dialog)
    @dialog = nil
    @bridge = nil
  end

  def test_selection_flow_syncs_both_directions_without_console_errors
    ensure_dialog_ready

    layout_model = {
      outer: { w_mm: 914, h_mm: 762 },
      bays: [
        { id: 'bay-left', role: 'bay', x_mm: 0, y_mm: 0, w_mm: 305, h_mm: 762 },
        { id: 'bay-center', role: 'bay', x_mm: 305, y_mm: 0, w_mm: 305, h_mm: 762 },
        { id: 'bay-right', role: 'bay', x_mm: 610, y_mm: 0, w_mm: 304, h_mm: 762 }
      ],
      fronts: []
    }

    assert(render_layout(layout_model), 'Expected LayoutPreviewDialog.renderLayout to succeed.')

    assert_request_select_bay_for('bay-center') do
      click_bay('bay-center')
    end

    @bridge.set_active_bay('bay-right', scope: :single)

    state = await_eval(<<~JAVASCRIPT)
      (function () {
        var root = document.querySelector('.lp-root');
        if (!root) {
          return null;
        }
        var active = root.querySelector('[data-role="bay"].is-active');
        var deemphasized = root.querySelectorAll('[data-role="bay"].is-deemphasized').length;
        return {
          activeId: active ? active.getAttribute('data-id') : null,
          scopeSingle: root.classList.contains('scope-single'),
          deemphasizedCount: deemphasized
        };
      })();
    JAVASCRIPT

    refute_nil(state, 'Expected preview state to be captured.')
    assert_equal('bay-right', state[:activeId] || state['activeId'])
    scope_single = state[:scopeSingle].nil? ? state['scopeSingle'] : state[:scopeSingle]
    assert(scope_single, 'Expected single-bay scope to add scope-single class.')
    count = state[:deemphasizedCount] || state['deemphasizedCount']
    assert_equal(2, count, 'Expected non-active bays to be deemphasized in single scope.')

    events = AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)
    errors = events.select { |event| event[:level] == 'error' }
    assert_empty(errors, build_console_failure_message(errors))
  end

  private

  def ensure_dialog_ready
    return if @dialog_ready

    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @dialog.add_action_callback('__aicabinets_report_console_event') do |_context, payload|
        AICabinets::UI::DialogConsoleBridge.record_event(@dialog, payload)
        if @pending_eval
          pending = @pending_eval
          @pending_eval = nil
          pending.call
        end
      end

      @dialog.add_action_callback('layout_preview_ready') do |_context, _payload|
        @dialog_ready = true
        close_pump.call
      end

      @dialog.add_action_callback('layout_preview_eval') do |_context, payload|
        store_eval_payload(payload)
        if @pending_eval
          pending = @pending_eval
          @pending_eval = nil
          pending.call
        end
      end

      @dialog.set_file(DIALOG_PATH)
      @dialog.show
    end

    flunk('Layout preview dialog did not report ready state.') unless @dialog_ready
  end

  def render_layout(model)
    ensure_dialog_ready

    model_json = JSON.generate(model)
    await_eval(<<~JAVASCRIPT)
      (function () {
        var api = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.LayoutPreviewDialog;
        if (!api || typeof api.renderLayout !== 'function') {
          return false;
        }
        return api.renderLayout(#{model_json});
      })();
    JAVASCRIPT
  end

  def click_bay(bay_id)
    ensure_dialog_ready

    identifier_json = JSON.generate(bay_id.to_s)
    await_eval(<<~JAVASCRIPT)
      (function () {
        var id = #{identifier_json};
        var selector = '[data-role="bay"][data-id="' + id + '"]';
        var element = document.querySelector(selector);
        if (!element) {
          return false;
        }
        element.dispatchEvent(new Event('click', { bubbles: true }));
        return true;
      })();
    JAVASCRIPT
  end

  def assert_request_select_bay_for(expected_id)
    ensure_dialog_ready
    initial_count = @form.selected_ids.length
    yield
    assert(@form.selected_ids.length > initial_count, 'Expected a select_bay call from the preview click.')
    assert_equal(expected_id.to_s, @form.selected_ids.last.to_s)
  end

  def await_eval(expression)
    ensure_dialog_ready

    payload = nil
    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @pending_eval = close_pump
      wrapped = <<~JAVASCRIPT
        (function () {
          var callback = window.sketchup && window.sketchup.layout_preview_eval;
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

  class RecordingForm
    attr_reader :selected_ids

    def initialize
      @selected_ids = []
    end

    def select_bay(bay_id)
      @selected_ids << bay_id
    end
  end
end
