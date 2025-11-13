# frozen_string_literal: true

module AICabinets
  module Rows
    module Highlight
      extend self

      ROW_HIGHLIGHT_OVERLAY_ID = 'AICabinets.Rows.Highlight'.freeze
      ROW_HIGHLIGHT_OVERLAY_NAME = 'Rows Highlight'.freeze
      ORIGIN_MARKER_SIZE_MM = 50.0
      POLYLINE_COLOR = Sketchup::Color.new(0xff, 0x66, 0x00).freeze
      LINE_WIDTH = 3
      GLYPH_LINE_WIDTH = 4

      def show(model:, row_id:, instances: [])
        model = validate_model(model)
        geometry = Geometry.build(row_id: row_id, instances: instances)

        return hide(model:) if geometry.empty?

        state = state_for(model)
        provider = ensure_provider(model, state)
        provider.show(geometry)

        state[:active_row_id] = row_id

        { ok: true, strategy: state[:strategy] }
      end

      def hide(model:)
        model = validate_model(model)
        state = state_for(model)
        provider = state[:provider]
        provider&.hide
        state.delete(:active_row_id)
        state.delete(:provider) if provider&.invalid?

        { ok: true, strategy: state[:strategy] }
      end

      def refresh(model:, row_id:, instances: [])
        model = validate_model(model)
        state = state_for(model)
        return unless state[:active_row_id] == row_id

        geometry = Geometry.build(row_id: row_id, instances: instances)
        provider = ensure_provider(model, state)
        if geometry.empty?
          provider.hide
          state.delete(:active_row_id)
        else
          provider.show(geometry)
        end
      end

      def active_row_id(model: Sketchup.active_model)
        model = validate_model(model)
        state_for(model)[:active_row_id]
      end

      def strategy(model: Sketchup.active_model)
        model = validate_model(model)
        state_for(model)[:strategy]
      end

      def overlay_supported?(model = Sketchup.active_model)
        model = validate_model(model)
        return false unless defined?(Sketchup::Overlay)
        manager = model.respond_to?(:overlays) ? model.overlays : nil
        manager.respond_to?(:add)
      end

      def reset!
        @states = nil
        @test_provider_override = nil
      end

      def test_override_provider(strategy:, factory:)
        @test_provider_override = { strategy:, factory: }
      end

      def test_clear_override!
        @test_provider_override = nil
      end

      private

      def ensure_provider(model, state)
        override = @test_provider_override
        if override
          state[:strategy] = override[:strategy]
          state[:provider] ||= override[:factory].call(model)
          return state[:provider]
        end

        if overlay_supported?(model)
          state[:strategy] = :overlay
          provider = state[:provider]
          return provider if provider.is_a?(OverlayProvider) && provider.valid?

          provider = OverlayProvider.new(model)
          state[:provider] = provider
          provider
        else
          state[:strategy] = :tool
          provider = state[:provider]
          return provider if provider.is_a?(ToolProvider) && provider.valid?

          provider = ToolProvider.new(model)
          state[:provider] = provider
          provider
        end
      end

      def state_for(model)
        states[model] ||= {}
      end

      def states
        @states ||= {}.compare_by_identity
      end

      def validate_model(model)
        return model if model.is_a?(Sketchup::Model)
        default_model = defined?(Sketchup) ? Sketchup.active_model : nil
        return default_model if default_model.is_a?(Sketchup::Model)

        raise ArgumentError, 'model must be a SketchUp::Model'
      end

      def overlay_priority
        @overlay_priority ||= begin
          if defined?(Sketchup::Overlay::PRIORITY_VIEWER)
            Sketchup::Overlay::PRIORITY_VIEWER
          elsif defined?(Sketchup::Overlay::PRIORITY_DEFAULT)
            Sketchup::Overlay::PRIORITY_DEFAULT
          elsif defined?(Sketchup::Overlay::PRIORITY_NORMAL)
            Sketchup::Overlay::PRIORITY_NORMAL
          else
            50
          end
        end
      end

      def overlay_constructor_arguments
        [
          ROW_HIGHLIGHT_OVERLAY_ID,
          ROW_HIGHLIGHT_OVERLAY_NAME,
          overlay_priority
        ]
      end

      def shrink_overlay_arguments(args)
        return nil unless args.is_a?(Array)
        return nil if args.length <= 1

        args[0, args.length - 1]
      end

      def handle_tool_deactivated(model)
        state = states[model]
        return unless state

        state.delete(:provider)
        state.delete(:active_row_id)
      end

      def invalidate_overlay(overlay, model)
        return unless overlay

        if overlay.respond_to?(:invalidate)
          begin
            overlay.invalidate
            return
          rescue ArgumentError
            view = model.respond_to?(:active_view) ? model.active_view : nil
            begin
              overlay.invalidate(view)
              return
            rescue StandardError
              # fall through to view invalidation
            end
          rescue StandardError
            # fall through to view invalidation
          end
        end

        begin
          view = model.respond_to?(:active_view) ? model.active_view : nil
          view&.invalidate
        rescue StandardError
          nil
        end
      end

      class Geometry
        attr_reader :polyline, :origin_segments, :row_id

        def self.build(row_id:, instances: [])
          new(row_id: row_id, instances: Array(instances))
        end

        def initialize(row_id:, instances: [])
          @row_id = row_id
          @polyline = extract_flb_points(instances)
          @origin_segments = build_origin_segments(@polyline.first)
        end

        def empty?
          @polyline.empty?
        end

        private

        def extract_flb_points(instances)
          instances.filter_map do |instance|
            next unless instance.respond_to?(:valid?) && instance.valid?
            bounds = instance.bounds
            next unless bounds

            min = bounds.min
            ::Geom::Point3d.new(min.x, min.y, min.z)
          rescue StandardError
            nil
          end
        end

        def build_origin_segments(origin)
          return [] unless origin.is_a?(::Geom::Point3d)

          size = ORIGIN_MARKER_SIZE_MM.mm
          [
            ::Geom::Point3d.new(origin.x - size, origin.y, origin.z),
            ::Geom::Point3d.new(origin.x + size, origin.y, origin.z),
            ::Geom::Point3d.new(origin.x, origin.y, origin.z - size),
            ::Geom::Point3d.new(origin.x, origin.y, origin.z + size),
            ::Geom::Point3d.new(origin.x, origin.y - size, origin.z),
            ::Geom::Point3d.new(origin.x, origin.y + size, origin.z)
          ]
        end
      end
      private_constant :Geometry

      class OverlayProvider
        def initialize(model)
          @model = model
          @overlay = Overlay.new(model)
          manager = model.respond_to?(:overlays) ? model.overlays : nil
          manager&.add(@overlay)
        end

        def show(geometry)
          @overlay.geometry = geometry
          Highlight.__send__(:invalidate_overlay, @overlay, @model)
        end

        def hide
          @overlay.geometry = nil
          Highlight.__send__(:invalidate_overlay, @overlay, @model)
        end

        def invalid?
          !valid?
        end

        def valid?
          @overlay&.valid_for_model?(@model)
        end

        class Overlay < Sketchup::Overlay
          def initialize(model)
            args = Highlight.__send__(:overlay_constructor_arguments)
            begin
              super(*args)
            rescue ArgumentError, TypeError
              args = Highlight.__send__(:shrink_overlay_arguments, args)
              retry if args
              raise
            end
            @model = model
            @geometry = nil
          end

          attr_writer :geometry

          def geometry
            @geometry
          end

          def valid_for_model?(model)
            @model == model
          end

          def clear
            @geometry = nil
            Highlight.__send__(:invalidate_overlay, self, @model)
          end

          def draw(view)
            geometry = @geometry
            return unless geometry

            draw_polyline(view, geometry.polyline)
            draw_origin(view, geometry.origin_segments)
          end

          private

          def draw_polyline(view, points)
            return unless points.is_a?(Array) && points.length >= 2

            view.drawing_color = POLYLINE_COLOR
            view.line_width = LINE_WIDTH
            view.line_stipple = ''
            view.draw(GL_LINE_STRIP, points)
          end

          def draw_origin(view, segments)
            return unless segments.is_a?(Array) && segments.length >= 2

            view.drawing_color = POLYLINE_COLOR
            view.line_width = GLYPH_LINE_WIDTH
            view.line_stipple = ''
            view.draw(GL_LINES, segments)
          end
        end
        private_constant :Overlay
      end
      private_constant :OverlayProvider

      class ToolProvider
        def initialize(model)
          @model = model
          @tool = Tool.new(self)
          @active = false
          @geometry = nil
        end

        def show(geometry)
          @geometry = geometry
          ensure_tool
          invalidate_view
        end

        def hide
          @geometry = nil
          invalidate_view
          pop_tool
        end

        def invalid?
          !valid?
        end

        def valid?
          @model.is_a?(Sketchup::Model)
        end

        def current_geometry
          @geometry
        end

        def mark_active(active)
          @active = active
        end

        def tool_deactivated
          @active = false
          @geometry = nil
          Highlight.__send__(:handle_tool_deactivated, @model)
        end

        private

        def ensure_tool
          return if @active

          tools = @model.tools
          tools.push_tool(@tool)
        rescue StandardError
          nil
        end

        def pop_tool
          return unless @active

          tools = @model.tools
          tools.pop_tool if tools
        rescue StandardError
          nil
        ensure
          @active = false
        end

        def invalidate_view
          view = @model.active_view if @model.respond_to?(:active_view)
          view&.invalidate
        rescue StandardError
          nil
        end

        class Tool
          include Math

          def initialize(provider)
            @provider = provider
          end

          def activate
            @provider.mark_active(true)
          end

          def deactivate(_view)
            @provider.tool_deactivated
          end

          def resume(view)
            view.invalidate
          end

          def draw(view)
            geometry = @provider.current_geometry
            return unless geometry

            draw_polyline(view, geometry.polyline)
            draw_origin(view, geometry.origin_segments)
          end

          private

          def draw_polyline(view, points)
            return unless points.is_a?(Array) && points.length >= 2

            view.drawing_color = POLYLINE_COLOR
            view.line_width = LINE_WIDTH
            view.line_stipple = ''
            view.draw(GL_LINE_STRIP, points)
          end

          def draw_origin(view, segments)
            return unless segments.is_a?(Array) && segments.length >= 2

            view.drawing_color = POLYLINE_COLOR
            view.line_width = GLYPH_LINE_WIDTH
            view.line_stipple = ''
            view.draw(GL_LINES, segments)
          end
        end
        private_constant :Tool
      end
      private_constant :ToolProvider
    end
  end
end
