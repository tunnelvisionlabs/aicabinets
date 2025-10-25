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
    end
  end
end
