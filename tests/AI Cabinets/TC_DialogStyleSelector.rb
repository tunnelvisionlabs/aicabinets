# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/test_harness')
Sketchup.require('aicabinets/ui/dialogs/insert_base_cabinet_dialog')

class TC_DialogStyleSelector < TestUp::TestCase
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

  DEFAULT_TIMEOUT = 3.0
  private_constant :DEFAULT_TIMEOUT, :READY_SCRIPT

  def setup
    cleanup_overrides
    @dialog_handle = AICabinets::TestHarness.open_dialog_for_tests
    @dialog_ready = false
    ensure_dialog_ready
  end

  def teardown
    teardown_html_dialog(@dialog_handle)
    @dialog_handle = nil
    cleanup_overrides
  end

  def test_probe_reports_disabled_styles_and_tooltip
    probe = await_js('AICabinets.UI.InsertBaseCabinet.emitProbeState()')

    assert_equal('base', probe[:style])
    assert_equal(%w[tall corner], probe[:disabled])
    assert_equal('Coming soon', probe[:tooltip])

    option_state = await_js(<<~JAVASCRIPT)
      (function () {
        var select = document.querySelector('[data-role="style-select"]');
        if (!select) {
          return null;
        }

        return Array.prototype.map.call(select.options, function (option) {
          return { value: option.value, disabled: option.disabled, title: option.title || '' };
        });
      })()
    JAVASCRIPT

    tall = option_state.find { |entry| entry['value'] == 'tall' }
    corner = option_state.find { |entry| entry['value'] == 'corner' }

    refute_nil(tall, 'Tall option should exist')
    assert(tall['disabled'], 'Tall option should be disabled')
    assert_equal('Coming soon', tall['title'])

    refute_nil(corner, 'Corner option should exist')
    assert(corner['disabled'], 'Corner option should be disabled')
    assert_equal('Coming soon', corner['title'])
  end

  def test_style_change_emits_event
    await_js(<<~JAVASCRIPT)
      (function () {
        var select = document.querySelector('[data-role="style-select"]');
        select.value = 'upper';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      })()
    JAVASCRIPT

    events = AICabinets::UI::Dialogs::InsertBaseCabinet.style_events_for_test
    assert_equal('upper', events.last)
  end

  def test_last_used_style_persists_across_dialogs
    await_js(<<~JAVASCRIPT)
      (function () {
        var select = document.querySelector('[data-role="style-select"]');
        select.value = 'upper';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      })()
    JAVASCRIPT

    AICabinets::UI::Dialogs::InsertBaseCabinet.send(:store_last_used_style)

    reopen_dialog

    probe = await_js('AICabinets.UI.InsertBaseCabinet.emitProbeState()')
    assert_equal('upper', probe[:style])
  end

  def test_disabled_override_falls_back_to_base
    write_override_style('tall')
    reopen_dialog

    probe = await_js('AICabinets.UI.InsertBaseCabinet.emitProbeState()')
    assert_equal('base', probe[:style])

    stored = JSON.parse(File.read(AICabinets::Defaults::OVERRIDES_PATH))
    assert_equal('tall', stored['last_used_style'])
  end

  def test_edit_prefill_uses_component_style
    dialog_module = AICabinets::UI::Dialogs::InsertBaseCabinet
    dialog = dialog_module.send(:ensure_dialog)

    params = AICabinets::Defaults.load_mm
    params[:cabinet_type] = 'upper'

    dialog_module.send(:set_dialog_context, mode: :edit, prefill: params, selection: { instances_count: 1 })
    dialog_module.send(:deliver_dialog_configuration, dialog)
    dialog_module.send(:deliver_form_defaults, dialog)

    probe = await_js('AICabinets.UI.InsertBaseCabinet.emitProbeState()')
    assert_equal('upper', probe[:style])
  ensure
    dialog_module.send(:set_dialog_context, mode: :insert, prefill: nil, selection: nil)
  end

  private

  def ensure_dialog_ready
    return if @dialog_ready

    await_js(READY_SCRIPT)
    @dialog_ready = true
  end

  def await_js(expression, timeout: DEFAULT_TIMEOUT)
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

  def cleanup_overrides
    overrides_path = AICabinets::Defaults::OVERRIDES_PATH
    FileUtils.rm_f(overrides_path)
  end

  def write_override_style(style)
    overrides_path = AICabinets::Defaults::OVERRIDES_PATH
    FileUtils.mkdir_p(File.dirname(overrides_path))
    File.write(overrides_path, JSON.pretty_generate('last_used_style' => style))
  end

  def reopen_dialog
    teardown_html_dialog(@dialog_handle)
    @dialog_handle = AICabinets::TestHarness.open_dialog_for_tests
    @dialog_ready = false
    ensure_dialog_ready
  end
end
