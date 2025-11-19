# frozen_string_literal: true

module AICabinets
  module Commands
    # Registers UI::Command instances for the face frame workflow.
    module FaceFrame
      module_function

      def register!(registry)
        return unless defined?(::UI::Command)

        registry[:face_frame_insert] ||= insert_command
        registry[:face_frame_edit] ||= edit_command
      end

      def insert_command
        @insert_command ||= build_insert_command
      end
      private_class_method :insert_command

      def edit_command
        @edit_command ||= build_edit_command
      end
      private_class_method :edit_command

      def build_insert_command
        command = ::UI::Command.new('Cabinet (Face Frame)') do
          execute_insert
        end
        command.tooltip = 'Insert Cabinet (Face Frame)'
        command.status_bar_text = 'Insert a new cabinet with a face frame'
        assign_command_icons(command, 'face_frame_insert')
        command
      end
      private_class_method :build_insert_command

      def build_edit_command
        command = ::UI::Command.new('Edit Cabinet (Face Frame)') do
          execute_edit
        end
        command.tooltip = 'Edit selected cabinet (Face Frame)'
        command.status_bar_text = 'Open options for the selected cabinet'
        assign_command_icons(command, 'face_frame_edit')
        attach_validation(command)
        command
      end
      private_class_method :build_edit_command

      def execute_insert
        dialog = face_frame_dialog
        unless dialog
          warn('AI Cabinets: Face Frame options dialog is unavailable.')
          return nil
        end

        defaults = face_frame_defaults

        if dialog.respond_to?(:show_for_insert)
          dialog.show_for_insert(defaults: defaults)
        elsif dialog.respond_to?(:show)
          dialog.show(defaults: defaults)
        else
          warn('AI Cabinets: Face Frame dialog does not support insert.')
        end
        nil
      end

      def execute_edit(model: nil)
        dialog = face_frame_dialog
        unless dialog
          warn('AI Cabinets: Face Frame options dialog is unavailable.')
          return nil
        end

        selection = selection_result(model: model)
        unless selection.valid?
          notify_selection_issue(selection.message)
          return nil
        end

        instance = selection.instance
        if dialog.respond_to?(:show_for_edit)
          dialog.show_for_edit(instance: instance)
        elsif dialog.respond_to?(:show)
          dialog.show(instance: instance)
        else
          warn('AI Cabinets: Face Frame dialog does not support edit.')
        end
        nil
      end

      def selection_result(model: nil)
        return AICabinets::Selection.require_editable_cabinet(model: model) if defined?(AICabinets::Selection)

        Struct.new(:status, :instance, :message) { def valid? = false }.new(:unavailable, nil, 'Selection tools unavailable')
      end
      private_class_method :selection_result

      def valid_selection?(model: nil)
        selection_result(model: model).valid?
      end

      def face_frame_defaults
        return {} unless defined?(AICabinets::Ops::Defaults)

        defaults = AICabinets::Ops::Defaults.load_insert_base_cabinet
        face_frame = defaults[:face_frame] ||= {}
        face_frame[:enabled] = true
        defaults
      rescue StandardError => e
        warn("AI Cabinets: Failed to load defaults for face frame insert: #{e.message}")
        {}
      end
      private_class_method :face_frame_defaults

      def assign_command_icons(command, base_name)
        return unless defined?(AICabinets::UI::Icons)

        small_icon = AICabinets::UI::Icons.small_icon_path(base_name)
        large_icon = AICabinets::UI::Icons.large_icon_path(base_name)
        command.small_icon = small_icon if small_icon
        command.large_icon = large_icon if large_icon
      end
      private_class_method :assign_command_icons

      def face_frame_dialog
        if defined?(AICabinets::UI::Dialogs::FaceFrameOptions)
          return AICabinets::UI::Dialogs::FaceFrameOptions
        end

        warn('AI Cabinets: Face Frame Options dialog is not loaded.')
        nil
      end
      private_class_method :face_frame_dialog

      def attach_validation(command)
        return unless command.respond_to?(:set_validation_proc)
        return unless defined?(MF_GRAYED) && defined?(MF_ENABLED)

        command.set_validation_proc do
          valid_selection? ? MF_ENABLED : MF_GRAYED
        rescue StandardError
          MF_GRAYED
        end
      end
      private_class_method :attach_validation

      def notify_selection_issue(message)
        warn("AI Cabinets: #{message}")
        return unless defined?(::UI)
        return unless ::UI.respond_to?(:messagebox)

        button_type = defined?(::MB_OK) ? ::MB_OK : 0
        ::UI.messagebox(message, button_type, 'AI Cabinets')
      end
      private_class_method :notify_selection_issue
    end
  end
end
