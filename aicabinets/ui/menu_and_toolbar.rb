# frozen_string_literal: true

module AICabinets
  module UI
    class << self
      MENU_TITLE = 'AI Cabinets'
      TOOLBAR_NAME = 'AI Cabinets'

      def register_ui!
        return unless defined?(::UI)
        return if @ui_registered

        register_commands!
        attach_menu
        attach_toolbar

        @ui_registered = true
      end

      private

      def attach_menu
        command = commands[:insert_base_cabinet]
        return unless command

        extensions_menu = ::UI.menu('Extensions')
        @menu ||= extensions_menu.add_submenu(MENU_TITLE)
        @menu.add_item(command)
      end

      def attach_toolbar
        command = commands[:insert_base_cabinet]
        return unless command

        @toolbar ||= begin
          toolbar = ::UI::Toolbar.new(TOOLBAR_NAME)
          toolbar.add_item(command)
          toolbar
        end

        show_toolbar_if_appropriate(@toolbar)
      end

      def show_toolbar_if_appropriate(toolbar)
        return unless toolbar

        state = toolbar.get_last_state if toolbar.respond_to?(:get_last_state)

        visible_states = toolbar_states(:VISIBLE, :FLOATING)
        hidden_state = toolbar_states(:HIDDEN).first

        if visible_states.include?(state)
          toolbar.restore
        elsif hidden_state && state == hidden_state
          # Respect the user's preference to keep the toolbar hidden.
        else
          toolbar.show
        end
      end

      def toolbar_states(*names)
        return [] unless defined?(::UI::Toolbar)

        toolbar_class = ::UI::Toolbar
        return [] unless toolbar_class.respond_to?(:const_defined?)

        names.filter_map do |name|
          next unless toolbar_class.const_defined?(name)

          toolbar_class.const_get(name)
        rescue NameError
          nil
        end
      end
    end
  end
end
