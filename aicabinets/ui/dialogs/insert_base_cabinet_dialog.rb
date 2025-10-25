# frozen_string_literal: true

module AICabinets
  module UI
    module Dialogs
      module InsertBaseCabinet
        module_function

        DIALOG_TITLE = 'AI Cabinets — Insert Base Cabinet'
        PREFERENCES_KEY = 'AICabinets.InsertBaseCabinet'
        HTML_FILENAME = 'insert_base_cabinet.html'

        # Shows the Insert Base Cabinet dialog, creating it if necessary.
        # Subsequent invocations focus the existing dialog to avoid duplicates.
        def show
          return unless ensure_html_dialog_support

          dialog = ensure_dialog
          if dialog.visible?
            dialog.bring_to_front
          else
            dialog.show
          end

          dialog
        end

        def ensure_dialog
          @dialog ||= build_dialog
        end
        private_class_method :ensure_dialog

        def build_dialog
          options = {
            dialog_title: DIALOG_TITLE,
            preferences_key: PREFERENCES_KEY,
            style: ::UI::HtmlDialog::STYLE_DIALOG,
            resizable: true,
            width: 400,
            height: 360
          }

          dialog = ::UI::HtmlDialog.new(options)
          attach_callbacks(dialog)
          set_dialog_file(dialog)
          dialog.set_on_closed { @dialog = nil }
          dialog
        end
        private_class_method :build_dialog

        def attach_callbacks(dialog)
          dialog.add_action_callback('insert') do |_action_context, _payload|
            # Reserved for future geometry generation wiring.
          end

          dialog.add_action_callback('cancel') do |action_context, _payload|
            action_context.close
          end
        end
        private_class_method :attach_callbacks

        def set_dialog_file(dialog)
          html_path = File.join(__dir__, HTML_FILENAME)

          unless File.exist?(html_path)
            warn_missing_asset(html_path)
            return
          end

          dialog.set_file(html_path)
        end
        private_class_method :set_dialog_file

        def ensure_html_dialog_support
          return true if defined?(::UI::HtmlDialog)

          warn('UI::HtmlDialog is not available in this environment.')
          false
        end
        private_class_method :ensure_html_dialog_support

        def warn_missing_asset(path)
          warn("AI Cabinets: Unable to locate dialog asset: #{path}")
        end
        private_class_method :warn_missing_asset
      end
    end
  end
end
