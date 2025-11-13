# frozen_string_literal: true

require 'aicabinets/rows'
require 'aicabinets/ui/rows/manager_dialog'

module AICabinets
  module UI
    module Rows
      module_function

      def show_manager(row_id: nil)
        ManagerDialog.show(row_id: row_id)
      end

      def toggle_manager
        ManagerDialog.toggle_visibility
      end

      def create_from_selection
        model = Sketchup.active_model
        result = AICabinets::Rows.create_from_selection(model: model)
        if result.is_a?(AICabinets::Rows::Result)
          notify(result.message)
          return nil
        end

        row_id = result
        ManagerDialog.show(row_id: row_id)
        detail = AICabinets::Rows.get_row(model: model, row_id: row_id)
        ManagerDialog.handle_row_result(detail)
        row_id
      rescue AICabinets::Rows::RowError => error
        notify(error.message)
        nil
      end

      def add_selection_to_active_row
        row_id = ManagerDialog.active_row_id
        if row_id.to_s.empty?
          notify('Select a row in the Rows Manager before adding cabinets.')
          return nil
        end

        pids = selection_component_pids
        if pids.empty?
          notify('Select at least one AI Cabinets cabinet to add to the row.')
          return nil
        end

        detail = AICabinets::Rows.add_members(model: Sketchup.active_model, row_id: row_id, member_pids: pids)
        ManagerDialog.handle_row_result(detail)
        detail
      rescue AICabinets::Rows::RowError => error
        notify(error.message)
        nil
      end

      def remove_selection_from_active_row
        row_id = ManagerDialog.active_row_id
        if row_id.to_s.empty?
          notify('Select a row in the Rows Manager before removing cabinets.')
          return nil
        end

        pids = selection_component_pids
        if pids.empty?
          notify('Select at least one row member to remove.')
          return nil
        end

        detail = AICabinets::Rows.remove_members(model: Sketchup.active_model, row_id: row_id, member_pids: pids)
        ManagerDialog.handle_row_result(detail)
        detail
      rescue AICabinets::Rows::RowError => error
        notify(error.message)
        nil
      end

      def toggle_highlight(row_id: nil)
        model = Sketchup.active_model
        highlight_module = AICabinets::Rows::Highlight
        current_row_id = highlight_module.active_row_id(model: model)

        target_row_id = row_id || ManagerDialog.active_row_id
        target_row_id = target_row_id.to_s
        target_row_id = nil if target_row_id.empty?

        if current_row_id && (!target_row_id || target_row_id == current_row_id)
          response = ManagerDialog.set_highlight(false)
          unless response.is_a?(Hash) && response[:ok]
            error = response && response[:error]
            notify(error[:message]) if error
            return nil
          end

          return response
        end

        target_row_id ||= infer_row_id_from_selection(model)
        if target_row_id.to_s.empty?
          notify('Select a row in the Rows Manager or select cabinets from a single row to highlight.')
          return nil
        end

        detail = AICabinets::Rows.get_row(model: model, row_id: target_row_id)
        ManagerDialog.set_active_row(target_row_id, sync_selection: false, detail: detail)
        ManagerDialog.refresh_ui(row_id: target_row_id)

        response = ManagerDialog.set_highlight(true)
        unless response.is_a?(Hash) && response[:ok]
          error = response && response[:error]
          notify(error[:message]) if error
          return nil
        end

        response
      rescue AICabinets::Rows::RowError => error
        notify(error.message)
        nil
      end

      def auto_select_row?
        AICabinets::Rows::Selection.auto_select_row?
      end

      def set_auto_select_row(on:)
        result = AICabinets::Rows::Selection.set_auto_select_row(on: on, model: Sketchup.active_model)
        ManagerDialog.refresh_preferences_ui if ManagerDialog.respond_to?(:refresh_preferences_ui)
        result
      end

      def toggle_auto_select
        set_auto_select_row(on: !auto_select_row?)
      end

      def refresh_active_row
        row_id = ManagerDialog.active_row_id
        return unless row_id

        detail = AICabinets::Rows.get_row(model: Sketchup.active_model, row_id: row_id)
        ManagerDialog.handle_row_result(detail)
        detail
      rescue AICabinets::Rows::RowError => error
        notify(error.message)
        nil
      end

      def selection_component_pids
        model = Sketchup.active_model
        selection = model.selection
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

      def notify(message)
        return unless defined?(::UI)

        button_type = defined?(::MB_OK) ? ::MB_OK : 0
        ::UI.messagebox(message, button_type, 'AI Cabinets')
      end
      private_class_method :notify

      def infer_row_id_from_selection(model)
        AICabinets::Rows.infer_row_from_selection(model)
      rescue StandardError
        nil
      end
      private_class_method :infer_row_id_from_selection

    end
  end
end
