# frozen_string_literal: true

if defined?(Sketchup) && defined?(Sketchup::Model)
  klass = Sketchup::Model

  unless klass.method_defined?(:undo)
    klass.class_eval do
      def undo
        if Sketchup.respond_to?(:send_action)
          Sketchup.send_action('editUndo:')
        else
          raise NoMethodError, 'SketchUp undo is unavailable in this environment.'
        end
      end
    end
  end

  unless klass.method_defined?(:redo)
    klass.class_eval do
      def redo
        if Sketchup.respond_to?(:send_action)
          Sketchup.send_action('editRedo:')
        else
          raise NoMethodError, 'SketchUp redo is unavailable in this environment.'
        end
      end
    end
  end
end
