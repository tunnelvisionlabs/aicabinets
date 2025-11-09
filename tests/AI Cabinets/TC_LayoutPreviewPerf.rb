# frozen_string_literal: true

require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/ui/dialog_console_bridge')

class TC_LayoutPreviewPerf < TestUp::TestCase
  include TestUiPump

  HARNESS_PATH = File.expand_path('../../aicabinets/html/layout_preview/perf_harness.html', __dir__)
  DEFAULT_TIMEOUT = 12.0
  private_constant :HARNESS_PATH, :DEFAULT_TIMEOUT

  def setup
    skip('UI::HtmlDialog is unavailable in this SketchUp build.') unless defined?(UI::HtmlDialog)

    options = {
      dialog_title: 'Layout Preview Performance Harness',
      width: 840,
      height: 720,
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

  def test_stress_run_meets_thresholds
    ensure_harness_ready
    AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)

    start_ok = await_eval(<<~JAVASCRIPT)
      LayoutPreviewPerfHarness.startRun({ fixtureKey: 'stress12', iterations: 300, intervalMs: 12, seed: 42 });
    JAVASCRIPT
    assert(start_ok, 'Expected startRun to return true.')

    metrics = await_eval(<<~JAVASCRIPT)
      LayoutPreviewPerfHarness.whenIdle().then(function () {
        return LayoutPreviewPerfHarness.getMetricsSnapshot();
      });
    JAVASCRIPT

    assert_equal('idle', metrics[:status], 'Harness should report idle after the run completes.')
    assert_equal(metrics[:iteration_target], metrics[:iteration_count], 'Expected all iterations to complete.')
    assert_operator(metrics.dig(:samples, :update).to_i, :>=, 280, 'Expected update sample count near the iteration count.')
    assert_operator(metrics.dig(:samples, :frame).to_i, :>=, 250, 'Expected frame samples to track the run.')

    update_median = metrics.dig(:medians, :update_ms).to_f
    update_p95 = metrics.dig(:p95, :update_ms).to_f
    assert_operator(update_median, :<=, 100.0, 'Median update should be ≤ 100 ms.')
    assert_operator(update_p95, :<=, 200.0, '95th percentile update should stay near 2× the median.')

    raf_period = metrics[:raf_period_ms]
    if raf_period && raf_period.to_f > 20.0
      formatted = format('%.1f', raf_period.to_f)
      skip("requestAnimationFrame cadence is throttled (~#{formatted} ms); frame metrics are not reliable in this run.")
    end

    frame_median = metrics.dig(:medians, :frame_ms).to_f
    frame_p95 = metrics.dig(:p95, :frame_ms).to_f
    assert_operator(frame_median, :<=, 16.0, 'Median frame cost should be ≤ 16 ms.')
    assert_operator(frame_p95, :<=, 24.0, '95th percentile frame cost should stay within one extra frame.')

    node_drift_total = metrics.dig(:node_drift, :total).to_i
    assert_equal(0, node_drift_total, 'Expected no DOM node drift when bay counts remain constant.')

    final_hash = metrics[:last_params_hash]
    current_hash = await_eval('LayoutPreviewPerfHarness.currentParamsHash();')
    assert_equal(final_hash, current_hash, 'Final DOM state should match the last param hash.')

    memory_drift = metrics[:memory_drift_mb]
    if memory_drift
      assert_operator(memory_drift.to_f.abs, :<=, 1.0, 'Heap drift should remain near zero when metrics are available.')
    end

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

      @dialog.add_action_callback('layout_preview_perf_ready') do |_context, _payload|
        @harness_ready = true
        close_pump.call
      end

      @dialog.add_action_callback('layout_preview_perf_eval') do |_context, payload|
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

    flunk('Layout preview perf harness did not report ready state.') unless @harness_ready
  end

  def await_eval(expression)
    ensure_harness_ready

    payload = nil
    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @pending_eval = close_pump
      wrapped = <<~JAVASCRIPT
        (function () {
          var callback = window.sketchup && window.sketchup.layout_preview_perf_eval;
          if (!callback) {
            return;
          }
          var invokeCallback = function (result) {
            try {
              callback(JSON.stringify(result));
            } catch (error) {
              callback(JSON.stringify({ ok: false, message: error && error.message ? error.message : String(error) }));
            }
          };
          try {
            var value = (function () { return #{expression}; })();
            if (value && typeof value.then === 'function') {
              value.then(function (resolved) {
                invokeCallback({ ok: true, value: resolved });
              }).catch(function (error) {
                invokeCallback({ ok: false, message: error && error.message ? error.message : String(error) });
              });
              return;
            }
            invokeCallback({ ok: true, value: value });
          } catch (error) {
            var message = error && error.message ? error.message : String(error);
            invokeCallback({ ok: false, message: message });
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
