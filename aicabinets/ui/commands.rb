# frozen_string_literal: true

module AICabinets
  module UI
    class << self
      # Returns the command registry for the extension.
      # The registry memoizes instances of UI::Command so they can be reused
      # across menus, toolbars, and other UI integrations without duplication.
      def commands
        @commands ||= {}
      end

      # Ensures all default commands are registered and available.
      def register_commands!
        return unless defined?(::UI::Command)

        commands[:insert_base_cabinet] ||= build_insert_base_cabinet_command
        commands[:edit_base_cabinet] ||= build_edit_base_cabinet_command
        commands[:create_row_from_selection] ||= build_create_row_command
        commands[:rows_manage] ||= build_rows_manage_command
        commands[:rows_add_selection] ||= build_rows_add_selection_command
        commands[:rows_remove_selection] ||= build_rows_remove_selection_command
        commands[:rows_toggle_highlight] ||= build_rows_highlight_command
      end

      private

      def build_insert_base_cabinet_command
        command = ::UI::Command.new('Insert Base Cabinet…') do
          handle_insert_base_cabinet
        end
        command.tooltip = 'Insert Base Cabinet…'
        command.status_bar_text = 'Insert a base cabinet using AI Cabinets.'
        assign_command_icons(command, 'insert_base_cabinet')
        command
      end

      def build_edit_base_cabinet_command
        command = ::UI::Command.new('Edit Selected Cabinet…') do
          handle_edit_base_cabinet
        end
        command.tooltip = 'Edit Selected Cabinet…'
        command.status_bar_text = 'Edit the selected AI Cabinets base cabinet.'
        assign_command_icons(command, 'edit_base_cabinet')
        command
      end

      def build_create_row_command
        command = ::UI::Command.new('Create Row from Selection') do
          handle_create_row_from_selection
        end
        command.tooltip = 'Create Row from Selection'
        command.status_bar_text = 'Create an AI Cabinets row from the current cabinet selection.'
        command
      end

      def build_rows_manage_command
        command = ::UI::Command.new('Manage Rows…') do
          handle_manage_rows
        end
        command.tooltip = 'Manage Rows…'
        command.status_bar_text = 'Open the AI Cabinets Rows manager dialog.'
        assign_command_icons(command, 'rows_manage')
        command
      end

      def build_rows_add_selection_command
        command = ::UI::Command.new('Rows: Add Selection') do
          handle_rows_add_selection
        end
        command.tooltip = 'Rows: Add Selection'
        command.status_bar_text = 'Add the selected cabinets to the active AI Cabinets row.'
        assign_command_icons(command, 'rows_add')
        command
      end

      def build_rows_remove_selection_command
        command = ::UI::Command.new('Rows: Remove from Row') do
          handle_rows_remove_selection
        end
        command.tooltip = 'Rows: Remove from Row'
        command.status_bar_text = 'Remove the selected cabinets from the active AI Cabinets row.'
        assign_command_icons(command, 'rows_remove')
        command
      end

      def build_rows_highlight_command
        command = ::UI::Command.new('Rows: Toggle Highlight') do
          handle_rows_toggle_highlight
        end
        command.tooltip = 'Rows: Toggle Highlight'
        command.status_bar_text = 'Toggle highlighting of the active AI Cabinets row.'
        assign_command_icons(command, 'rows_highlight')
        command
      end

      def assign_command_icons(command, base_name)
        return unless defined?(::UI::Command)

        small_icon = Icons.small_icon_path(base_name)
        large_icon = Icons.large_icon_path(base_name)

        command.small_icon = small_icon if small_icon
        command.large_icon = large_icon if large_icon
      end

      def handle_insert_base_cabinet
        dialog = if defined?(AICabinets::UI::Dialogs::InsertBaseCabinet) &&
                    AICabinets::UI::Dialogs::InsertBaseCabinet.respond_to?(:show)
                   AICabinets::UI::Dialogs::InsertBaseCabinet
                 end

        if dialog
          dialog.show
        else
          warn('AI Cabinets: Insert Base Cabinet dialog is unavailable.')
        end

        nil
      end

      def handle_edit_base_cabinet
        dialog = if defined?(AICabinets::UI::Dialogs::InsertBaseCabinet) &&
                    AICabinets::UI::Dialogs::InsertBaseCabinet.respond_to?(:show_for_edit)
                   AICabinets::UI::Dialogs::InsertBaseCabinet
                 end

        unless dialog
          warn('AI Cabinets: Edit Base Cabinet dialog is unavailable.')
          return nil
        end

        result = AICabinets::Selection.require_editable_cabinet
        unless result.valid?
          notify_selection_issue(result.message, status: result.status)
          return nil
        end

        instance = result.instance

        unless dialog.show_for_edit(instance)
          notify_selection_issue('Unable to open the edit dialog for the selected cabinet.', status: :dialog_failed)
        end
        nil
      end

      def handle_create_row_from_selection
        return unless defined?(Sketchup)

        model = Sketchup.active_model
        result = AICabinets::Rows.create_from_selection(model: model)
        if result.is_a?(AICabinets::Rows::Result)
          warn("AI Cabinets: Row creation failed (#{result.code}): #{result.message}")
          if defined?(::UI) && ::UI.respond_to?(:messagebox)
            button_type = defined?(::MB_OK) ? ::MB_OK : 0
            ::UI.messagebox(result.message, button_type, 'AI Cabinets')
          end
        elsif result
          warn("AI Cabinets: Created cabinet row #{result}.")
          if defined?(AICabinets::UI::Rows)
            AICabinets::UI::Rows.show_manager(row_id: result)
          end
        end

        nil
      end

      def handle_manage_rows
        unless defined?(AICabinets::UI::Rows)
          warn('AI Cabinets: Rows UI unavailable.')
          return
        end

        AICabinets::UI::Rows.show_manager
      end

      def handle_rows_add_selection
        unless defined?(AICabinets::UI::Rows)
          warn('AI Cabinets: Rows UI unavailable.')
          return
        end

        AICabinets::UI::Rows.add_selection_to_active_row
      end

      def handle_rows_remove_selection
        unless defined?(AICabinets::UI::Rows)
          warn('AI Cabinets: Rows UI unavailable.')
          return
        end

        AICabinets::UI::Rows.remove_selection_from_active_row
      end

      def handle_rows_toggle_highlight
        unless defined?(AICabinets::UI::Rows)
          warn('AI Cabinets: Rows UI unavailable.')
          return
        end

        AICabinets::UI::Rows.toggle_highlight
      end

      def notify_selection_issue(message, status: nil)
        log_message = if status
                        "Edit Selected Cabinet aborted (#{status}): #{message}"
                      else
                        message
                      end
        warn("AI Cabinets: #{log_message}")

        if defined?(::UI) && ::UI.respond_to?(:messagebox)
          button_type = defined?(::MB_OK) ? ::MB_OK : 0
          ::UI.messagebox(message, button_type, 'AI Cabinets')
        elsif defined?(::UI) && ::UI.respond_to?(:show_notification)
          ::UI.show_notification('AI Cabinets', message)
        end
      end

    end
  end
end
