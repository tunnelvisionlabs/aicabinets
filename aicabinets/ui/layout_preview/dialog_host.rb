# frozen_string_literal: true

require 'json'

require 'aicabinets/ui/layout_preview/dialog'

module AICabinets
  module UI
    module LayoutPreview
      # DialogHost coordinates the HtmlDialog-based layout preview within the
      # Insert Base Cabinet dialog. It lazily enables the preview pane, forwards
      # layout model updates to the browser, and keeps selection synchronized in
      # both directions via SelectionSyncBridge.
      class DialogHost
        attr_reader :dialog

        def initialize(dialog, &on_select)
          unless dialog.respond_to?(:add_action_callback) && dialog.respond_to?(:execute_script)
            raise ArgumentError, 'dialog must respond to HtmlDialog scripting APIs'
          end

          @dialog = dialog
          @on_select = on_select
          @enabled = false
          @selection_bridge = SelectionSyncBridge.new(dialog, form: self)
        end

        def ensure_enabled(options = nil)
          return false unless dialog
          return true if @enabled

          dispatch('enable', options || {})
          @enabled = true
          true
        rescue StandardError => error
          warn("AI Cabinets: Failed to enable layout preview: #{error.message}")
          false
        end

        def enabled?
          @enabled
        end

        def update(model_payload)
          return false unless ensure_enabled

          dispatch('update', model_payload)
          true
        rescue StandardError => error
          warn("AI Cabinets: Failed to update layout preview: #{error.message}")
          false
        end

        def set_active_bay(bay_id, scope: nil)
          return false unless ensure_enabled

          @selection_bridge.set_active_bay(bay_id, scope: scope)
        end

        def select_form_bay(index, bay_id: nil, focus: true, emit: false)
          return false unless ensure_enabled

          payload = {
            index: index,
            id: bay_id,
            focus: focus ? true : false,
            emit: emit ? true : false
          }
          dispatch('selectBay', payload)
          true
        rescue StandardError => error
          warn("AI Cabinets: Failed to synchronize bay selection: #{error.message}")
          false
        end

        def destroy
          return unless dialog

          dispatch('destroy') if @enabled
        rescue StandardError => error
          warn("AI Cabinets: Failed to destroy layout preview host: #{error.message}")
        ensure
          @enabled = false
        end

        # SelectionSyncBridge expects the form to respond to #select_bay.
        def select_bay(bay_id)
          return unless @on_select

          @on_select.call(bay_id, self)
        rescue StandardError => error
          warn("AI Cabinets: requestSelectBay callback failed: #{error.message}")
          nil
        end

        private

        def dispatch(function_name, payload = nil)
          script = build_dispatch_script(function_name, payload)
          dialog.execute_script(script)
        end

        def build_dispatch_script(function_name, payload)
          arguments =
            if payload.nil?
              ''
            elsif payload.is_a?(String)
              payload
            else
              JSON.generate(payload)
            end

          <<~JAVASCRIPT
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (!root || !root.layoutPreview || typeof root.layoutPreview.#{function_name} !== 'function') {
                return;
              }
              try {
                root.layoutPreview.#{function_name}(#{arguments});
              } catch (error) {
                if (window.console && typeof window.console.warn === 'function') {
                  window.console.warn('layoutPreview.#{function_name} failed:', error);
                }
              }
            })();
          JAVASCRIPT
        end
      end

      # Null object used when the layout preview feature flag is disabled.
      class NullDialogHost
        def ensure_enabled(*)
          false
        end

        def enabled?
          false
        end

        def update(*)
          false
        end

        def set_active_bay(*)
          false
        end

        def select_form_bay(*)
          false
        end

        def select_bay(*)
          false
        end

        def destroy(*)
          nil
        end

        def dialog
          nil
        end
      end
    end
  end
end
