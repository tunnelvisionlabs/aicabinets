# frozen_string_literal: true

require 'json'
require 'securerandom'

require 'aicabinets/rows'
require 'aicabinets/ui/dialog_console_bridge'

module AICabinets
  module UI
    module Rows
      module ManagerDialog
        module_function

        ConsoleBridge = AICabinets::UI::DialogConsoleBridge
        private_constant :ConsoleBridge

        DIALOG_TITLE = 'AI Cabinets — Rows Manager'
        PREFERENCES_KEY = 'AICabinets.RowsManager'
        HTML_FILENAME = 'rows_manager.html'
        CALLBACK_NAME = 'rows_rpc'

        def show(row_id: nil)
          dialog = ensure_dialog
          return unless dialog

          state[:pending_focus_row] = row_id if row_id
          show_dialog(dialog)
          refresh_ui
          dialog
        end

        def toggle_visibility
          dialog = ensure_dialog
          return unless dialog

          if dialog.visible?
            dialog.close
          else
            show_dialog(dialog)
            refresh_ui
          end
        end

        def active_row_id
          state[:active_row_id]
        end

        def highlight_enabled?
          !!state[:highlight]
        end

        def set_active_row(row_id, sync_selection: true, detail: nil)
          previous_row_id = state[:active_row_id]
          state[:active_row_id] = row_id

          sync_selection_with_detail(detail) if sync_selection && detail

          if highlight_enabled? && row_id
            begin
              AICabinets::Rows.highlight(model: active_model, row_id: row_id, enabled: true)
            rescue AICabinets::Rows::RowError => error
              warn("AI Cabinets: Unable to update row highlight: #{error.message}")
            end
          elsif previous_row_id && previous_row_id != row_id
            begin
              AICabinets::Rows.highlight(model: active_model, row_id: previous_row_id, enabled: false)
            rescue AICabinets::Rows::RowError
              # Ignore cleanup failures when highlight is disabled.
            end
          end

          detail
        end

      def set_highlight(enabled)
        row_id = active_row_id
        raise AICabinets::Rows::RowError.new(:unknown_row, 'Select a row before highlighting.') if enabled && row_id.to_s.empty?

        state[:highlight] = enabled
        unless row_id
          update_highlight_ui(false)
          return { ok: true, highlight: false }
        end

        result = AICabinets::Rows.highlight(model: active_model, row_id: row_id, enabled: enabled)
        update_highlight_ui(enabled)
        { ok: true, highlight: enabled, overlay: result }
      end

      def toggle_highlight
        new_state = !highlight_enabled?
        result = set_highlight(new_state)
        result
      rescue AICabinets::Rows::RowError => error
        notify(error.message)
        { ok: false, error: { code: error.code, message: error.message } }
      end

        def handle_row_result(detail)
          return unless detail.is_a?(Hash)

          row = detail[:row] || detail['row']
          return detail unless row

          row_id = row[:row_id] || row['row_id']
          set_active_row(row_id, sync_selection: false, detail: detail)
          sync_selection_with_detail(detail)
          update_highlight_ui(highlight_enabled?)
          refresh_ui(row_id: row_id)
          detail
        end

        def refresh_ui(row_id: nil)
          row_id ||= state.delete(:pending_focus_row)
          dialog = current_dialog
          return unless dialog

          if row_id
            dialog.execute_script(format('window.AICabinetsRows && window.AICabinetsRows.refreshRow(%s);', js_string(row_id)))
          else
            dialog.execute_script('window.AICabinetsRows && window.AICabinetsRows.refreshAll();')
          end
        end

        def invoke_rpc_for_test(method, params = {})
          dispatch_rpc(method, params)
        end

        def enable_test_mode!
          state[:test_mode] = true
        end

        def disable_test_mode!
          state[:test_mode] = false
        end

        def test_mode?
          !!state[:test_mode]
        end

        def ensure_dialog
          return if test_mode?
          return @dialog if @dialog
          return unless html_dialog_available?

          @dialog = build_dialog
        end
        private_class_method :ensure_dialog

        def current_dialog
          return nil if test_mode?

          @dialog
        end
        private_class_method :current_dialog

        def build_dialog
          options = {
            dialog_title: DIALOG_TITLE,
            preferences_key: PREFERENCES_KEY,
            style: ::UI::HtmlDialog::STYLE_DIALOG,
            resizable: true,
            width: 520,
            height: 420
          }

          dialog = ::UI::HtmlDialog.new(options)
          ConsoleBridge.register_dialog(dialog)
          dialog.add_action_callback(CALLBACK_NAME) do |_context, payload|
            handle_callback(dialog, payload)
          end
          dialog.set_on_closed do
            ConsoleBridge.unregister_dialog(dialog)
            begin
              set_highlight(false)
            rescue StandardError
              # Ignore highlight cleanup errors when closing the dialog.
            end
            state[:active_row_id] = nil
            @dialog = nil
          end
          set_dialog_file(dialog)
          dialog
        end
        private_class_method :build_dialog

        def show_dialog(dialog)
          dialog.show
          dialog.bring_to_front if dialog.respond_to?(:bring_to_front)
        end
        private_class_method :show_dialog

        def html_dialog_available?
          defined?(::UI::HtmlDialog)
        end
        private_class_method :html_dialog_available?

        def set_dialog_file(dialog)
          assets_dir = File.expand_path(__dir__)
          html_path = File.join(assets_dir, HTML_FILENAME)
          dialog.set_file(html_path)
        end
        private_class_method :set_dialog_file

        def handle_callback(dialog, payload)
          request = parse_request(payload)
          response =
            begin
              result = dispatch_rpc(request[:method], request[:params])
              { id: request[:id], result: result }
            rescue AICabinets::Rows::RowError => error
              { id: request[:id], error: { code: error.code, message: error.message } }
            rescue StandardError => error
              warn("AI Cabinets: Rows RPC failed: #{error.message}")
              { id: request[:id], error: { code: :internal_error, message: 'Unable to complete rows request.' } }
            end

          deliver_response(dialog, response)
        end
        private_class_method :handle_callback

        def parse_request(payload)
          data =
            case payload
            when String
              JSON.parse(payload, symbolize_names: true)
            when Hash
              payload
            else
              {}
            end

          {
            id: data[:id] || data['id'] || SecureRandom.uuid,
            method: (data[:method] || data['method']).to_s,
            params: data[:params] || data['params'] || {}
          }
        rescue JSON::ParserError
          { id: SecureRandom.uuid, method: '', params: {} }
        end
        private_class_method :parse_request

        def deliver_response(dialog, response)
          return unless dialog

          json = JSON.generate(response)
          dialog.execute_script(format('window.AICabinetsRows && window.AICabinetsRows.receive(%s);', js_string(json)))
        end
        private_class_method :deliver_response

        def dispatch_rpc(method, params)
          case method
          when 'rows.list'
            rows = AICabinets::Rows.list_summary(active_model)
            { rows: rows }
          when 'rows.get'
            row_id = fetch_row_id(params)
            detail = AICabinets::Rows.get_row(model: active_model, row_id: row_id)
            set_active_row(row_id, sync_selection: true, detail: detail)
            detail
          when 'rows.create_from_selection'
            handle_create_from_selection
          when 'rows.add_members'
            row_id = fetch_row_id(params)
            pids = fetch_pids(params)
            detail = AICabinets::Rows.add_members(model: active_model, row_id: row_id, member_pids: pids)
            handle_row_result(detail)
          when 'rows.remove_members'
            row_id = fetch_row_id(params)
            pids = fetch_pids(params)
            detail = AICabinets::Rows.remove_members(model: active_model, row_id: row_id, member_pids: pids)
            handle_row_result(detail)
          when 'rows.reorder'
            row_id = fetch_row_id(params)
            order = fetch_pids(params)
            detail = AICabinets::Rows.reorder(model: active_model, row_id: row_id, order: order)
            handle_row_result(detail)
          when 'rows.update'
            row_id = fetch_row_id(params)
            detail = AICabinets::Rows.update(
              model: active_model,
              row_id: row_id,
              row_reveal_mm: params[:row_reveal_mm] || params['row_reveal_mm'],
              lock_total_length: fetch_boolean(params, :lock_total_length)
            )
            handle_row_result(detail)
          when 'rows.highlight'
            row_id = fetch_row_id(params)
            enabled = fetch_boolean(params, :on)
            state[:active_row_id] = row_id
            state[:highlight] = !!enabled
            result = AICabinets::Rows.highlight(model: active_model, row_id: row_id, enabled: enabled)
            update_highlight_ui(enabled)
            result
          when 'rows.selection'
            { pids: selection_component_pids }
          else
            raise AICabinets::Rows::RowError.new(:unsupported_method, "Unknown rows method: #{method}")
          end
        end
        private_class_method :dispatch_rpc

        def handle_create_from_selection
          result = AICabinets::Rows.create_from_selection(model: active_model)
          if result.is_a?(AICabinets::Rows::Result)
            raise AICabinets::Rows::RowError.new(result.code, result.message)
          end

          row_id = result
          detail = AICabinets::Rows.get_row(model: active_model, row_id: row_id)
          handle_row_result(detail)
        end
        private_class_method :handle_create_from_selection

        def fetch_row_id(params)
          value = params[:row_id] || params['row_id']
          value.to_s
        end
        private_class_method :fetch_row_id

        def fetch_pids(params)
          array =
            case params
            when Hash
              params[:pids] || params['pids'] || params[:order] || params['order'] || []
            else
              params
            end

          Array(array).map { |pid| pid.to_i }.select { |pid| pid.positive? }.uniq
        end
        private_class_method :fetch_pids

        def fetch_boolean(params, key)
          return convert_boolean(params[key]) if params.is_a?(Hash) && params.key?(key)
          return convert_boolean(params[key.to_s]) if params.is_a?(Hash) && params.key?(key.to_s)

          nil
        end
        private_class_method :fetch_boolean

        def convert_boolean(value)
          case value
          when true, false
            value
          when String
            normalized = value.strip.downcase
            return true if %w[true 1 yes on].include?(normalized)
            return false if %w[false 0 no off].include?(normalized)
            nil
          when Numeric
            !value.to_f.zero?
          else
            nil
          end
        end
        private_class_method :convert_boolean

        def selection_component_pids
        selection = active_model.selection
        return [] unless selection && selection.respond_to?(:grep)

          selection.grep(Sketchup::ComponentInstance).filter_map do |instance|
            next unless instance.valid?

            pid = instance.persistent_id.to_i
            next unless pid.positive?

            next unless AICabinets::Rows.__send__(:cabinet_instance?, instance)

            pid
          end
        end
        private_class_method :selection_component_pids

        def sync_selection_with_detail(detail)
          return unless detail.is_a?(Hash)

          row = detail[:row] || detail['row']
          return unless row

        selection = active_model.selection
        return unless selection

          pids = Array(row[:member_pids] || row['member_pids'])

          selection.clear
          pids.each do |pid|
            entity = active_model.find_entity_by_persistent_id(pid.to_i)
            selection.add(entity) if entity
          end
        end
        private_class_method :sync_selection_with_detail

    def state
      @state ||= {}
    end
    private_class_method :state

    def update_highlight_ui(enabled)
      dialog = current_dialog
      return unless dialog

      literal = enabled ? 'true' : 'false'
      dialog.execute_script("window.AICabinetsRows && window.AICabinetsRows.setHighlight(#{literal});")
    end
    private_class_method :update_highlight_ui

    def active_model
      Sketchup.active_model
    end
        private_class_method :active_model

        def js_string(value)
          format('"%s"', value.to_s.gsub(/\\/, '\\\\').gsub(/"/, '\\"'))
        end
        private_class_method :js_string

        def notify(message)
          return unless defined?(::UI)

          button_type = defined?(::MB_OK) ? ::MB_OK : 0
          ::UI.messagebox(message, button_type, 'AI Cabinets')
        end
        private_class_method :notify
      end
    end
  end
end
