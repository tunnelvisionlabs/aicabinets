# frozen_string_literal: true

require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/ui/dialog_console_bridge')

class TC_LayoutPreviewRenderer < TestUp::TestCase
  include TestUiPump

  DEMO_PATH = File.expand_path('../../aicabinets/html/layout_preview/renderer_demo.html', __dir__)
  DEFAULT_TIMEOUT = 4.0
  private_constant :DEMO_PATH, :DEFAULT_TIMEOUT

  def setup
    skip('UI::HtmlDialog is unavailable in this SketchUp build.') unless defined?(UI::HtmlDialog)

    options = {
      dialog_title: 'Layout Preview Renderer Demo',
      width: 520,
      height: 400,
      resizable: true,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    }

    @dialog = ::UI::HtmlDialog.new(options)
    AICabinets::UI::DialogConsoleBridge.register_dialog(@dialog)
    @pending_eval = nil
    @eval_queue = []
  end

  def teardown
    if defined?(AICabinets::UI::DialogConsoleBridge) && @dialog
      AICabinets::UI::DialogConsoleBridge.unregister_dialog(@dialog)
    end
    teardown_html_dialog(@dialog)
    @dialog = nil
  end

  def test_demo_load_has_no_console_errors
    ensure_demo_ready

    events = AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)
    errors = events.select { |event| event[:level] == 'error' }

    assert_empty(errors, build_console_failure_message(errors))
  end

  def test_layout_switches_have_no_console_errors
    ensure_demo_ready
    AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)

    click_layout_button('empty')
    click_layout_button('single')
    click_layout_button('triple')

    events = AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)
    errors = events.select { |event| event[:level] == 'error' }

    assert_empty(errors, build_console_failure_message(errors))
  end

  private

  def ensure_demo_ready
    return if @demo_ready

    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @dialog.add_action_callback('__aicabinets_report_console_event') do |_context, payload|
        AICabinets::UI::DialogConsoleBridge.record_event(@dialog, payload)
        if @pending_eval
          pending = @pending_eval
          @pending_eval = nil
          pending.call
        end
      end

      @dialog.add_action_callback('layout_preview_demo_ready') do |_context, _payload|
        @demo_ready = true
        close_pump.call
      end

      @dialog.add_action_callback('layout_preview_demo_eval') do |_context, payload|
        store_eval_payload(payload)
        if @pending_eval
          pending = @pending_eval
          @pending_eval = nil
          pending.call
        end
      end

      @dialog.set_file(DEMO_PATH)
      @dialog.show
    end

    flunk('Layout preview demo did not report ready state.') unless @demo_ready
  end

  def click_layout_button(key)
    ensure_demo_ready

    selector_json = JSON.generate(key)
    script = <<~JAVASCRIPT
      (function () {
        var selector = '[data-layout-key="' + #{selector_json} + '"]';
        var element = document.querySelector(selector);
        if (element) {
          element.click();
          return true;
        }
        return false;
      })()
    JAVASCRIPT

    result = await_eval(script)
    assert(result, "Expected layout button '#{key}' to exist.")
  end

  def await_eval(expression)
    ensure_demo_ready

    payload = nil
    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @pending_eval = close_pump
      wrapped = <<~JAVASCRIPT
        (function () {
          var callback = window.sketchup && window.sketchup.layout_preview_demo_eval;
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
end
