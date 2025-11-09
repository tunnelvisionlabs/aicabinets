# frozen_string_literal: true

require 'json'

module AICabinets
  module UI
    module LayoutPreview
      # SelectionSyncBridge wires the HtmlDialog preview to the Ruby form state.
      #
      # It forwards preview click events (requestSelectBay) into the provided form
      # object and exposes a Ruby API to update the active bay highlight within the
      # HtmlDialog. A short-lived guard prevents the Ruby-initiated highlight from
      # echoing the same selection request back into the form, avoiding feedback
      # loops when both sides update quickly.
      class SelectionSyncBridge
        DEFAULT_SCOPE = 'all'
        GUARD_DURATION = 0.35
        private_constant :DEFAULT_SCOPE, :GUARD_DURATION

        attr_reader :dialog, :form

        def initialize(dialog, form:)
          raise ArgumentError, 'dialog must be a UI::HtmlDialog' unless html_dialog?(dialog)
          raise ArgumentError, 'form must respond to #select_bay' unless form.respond_to?(:select_bay)

          @dialog = dialog
          @form = form
          @default_scope = DEFAULT_SCOPE
          @guard_identifier = nil
          @guard_expires_at = Time.at(0)

          attach_callbacks
        end

        # Programmatically highlight the given bay in the HtmlDialog.
        # The scope argument accepts :single or :all and defaults to the most
        # recent scope used for the dialog. Passing nil preserves the existing
        # scope.
        #
        # @param bay_id [String, Numeric, nil]
        # @param scope [String, Symbol, nil]
        # @return [Boolean] true when the script is dispatched to the dialog
        def set_active_bay(bay_id, scope: nil)
          normalized_scope = normalize_scope(scope) || @default_scope
          @default_scope = normalized_scope

          normalized_guard_id = guard_id_for(bay_id)
          activate_guard(normalized_guard_id)

          script = build_set_active_bay_script(bay_id, normalized_scope)
          dialog.execute_script(script)
          true
        rescue StandardError => error
          warn("AI Cabinets: Failed to invoke setActiveBay: #{error.message}")
          false
        end

        private

        def attach_callbacks
          dialog.add_action_callback('requestSelectBay') do |_context, bay_id|
            handle_request_select_bay(bay_id)
          end
        end

        def handle_request_select_bay(bay_id)
          return if suppress_echo_for?(bay_id)

          form.select_bay(bay_id)
        rescue StandardError => error
          warn("AI Cabinets: requestSelectBay callback failed: #{error.message}")
        end

        def suppress_echo_for?(bay_id)
          return false if @guard_identifier.nil?

          identifier = guard_id_for(bay_id)
          return false if identifier.nil?

          current_time = current_timestamp
          if current_time <= @guard_expires_at && identifier == @guard_identifier
            true
          else
            clear_guard_if_expired(current_time)
            false
          end
        end

        def activate_guard(identifier)
          if identifier.nil?
            clear_guard
            return
          end

          @guard_identifier = identifier
          @guard_expires_at = current_timestamp + GUARD_DURATION
        end

        def clear_guard_if_expired(reference_time)
          return unless reference_time > @guard_expires_at

          clear_guard
        end

        def clear_guard
          @guard_identifier = nil
          @guard_expires_at = Time.at(0)
        end

        def build_set_active_bay_script(bay_id, scope)
          id_json = JSON.generate(bay_id)
          opts_json = JSON.generate(scope: scope)
          <<~JS
            (function () {
              if (window.LayoutPreview && typeof window.LayoutPreview.setActiveBay === 'function') {
                window.LayoutPreview.setActiveBay(#{id_json}, #{opts_json});
              }
            })();
          JS
        end

        def guard_id_for(value)
          return nil if value.nil?

          text = value.to_s
          text.empty? ? nil : text
        end

        def normalize_scope(value)
          return nil if value.nil?

          case value
          when :single, 'single'
            'single'
          when :all, 'all'
            'all'
          else
            string = value.to_s.strip.downcase
            return 'single' if string == 'single'
            return 'all' if string == 'all'
            nil
          end
        end

        def current_timestamp
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rescue StandardError
          Time.now
        end

        def html_dialog?(object)
          defined?(UI::HtmlDialog) && object.is_a?(UI::HtmlDialog)
        end
      end
    end
  end
end
