# frozen_string_literal: true

require 'json'

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
          dialog.add_action_callback('dialog_ready') do |_action_context, _payload|
            deliver_units_bootstrap(dialog)
          end

          dialog.add_action_callback('request_defaults') do |_action_context, _payload|
            deliver_insert_defaults(dialog)
          end

          dialog.add_action_callback('insert') do |_action_context, _payload|
            # Reserved for future geometry generation wiring.
          end

          dialog.add_action_callback('cancel') do |_action_context, _payload|
            dialog.close
          end
        end
        private_class_method :attach_callbacks

        def deliver_units_bootstrap(dialog)
          payload = JSON.generate(current_unit_settings)
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (root && typeof root.bootstrap === 'function') {
                root.bootstrap(#{payload});
              }
            })();
          JS

          dialog.execute_script(script)
        end
        private_class_method :deliver_units_bootstrap

        def deliver_insert_defaults(dialog)
          defaults = AICabinets::Ops::Defaults.load_insert_base_cabinet
          payload = JSON.generate(defaults)
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (root && typeof root.applyDefaults === 'function') {
                root.applyDefaults(#{payload});
              }
            })();
          JS

          dialog.execute_script(script)
        end
        private_class_method :deliver_insert_defaults

        def current_unit_settings
          model = ::Sketchup.active_model
          options = model&.options&.[]('UnitsOptions')

          return default_unit_settings unless options

          unit = length_unit_to_symbol(options['LengthUnit'])
          format = length_format_to_symbol(options['LengthFormat'])
          unit = normalize_unit_for_format(unit, format)
          {
            unit: unit,
            unit_label: unit_label_for(unit),
            unit_name: unit_name_for(unit),
            format: format,
            precision: options['LengthPrecision'],
            fractional_precision: options['LengthFractionalPrecision']
          }
        rescue StandardError
          default_unit_settings
        end
        private_class_method :current_unit_settings

        def default_unit_settings
          {
            unit: 'millimeter',
            unit_label: 'mm',
            unit_name: 'millimeters',
            format: 'decimal',
            precision: 0,
            fractional_precision: 3
          }
        end
        private_class_method :default_unit_settings

        def length_unit_to_symbol(code)
          case code
          when 0
            'inch'
          when 1
            'foot'
          when 2
            'millimeter'
          when 3
            'centimeter'
          when 4
            'meter'
          else
            'millimeter'
          end
        end
        private_class_method :length_unit_to_symbol

        def length_format_to_symbol(code)
          case code
          when 1
            'architectural'
          when 2
            'engineering'
          when 3
            'fractional'
          else
            'decimal'
          end
        end
        private_class_method :length_format_to_symbol

        def normalize_unit_for_format(unit, format)
          return unit unless unit == 'foot'

          if %w[architectural fractional].include?(format)
            'inch'
          else
            unit
          end
        end
        private_class_method :normalize_unit_for_format

        def unit_label_for(unit)
          case unit
          when 'inch'
            'in'
          when 'foot'
            'ft'
          when 'centimeter'
            'cm'
          when 'meter'
            'm'
          else
            'mm'
          end
        end
        private_class_method :unit_label_for

        def unit_name_for(unit)
          case unit
          when 'inch'
            'inches'
          when 'foot'
            'feet'
          when 'centimeter'
            'centimeters'
          when 'meter'
            'meters'
          else
            'millimeters'
          end
        end
        private_class_method :unit_name_for

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
