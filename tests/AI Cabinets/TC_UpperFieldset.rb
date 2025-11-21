# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/test_harness')
Sketchup.require('aicabinets/ui/dialogs/insert_base_cabinet_dialog')

class TC_UpperFieldset < TestUp::TestCase
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
  private_constant :READY_SCRIPT

  def setup
    @dialog_handle = AICabinets::TestHarness.open_dialog_for_tests
    ensure_dialog_ready
  end

  def teardown
    teardown_html_dialog(@dialog_handle)
    @dialog_handle = nil
  end

  def test_upper_defaults_apply_once_and_preserve_user_values
    switch_to_upper

    defaults = await_js(<<~JAVASCRIPT)
      (function () {
        var width = document.querySelector('#field-width');
        var depth = document.querySelector('#field-depth');
        var height = document.querySelector('#field-height');
        var toeKick = document.querySelector('[data-field="toe_kick_height"]');

        return {
          width_mm: Number(width && width.dataset.mmValue),
          depth_mm: Number(depth && depth.dataset.mmValue),
          height_mm: Number(height && height.dataset.mmValue),
          toe_kick_hidden:
            !!(
              toeKick &&
              (toeKick.hasAttribute('hidden') ||
                toeKick.getAttribute('aria-hidden') === 'true' ||
                toeKick.hasAttribute('inert'))
            )
        };
      })()
    JAVASCRIPT

    assert_in_delta(762, defaults[:width_mm], 0.01)
    assert_in_delta(356, defaults[:depth_mm], 0.01)
    assert_in_delta(762, defaults[:height_mm], 0.01)
    assert(defaults[:toe_kick_hidden], 'Toe kick fields should be hidden for upper style')

    await_js(<<~JAVASCRIPT)
      (function () {
        var select = document.querySelector('[data-role="style-select"]');
        var width = document.querySelector('#field-width');
        if (!select || !width) {
          return;
        }

        width.value = '1010';
        width.dataset.mmValue = '1010';

        select.value = 'base';
        select.dispatchEvent(new Event('change', { bubbles: true }));
        select.value = 'upper';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      })()
    JAVASCRIPT

    restored = await_js(<<~JAVASCRIPT)
      (function () {
        var width = document.querySelector('#field-width');
        return width ? width.value : null;
      })()
    JAVASCRIPT

    assert_equal('1010', restored)
  end

  private

  def ensure_dialog_ready
    await_js(READY_SCRIPT)
  end

  def switch_to_upper
    await_js(<<~JAVASCRIPT)
      (function () {
        var select = document.querySelector('[data-role="style-select"]');
        if (!select) {
          return;
        }
        select.value = 'upper';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      })()
    JAVASCRIPT
  end

  def await_js(expression, timeout: 3.0)
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
end
