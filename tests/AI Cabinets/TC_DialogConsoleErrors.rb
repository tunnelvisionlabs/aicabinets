# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/test_harness')
Sketchup.require('aicabinets/ui/dialog_console_bridge')

class TC_DialogConsoleErrors < TestUp::TestCase
  include TestUiPump

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

  DEFAULT_PUMP_TIMEOUT = 3.0
  private_constant :DEFAULT_PUMP_TIMEOUT

  def setup
    @dialog_handle = AICabinets::TestHarness.open_dialog_for_tests
    @dialog_ready = false
    ensure_dialog_ready
    drain_console_events(@dialog_handle)
  end

  def teardown
    teardown_html_dialog(@dialog_handle)
    @dialog_handle = nil
  end

  def test_insert_dialog_boot_has_no_console_errors
    ensure_dialog_ready
    assert_no_console_errors(@dialog_handle, 'Insert dialog boot')
  end

  def test_insert_dialog_partition_toggle_has_no_console_errors
    ensure_dialog_ready
    await_js('AICabinetsTest.setPartitionMode("vertical")')
    assert_no_console_errors(@dialog_handle, 'Partition mode toggle')
  end

  def test_fixture_reports_onload_error
    errors = capture_fixture_errors(
      dialog_id: 'fixture-onload',
      on_load: 'throw new Error("fixture load failure");'
    )

    assert_event_message_includes(errors, 'fixture load failure')
    assert_event_dialog_id_includes(errors, 'fixture-onload')
  end

  def test_fixture_reports_unhandled_rejection
    errors = capture_fixture_errors(
      dialog_id: 'fixture-rejection',
      on_load: 'Promise.reject(new Error("fixture rejection"));'
    )

    assert_event_message_includes(errors, 'fixture rejection')
    assert_event_dialog_id_includes(errors, 'fixture-rejection')
  end

  def test_fixture_reports_console_error
    errors = capture_fixture_errors(
      dialog_id: 'fixture-console-error',
      on_load: 'console.error("fixture console failure");'
    )

    assert_event_message_includes(errors, 'fixture console failure')
    assert_event_dialog_id_includes(errors, 'fixture-console-error')
  end

  private

  def ensure_dialog_ready
    return if @dialog_ready

    await_js(READY_SCRIPT)
    @dialog_ready = true
  end

  def await_js(expression, timeout: DEFAULT_PUMP_TIMEOUT)
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

  def drain_console_events(target)
    if target.respond_to?(:drain_console_events)
      target.drain_console_events
    else
      AICabinets::UI::DialogConsoleBridge.drain_events(target)
    end
  end

  def peek_console_events(target)
    if target.respond_to?(:peek_console_events)
      target.peek_console_events
    else
      AICabinets::UI::DialogConsoleBridge.peek_events(target)
    end
  end

  def assert_no_console_errors(target, phase)
    events = drain_console_events(target)
    errors = events.select { |event| event[:level] == 'error' }
    return if errors.empty?

    message = build_console_failure_message(errors, phase)
    flunk(message)
  end

  def build_console_failure_message(events, phase)
    formatted = events.map do |event|
      location = [event[:url], event[:line], event[:column]].compact.join(':')
      parts = []
      parts << "[#{event[:dialog_id] || 'unknown'}]"
      parts << event[:level]
      parts << (event[:message] || '(no message)')
      parts << "@ #{location}" unless location.empty?
      details = parts.compact.join(' ')
      stack = event[:stack]
      stack ? "#{details}\n#{stack}" : details
    end

    <<~MESSAGE
      Expected no console errors during #{phase}.
      Captured events:
      #{formatted.join("\n\n")}
    MESSAGE
  end

  def capture_fixture_errors(dialog_id:, on_load:)
    errors = []

    with_console_fixture(dialog_id: dialog_id, on_load: on_load) do |dialog|
      wait_for_console_event(dialog, level: 'error')
      drained = drain_console_events(dialog)
      errors = drained.select { |event| event[:level] == 'error' }
    end

    refute_empty(errors, 'Expected at least one error-level console event.')
    errors
  end

  def wait_for_console_event(target, level:, timeout: DEFAULT_PUMP_TIMEOUT)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f

    loop do
      events = peek_console_events(target)
      return events if events.any? { |event| event[:level] == level }

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        flunk("Timed out waiting for #{level}-level console event.")
      end

      with_modal_pump(timeout: 0.05) { |_pump, _close_pump| }
    end
  end

  def assert_event_message_includes(events, expected)
    messages = events.map { |event| event[:message].to_s }
    assert(messages.any? { |message| message.include?(expected) }, "Expected event message to include '#{expected}'.")
  end

  def assert_event_dialog_id_includes(events, expected)
    ids = events.map { |event| event[:dialog_id].to_s }
    assert(ids.any? { |dialog_id| dialog_id.include?(expected) }, "Expected dialog identifier to include '#{expected}'.")
  end

  def with_console_fixture(dialog_id:, on_load:, interaction: nil)
    raise ArgumentError, 'with_console_fixture requires a block.' unless block_given?

    dialog = ::UI::HtmlDialog.new(
      dialog_title: 'AI Cabinets Console Fixture',
      width: 320,
      height: 200,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    )

    bridge_path = File.expand_path('../../aicabinets/ui/dialogs/console_bridge.js', __dir__)
    bridge_url = file_url_for(bridge_path)
    html = fixture_html(dialog_id: dialog_id, bridge_url: bridge_url, on_load: on_load, interaction: interaction)

    AICabinets::UI::DialogConsoleBridge.register_dialog(dialog)

    begin
      with_modal_pump(timeout: DEFAULT_PUMP_TIMEOUT) do |_pump, close_pump|
        dialog.add_action_callback('__aicabinets_report_console_event') do |_context, payload|
          AICabinets::UI::DialogConsoleBridge.record_event(dialog, payload)
          close_pump.call
        end

        dialog.add_action_callback('fixture_ready') do |_context, _payload|
          close_pump.call
        end

        dialog.set_html(html)
        dialog.show
      end

      yield(dialog)
    ensure
      teardown_html_dialog(dialog)
      AICabinets::UI::DialogConsoleBridge.unregister_dialog(dialog)
    end
  end

  def fixture_html(dialog_id:, bridge_url:, on_load:, interaction: nil)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en" data-dialog-id="#{dialog_id}">
        <head>
          <meta charset="utf-8" />
          <title>Console Fixture</title>
          <script src="#{bridge_url}"></script>
          <script>
            (function () {
              function ready() {
                if (window.sketchup && typeof window.sketchup.fixture_ready === 'function') {
                  window.sketchup.fixture_ready('ready');
                }
              }

              window.addEventListener('DOMContentLoaded', function () {
                ready();
                #{on_load}
              });

              window.addEventListener('load', ready);
            })();
          </script>
        </head>
        <body>
          <button id="fixture-action" type="button">Action</button>
          <script>
            (function () {
              var action = document.getElementById('fixture-action');
              if (!action) {
                return;
              }

              action.addEventListener('click', function () {
                #{interaction}
              });
            })();
          </script>
        </body>
      </html>
    HTML
  end

  def file_url_for(path)
    normalized = File.expand_path(path).tr('\\', '/')
    return "file:///#{normalized}" if normalized.match?(/^[a-zA-Z]:\//)
    return "file://#{normalized}" if normalized.start_with?('/')

    "file:///#{normalized}"
  end
end
