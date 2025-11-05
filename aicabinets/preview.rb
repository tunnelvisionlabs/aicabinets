# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/ops/units')
require 'aicabinets/preview/layout'

module AICabinets
  module Preview

    OPERATION_NAME = 'AI Cabinets Preview'.freeze
    GROUP_NAME = 'AI Cabinets Preview'.freeze
    GROUP_ATTRIBUTE_DICTIONARY = 'AICabinets'.freeze
    GROUP_ATTRIBUTE_KEY = 'preview_group'.freeze
    LINES_Y_OFFSET_MM = 0.0
    HIGHLIGHT_Y_OFFSET_MM = 1.0

    class << self
      def render(config:, selected_path: [])
        return unless defined?(Sketchup) && defined?(Sketchup::Model)

        model = Sketchup.active_model
        return unless model.is_a?(Sketchup::Model)

        plan = Layout.plan(config, selected_path: selected_path)

        model.start_operation(OPERATION_NAME, true)
        group = ensure_preview_group(model)
        refresh_group!(group, plan)
        model.commit_operation
      rescue StandardError => e
        model.abort_operation if model.respond_to?(:abort_operation)
        warn("AI Cabinets: Unable to render preview: #{e.message}")
        nil
      end

      private

      def ensure_preview_group(model)
        entities = model.entities
        group = find_preview_group(entities)
        return group if group

        new_group = entities.add_group
        new_group.name = GROUP_NAME if new_group.respond_to?(:name=)
        new_group.set_attribute(GROUP_ATTRIBUTE_DICTIONARY, GROUP_ATTRIBUTE_KEY, true)
        new_group
      end

      def find_preview_group(entities)
        return nil unless entities.respond_to?(:grep)

        entities.grep(Sketchup::Group).find do |group|
          group.valid? && group.get_attribute(GROUP_ATTRIBUTE_DICTIONARY, GROUP_ATTRIBUTE_KEY)
        end
      end

      def refresh_group!(group, plan)
        return unless group&.valid?

        entities = group.entities
        clear_entities!(entities)
        draw_outline(entities, plan.outline)
        draw_partitions(entities, plan)
        draw_highlight(entities, plan.highlight_rect)
        nil
      end

      def clear_entities!(entities)
        return unless entities.respond_to?(:erase_entities)

        all = entities.to_a
        entities.erase_entities(all) unless all.empty?
      end

      def draw_outline(entities, rect)
        return unless rect

        points = [
          point_mm(rect.left, LINES_Y_OFFSET_MM, rect.bottom),
          point_mm(rect.right, LINES_Y_OFFSET_MM, rect.bottom),
          point_mm(rect.right, LINES_Y_OFFSET_MM, rect.top),
          point_mm(rect.left, LINES_Y_OFFSET_MM, rect.top)
        ]

        entities.add_edges(points[0], points[1], points[2], points[3], points[0])
      end

      def draw_partitions(entities, plan)
        lines = Layout.collect_lines(plan.container_plan)
        lines.each do |line|
          case line.orientation
          when :horizontal
            start_point = point_mm(line.range_start, LINES_Y_OFFSET_MM, line.position)
            end_point = point_mm(line.range_end, LINES_Y_OFFSET_MM, line.position)
          else
            start_point = point_mm(line.position, LINES_Y_OFFSET_MM, line.range_start)
            end_point = point_mm(line.position, LINES_Y_OFFSET_MM, line.range_end)
          end

          entities.add_line(start_point, end_point)
        end
      end

      def draw_highlight(entities, rect)
        return unless rect
        return if rect.width <= 0.0 || rect.height <= 0.0

        points = [
          point_mm(rect.left, HIGHLIGHT_Y_OFFSET_MM, rect.bottom),
          point_mm(rect.right, HIGHLIGHT_Y_OFFSET_MM, rect.bottom),
          point_mm(rect.right, HIGHLIGHT_Y_OFFSET_MM, rect.top),
          point_mm(rect.left, HIGHLIGHT_Y_OFFSET_MM, rect.top)
        ]

        face = entities.add_face(points)
        return unless face&.valid?

        color = highlight_color
        face.material = color if face.respond_to?(:material=)
        face.back_material = color if face.respond_to?(:back_material=)
        face.edges.each do |edge|
          edge.soft = true if edge.respond_to?(:soft=)
          edge.smooth = true if edge.respond_to?(:smooth=)
          edge.hidden = true if edge.respond_to?(:hidden=)
        end
      rescue StandardError => e
        warn("AI Cabinets: Unable to draw preview highlight: #{e.message}")
      end

      def highlight_color
        @highlight_color ||= Sketchup::Color.new(255, 204, 0, 80)
      end

      def point_mm(x_mm, y_mm, z_mm)
        Ops::Units.point_mm(x_mm, y_mm, z_mm)
      end
    end
  end
end
