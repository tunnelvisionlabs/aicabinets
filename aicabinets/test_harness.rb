# frozen_string_literal: true

require 'json'
require 'securerandom'

require 'aicabinets/ui/dialogs/insert_base_cabinet_dialog'

module AICabinets
  module TestHarness
    DEFAULT_TIMEOUT = 5.0
    module_function

    def open_dialog_for_tests
      unless defined?(::UI::HtmlDialog)
        raise 'UI::HtmlDialog is required to drive the HtmlDialog tests.'
      end

      dialog_module = AICabinets::UI::Dialogs::InsertBaseCabinet
      dialog_module.send(:enable_test_mode!)

      dialog = dialog_module.show
      raise 'Failed to create HtmlDialog for tests.' unless dialog

      DialogHandle.new(dialog)
    end

    def handle_eval_payload(payload)
      data = JSON.parse(payload.to_s)
      token = data['token']
      store_eval_result(token, data)
    rescue JSON::ParserError => e
      warn("AI Cabinets: Unable to parse test eval payload: #{e.message}")
    end

    def store_eval_result(token, data)
      return unless token

      @eval_results ||= {}
      @eval_results[token] = data
    end

    def take_eval_result(token, timeout: DEFAULT_TIMEOUT)
      @eval_results ||= {}
      deadline = Time.now + timeout
      loop do
        data = @eval_results.delete(token)
        return normalize_eval_result(data) if data

        raise TimeoutError, "Timed out waiting for eval result (#{token})." if Time.now > deadline

        sleep(0.01)
      end
    end

    def normalize_eval_result(data)
      return { ok: false, error: 'No data' } unless data.is_a?(Hash)

      ok = data['ok']
      if ok
        value_json = data['value']
        begin
          value = value_json.nil? ? nil : JSON.parse(value_json)
        rescue JSON::ParserError
          value = value_json
        end
        { ok: true, value: value }
      else
        { ok: false, error: data['error'].to_s }
      end
    end

    def next_token
      SecureRandom.uuid
    end

    def wrap_script(expression, token)
      token_json = JSON.generate(token.to_s)
      <<~JAVASCRIPT
        (function () {
          function postResult(success, payload) {
            var message = { token: #{token_json}, ok: success };
            if (success) {
              try {
                message.value = JSON.stringify(payload);
              } catch (error) {
                message.ok = false;
                message.error = 'Serialize error: ' + (error && error.message ? error.message : String(error));
              }
            } else {
              message.error = payload && payload.message ? payload.message : String(payload);
            }
            if (window.sketchup && typeof window.sketchup.__aicabinets_test_eval === 'function') {
              window.sketchup.__aicabinets_test_eval(JSON.stringify(message));
            }
          }

          function resolveResult(value) {
            postResult(true, value);
          }

          function rejectResult(error) {
            postResult(false, error);
          }

          try {
            var outcome = (function () { return #{expression}; })();
            if (outcome && typeof outcome.then === 'function') {
              outcome.then(resolveResult, rejectResult);
            } else {
              resolveResult(outcome);
            }
          } catch (error) {
            rejectResult(error);
          }
        })();
      JAVASCRIPT
    end

    class DialogHandle
      def initialize(dialog)
        @dialog = dialog
      end

      def eval_js(expression, timeout: DEFAULT_TIMEOUT)
        raise 'Dialog is closed.' unless @dialog

        token = TestHarness.next_token
        script = TestHarness.wrap_script(expression, token)
        @dialog.execute_script(script)
        result = TestHarness.take_eval_result(token, timeout: timeout)
        raise EvalError, result[:error] unless result[:ok]

        result[:value]
      end

      def close
        return unless @dialog

        begin
          @dialog.close
        ensure
          AICabinets::UI::Dialogs::InsertBaseCabinet.send(:disable_test_mode!)
          @dialog = nil
        end
      end
    end

    class EvalError < StandardError; end
    class TimeoutError < StandardError; end
  end
end
