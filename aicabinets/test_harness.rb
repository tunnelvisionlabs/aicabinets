# frozen_string_literal: true

require 'json'
require 'securerandom'

require 'aicabinets/ui/dialogs/insert_base_cabinet_dialog'
require 'aicabinets/ui/dialog_console_bridge'
require 'aicabinets/defaults'
require 'aicabinets/params_sanitizer'

Sketchup.require('aicabinets/ops/insert_base_cabinet')
Sketchup.require('aicabinets/ops/edit_base_cabinet')

module AICabinets
  module TestHarness
    DEFAULT_TIMEOUT = 8.0
    ConsoleBridge = AICabinets::UI::DialogConsoleBridge
    private_constant :ConsoleBridge
    module_function

    TEST_MODE = true unless const_defined?(:TEST_MODE)

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
      @dialog_boot_states = {}.compare_by_identity
      @dialog_eval_queues = {}.compare_by_identity

      initialize_dialog_state(dialog)

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

    def handle_boot_event(dialog, phase)
      return unless dialog

      mapping = {
        'dom-loading' => :dom_loading,
        'dom-ready' => :dom_ready,
        'app-ready' => :app_ready
      }
      state = mapping.fetch(phase.to_s, :dom_loading)

      dialog_boot_states[dialog] = state

      return unless ready_state?(state)

      flush_eval_queue(dialog)
    end

    def drain_console_events(dialog)
      return [] unless dialog

      ConsoleBridge.drain_events(dialog)
    end

    def peek_console_events(dialog)
      return [] unless dialog

      ConsoleBridge.peek_events(dialog)
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

    def initialize_dialog_state(dialog)
      return unless dialog

      dialog_boot_states[dialog] = :cold
      dialog_eval_queues[dialog] = []
    end

    def dialog_boot_states
      @dialog_boot_states ||= {}.compare_by_identity
    end

    def dialog_eval_queues
      @dialog_eval_queues ||= {}.compare_by_identity
    end

    def ready_state?(state)
      %i[dom_ready app_ready].include?(state)
    end

    def enqueue_eval(dialog, script, token)
      dialog_eval_queues[dialog] ||= []
      dialog_eval_queues[dialog] << [script, token, dialog]
    end

    def flush_eval_queue(dialog)
      queue = dialog_eval_queues.delete(dialog)
      return unless queue&.any?

      dispatch = lambda do
        queue.each do |script, token, target_dialog|
          next unless target_dialog

          execute_script(target_dialog, script, token)
        end
      end

      if dispatching_eval_callback?
        ::UI.start_timer(0, false) { dispatch.call }
      else
        dispatch.call
      end
    end

    def execute_script(dialog, script, token)
      dialog.execute_script(script)
    rescue StandardError => error
      dispatch_eval_failure(token, error)
    end

    def handle_dialog_closed(dialog)
      return unless dialog

      pending = dialog_eval_queues.delete(dialog)
      dialog_boot_states.delete(dialog)
      ConsoleBridge.unregister_dialog(dialog)

      return unless pending&.any?

      pending.each do |_script, token, _dlg|
        dispatch_eval_failure(token, 'Dialog closed before HtmlDialog eval could run.')
      end
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

        state = TestHarness.dialog_boot_states[@dialog]

        if TestHarness.ready_state?(state)
          dispatch = lambda { TestHarness.execute_script(@dialog, script, token) }

          if TestHarness.dispatching_eval_callback?
            ::UI.start_timer(0, false) { dispatch.call }
          else
            dispatch.call
          end
        else
          TestHarness.enqueue_eval(@dialog, script, token)
        end

        token
      end

      def drain_console_events
        raise 'Dialog is closed.' unless @dialog

        TestHarness.drain_console_events(@dialog)
      end

      def peek_console_events
        return [] unless @dialog

        TestHarness.peek_console_events(@dialog)
      end

      def close
        return unless @dialog

        begin
          @dialog.close
        ensure
          TestHarness.handle_dialog_closed(@dialog)
          AICabinets::UI::Dialogs::InsertBaseCabinet.send(:disable_test_mode!)
          @dialog = nil
        end
      end
    end

    class EvalError < StandardError; end
    class TimeoutError < StandardError; end
    class SynchronousEvalUnsupportedError < StandardError; end

    def insert!(config:)
      model = active_model!
      params = build_params(config)
      instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
        model: model,
        point3d: ::Geom::Point3d.new(0, 0, 0),
        params_mm: params
      )
      [instance.definition, instance]
    end

    def edit_this_instance!(instance:, config_patch:)
      validate_instance!(instance)

      model = active_model!
      selection = model.selection
      selection.clear
      selection.add(instance)

      params = merged_params(instance.definition, config_patch)
      result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
        model: model,
        params_mm: params,
        scope: 'instance'
      )
      raise "Edit failed: #{result.inspect}" unless result[:ok]

      instance
    end

    def edit_all_instances!(definition:, config_patch:)
      validate_definition!(definition)

      instance = definition.instances.find(&:valid?)
      raise ArgumentError, 'definition has no valid instances' unless instance

      model = active_model!
      selection = model.selection
      selection.clear
      selection.add(instance)

      params = merged_params(definition, config_patch)
      result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
        model: model,
        params_mm: params,
        scope: 'all'
      )
      raise "Edit failed: #{result.inspect}" unless result[:ok]

      definition
    end

    def build_params(config)
      defaults = AICabinets::Defaults.load_effective_mm
      merged = deep_copy(defaults)
      merged = deep_merge(merged, deep_copy(config)) if config
      sanitized = deep_copy(merged)
      AICabinets::ParamsSanitizer.sanitize!(sanitized, global_defaults: defaults)
      sanitized.delete(:scope)
      sanitized
    end
    private_class_method :build_params

    def merged_params(definition, patch)
      base = definition_params(definition)
      merged = deep_merge(base, deep_copy(patch))
      build_params(merged)
    end
    private_class_method :merged_params

    def definition_params(definition)
      validate_definition!(definition)

      dict = definition.attribute_dictionary(
        AICabinets::Ops::InsertBaseCabinet::DICTIONARY_NAME
      )
      return {} unless dict

      json = dict[AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY]
      return {} unless json.is_a?(String) && !json.empty?

      JSON.parse(json, symbolize_names: true)
    rescue JSON::ParserError
      {}
    end
    private_class_method :definition_params

    def active_model!
      model = Sketchup.active_model
      raise 'No active model available.' unless model.is_a?(Sketchup::Model)

      model
    end
    private_class_method :active_model!

    def validate_instance!(instance)
      unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
        raise ArgumentError, 'instance must be a valid SketchUp::ComponentInstance'
      end
    end
    private_class_method :validate_instance!

    def validate_definition!(definition)
      unless definition.is_a?(Sketchup::ComponentDefinition) && definition.valid?
        raise ArgumentError, 'definition must be a valid SketchUp::ComponentDefinition'
      end
    end
    private_class_method :validate_definition!

    def deep_merge(base, patch)
      return deep_copy(patch) if base.nil?
      return deep_copy(base) if patch.nil?

      if base.is_a?(Hash) && patch.is_a?(Hash)
        base.each_with_object({}) do |(key, value), memo|
          memo[key] = deep_copy(value)
        end.merge(patch) do |_key, old_value, new_value|
          deep_merge(old_value, new_value)
        end
      elsif base.is_a?(Array) && patch.is_a?(Array)
        length = [base.length, patch.length].max
        Array.new(length) do |index|
          old_value = index < base.length ? base[index] : nil
          new_value = index < patch.length ? patch[index] : nil
          new_value.nil? ? deep_copy(old_value) : deep_merge(old_value, new_value)
        end
      else
        deep_copy(patch)
      end
    end
    private_class_method :deep_merge

    def deep_copy(object)
      Marshal.load(Marshal.dump(object))
    rescue TypeError
      object
    end
    private_class_method :deep_copy
  end
end
