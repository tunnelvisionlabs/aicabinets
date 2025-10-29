# frozen_string_literal: true

module AICabinets
  module UI
    module Icons
      module_function

      ICONS_DIR = File.expand_path(File.join(__dir__, '..', 'icons'))
      SMALL_SIZE = 24
      LARGE_SIZE = 32

      def small_icon_path(base_name)
        resolve_icon_path(base_name, size: SMALL_SIZE)
      end

      def large_icon_path(base_name)
        resolve_icon_path(base_name, size: LARGE_SIZE)
      end

      def cursor_icon_path(base_name)
        icon_path_for(base_name, 'png', size: LARGE_SIZE)
      end

      def resolve_icon_path(base_name, size:)
        preferred_ext = preferred_vector_extension
        preferred_path = icon_path_for(base_name, preferred_ext) if preferred_ext
        return preferred_path if preferred_path

        alternative_exts = (vector_extensions - [preferred_ext]).compact
        alternative_exts.each do |ext|
          path = icon_path_for(base_name, ext)
          return path if path
        end

        fallback = icon_path_for(base_name, 'png', size: size)
        warn_once(base_name, preferred_ext, fallback) if preferred_ext && fallback
        fallback
      end

      def preferred_vector_extension
        return unless defined?(Sketchup)

        platform = Sketchup.respond_to?(:platform) ? Sketchup.platform : nil
        case platform
        when :platform_win
          'svg'
        when :platform_osx
          'pdf'
        else
          nil
        end
      end

      def vector_extensions
        %w[pdf svg]
      end

      def icon_path_for(base_name, extension, size: nil)
        return unless extension

        filename = if extension == 'png' && size
                     format('%s_%d.%s', base_name, size, extension)
                   else
                     format('%s.%s', base_name, extension)
                   end
        path = File.join(ICONS_DIR, filename)
        File.exist?(path) ? path : nil
      end

      def warn_once(base_name, extension, fallback)
        @warned ||= {}
        key = [base_name, extension]
        return if @warned[key]
        return unless fallback

        @warned[key] = true
        warn("[AICabinets] Missing #{extension} icon for '#{base_name}', using fallback: #{File.basename(fallback)}")
      end
    end
  end
end
