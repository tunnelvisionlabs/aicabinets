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
        attach_context_menu

        @ui_registered = true
      end

      private

      def attach_menu
        extensions_menu = ::UI.menu('Extensions')
        @menu ||= extensions_menu.add_submenu(MENU_TITLE)

        primary_commands = [
          commands[:insert_base_cabinet],
          commands[:edit_base_cabinet]
        ].compact

        primary_commands.each do |command|
          @menu.add_item(command)
        end

        primary_group_has_items = primary_commands.any?

        rows_commands = [
          commands[:create_row_from_selection],
          commands[:rows_manage],
          commands[:rows_add_selection],
          commands[:rows_remove_selection],
          commands[:rows_toggle_highlight],
          commands[:rows_toggle_auto_select]
        ].compact

        if rows_commands.any?
          @menu.add_separator if primary_group_has_items
          rows_menu = @menu.add_submenu('Rows')
          rows_commands.each do |command|
            rows_menu.add_item(command)
          end
        end
      end

      def attach_toolbar
        @toolbar ||= ::UI::Toolbar.new(TOOLBAR_NAME)
        return unless @toolbar

        toolbar_commands = [
          commands[:insert_base_cabinet],
          commands[:create_row_from_selection],
          commands[:rows_manage],
          commands[:rows_add_selection],
          commands[:rows_remove_selection],
          commands[:rows_toggle_highlight]
        ].compact

        toolbar_commands.each do |command|
          next unless command
          next if toolbar_contains?(@toolbar, command)

          @toolbar.add_item(command)
          toolbar_added_commands << command
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

      def toolbar_contains?(toolbar, command)
        return false unless toolbar && command

        toolbar_added_commands.include?(command)
      end

      def toolbar_added_commands
        @toolbar_added_commands ||= []
      end

      def attach_context_menu
        return unless defined?(::UI)
        return unless ::UI.respond_to?(:add_context_menu_handler)
        return if @context_menu_handler_attached

        ::UI.add_context_menu_handler do |menu|
          next unless context_menu_allows_edit_cabinet?

          command = commands[:edit_base_cabinet]
          next unless command

          submenu = menu.add_submenu(MENU_TITLE)
          submenu.add_item(command)
        end

        @context_menu_handler_attached = true
      end

      def context_menu_allows_edit_cabinet?
        return unless defined?(Sketchup)

        model = Sketchup.active_model
        result = AICabinets::Selection.require_editable_cabinet(model: model)
        result.valid?
      end

    end
  end
end
