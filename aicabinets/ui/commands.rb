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
        command
      end

      def handle_insert_base_cabinet
        message = 'AI Cabinets placeholder: Insert Base Cabinet command invoked.'
        if defined?(::UI) && ::UI.respond_to?(:messagebox)
          ::UI.messagebox(message)
        else
          puts(message)
        end
        nil
      end
    end
  end
end
