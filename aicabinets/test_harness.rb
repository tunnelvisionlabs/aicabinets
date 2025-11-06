# frozen_string_literal: true

require 'json'
require 'securerandom'

require 'aicabinets/ui/dialogs/insert_base_cabinet_dialog'

module AICabinets
  module TestHarness
    DEFAULT_TIMEOUT = 8.0
    module_function

    def open_dialog_for_tests
      unless defined?(::UI::HtmlDialog)
        raise 'UI::HtmlDialog is required to drive the HtmlDialog tests.'
      end

      dialog_module = AICabinets::UI::Dialogs::InsertBaseCabinet
      dialog_module.send(:enable_test_mode!)

      dialog = dialog_module.show
      raise 'Failed to create HtmlDialog for tests.' unless dialog

      @eval_results = {}
      @eval_callbacks = {}
      @dispatching_eval_callback = false

      DialogHandle.new(dialog)
    end

    def handle_eval_payload(payload)
      data = JSON.parse(payload.to_s)
      token = data['token']
      store_eval_result(token, data)
      notify_eval_callback(token, data)
    rescue JSON::ParserError => e
      warn("AI Cabinets: Unable to parse test eval payload: #{e.message}")
    end

    def store_eval_result(token, data)
      return unless token

      @eval_results[token] = data
    end

    def notify_eval_callback(token, data)
      return unless token

      callback = @eval_callbacks.delete(token)
      return unless callback

      begin
        @dispatching_eval_callback = true
        callback.call(normalize_eval_result(data))
      rescue StandardError => error
        warn("AI Cabinets: Error dispatching eval callback: #{error.message}")
      ensure
        @dispatching_eval_callback = false
      end
    end

    def register_eval_callback(token, callback)
      return unless token && callback

      @eval_callbacks[token] = callback
    end

    def dispatch_eval_failure(token, error)
      data = {
        'token' => token,
        'ok' => false,
        'error' => error.to_s
      }
      store_eval_result(token, data)
      notify_eval_callback(token, data)
    end

    def take_eval_result(token, timeout: DEFAULT_TIMEOUT)
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
          function dispatchTestResult(json) {
            if (window.sketchup && typeof window.sketchup.__aicabinets_test_eval === 'function') {
              window.sketchup.__aicabinets_test_eval(json);
              return true;
            }

            return false;
          }

          function scheduleDispatch(json) {
            var attempts = 0;

            function attemptDispatch() {
              if (dispatchTestResult(json)) {
                return;
              }

              if (attempts >= 400) {
                if (window.console && typeof window.console.warn === 'function') {
                  window.console.warn('AI Cabinets test harness: eval callback unavailable.');
                }
                return;
              }

              attempts += 1;
              window.setTimeout(attemptDispatch, 10);
            }

            attemptDispatch();
          }

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

            try {
              scheduleDispatch(JSON.stringify(message));
            } catch (error) {
              if (window.console && typeof window.console.error === 'function') {
                window.console.error('AI Cabinets test harness: failed to dispatch eval result.', error);
              }
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

    def dispatching_eval_callback?
      !!@dispatching_eval_callback
    end

    class DialogHandle
      def initialize(dialog)
        @dialog = dialog
      end

      def eval_js(*_args, **_kwargs)
        message = if @dialog
                    'HtmlDialog evals must be asynchronous in SketchUp tests. '\
                      'Use #eval_js_async and wait for the callback instead.'
                  else
                    'Dialog is closed.'
                  end
        error_class = @dialog ? SynchronousEvalUnsupportedError : RuntimeError
        raise(error_class, message)
      end

      def eval_js_async(expression, &on_complete)
        raise 'Dialog is closed.' unless @dialog

        token = TestHarness.next_token
        script = TestHarness.wrap_script(expression, token)

        TestHarness.register_eval_callback(token, on_complete) if block_given?

        dispatch = lambda do
          begin
            @dialog.execute_script(script)
          rescue StandardError => error
            TestHarness.dispatch_eval_failure(token, error)
          end
        end

        if TestHarness.dispatching_eval_callback?
          ::UI.start_timer(0, false) { dispatch.call }
        else
          dispatch.call
        end

        token
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
    class SynchronousEvalUnsupportedError < StandardError; end
  end
end
