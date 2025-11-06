# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/generator/bay_bounds')
Sketchup.require('aicabinets/ops/units')

module AICabinets
  module Generator
    module Fronts
      module_function

      FRONT_MODES = %i[empty doors_left doors_right doors_double].freeze

      DOOR_THICKNESS_MM = 19.0
      REVEAL_EDGE_MM = 2.0
      REVEAL_CENTER_MM = 2.0
      REVEAL_TOP_MM = 2.0
      REVEAL_BOTTOM_MM = 2.0
      MIN_DIMENSION_MM = 1.0e-3

      DoorPlacement = Struct.new(
        :name,
        :bay_index,
        :x_start_mm,
        :width_mm,
        :height_mm,
        :bottom_z_mm,
        keyword_init: true
      )

      def build(parent_entities:, params:)
        validate_parent!(parent_entities)
        return [] unless params.respond_to?(:front_mode)

        placements = plan_layout(params)
        return [] if placements.empty?

        thickness_mm = params.door_thickness_mm.to_f
        return [] unless thickness_mm > MIN_DIMENSION_MM

        thickness = length_mm(thickness_mm)
        placements.each_with_object([]) do |placement, memo|
          width = length_mm(placement.width_mm)
          height = length_mm(placement.height_mm)
          next unless width > 0 && height > 0

          component = build_single_door(
            parent_entities,
            placement,
            width: width,
            height: height,
            thickness: thickness
          )
          next unless component&.valid?

          memo << component
        end
      end

      def plan_layout(params)
        per_bay = plan_layout_from_bays(params)
        return per_bay if per_bay.any?

        plan_layout_from_front_mode(params)
      end

      def length_mm(value)
        Ops::Units.to_length_mm(value)
      end
      private_class_method :length_mm

      def build_single_door(parent_entities, placement, width:, height:, thickness:)
        group = parent_entities.add_group
        group.name = placement.name if group.respond_to?(:name=)

        face = group.entities.add_face(
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(width, 0, 0),
          Geom::Point3d.new(width, 0, height),
          Geom::Point3d.new(0, 0, height)
        )
        face.reverse! if face.normal.y.positive?
        face.pushpull(thickness)

        translation = Geom::Transformation.translation([
          length_mm(placement.x_start_mm),
          0,
          length_mm(placement.bottom_z_mm)
        ])
        group.transform!(translation)

        component = group.to_component
        definition = component.definition
        definition.name = placement.name if definition.respond_to?(:name=)
        component.name = placement.name if component.respond_to?(:name=)
        component
      end
      private_class_method :build_single_door

      def toe_kick_clearance_mm(params)
        return 0.0 unless params.respond_to?(:toe_kick_height_mm)
        return 0.0 unless params.respond_to?(:toe_kick_depth_mm)

        height_mm = params.toe_kick_height_mm.to_f
        depth_mm = params.toe_kick_depth_mm.to_f
        return 0.0 unless height_mm.positive? && depth_mm.positive?

        height_mm
      end
      private_class_method :toe_kick_clearance_mm

      def plan_layout_from_bays(params)
        vertical_bounds = door_vertical_bounds(params)
        return [] unless vertical_bounds

        bays = params.partition_bays
        return [] if bays.empty?

        left_reveal_mm = params.door_edge_reveal_mm.to_f
        right_reveal_mm = params.door_edge_reveal_mm.to_f
        center_gap_mm = params.door_center_reveal_mm.to_f

        total_bays = bays.length

        bays.each_with_object([]) do |bay, memo|
          next unless bay.leaf?

          mode = bay.door_mode
          next if mode == :none

          bounds = BayBounds.interior_bounds(params: params, bay: bay)
          next unless bounds

          placements = build_bay_fronts(
            bay: bay,
            bounds: bounds,
            left_reveal_mm: left_reveal_mm,
            right_reveal_mm: right_reveal_mm,
            center_gap_mm: center_gap_mm,
            vertical_bounds: vertical_bounds,
            total_bays: total_bays
          )
          memo.concat(placements)
        end
      end
      private_class_method :plan_layout_from_bays

      def build_bay_fronts(bay:, bounds:, left_reveal_mm:, right_reveal_mm:, center_gap_mm:, vertical_bounds:, total_bays:)
        clear_width_mm = bounds.width_mm - left_reveal_mm - right_reveal_mm
        if clear_width_mm <= MIN_DIMENSION_MM
          warn_skip("Skipped doors for bay #{bay.index + 1} because reveals consumed the width.")
          return []
        end

        base_x = bounds.x_start_mm + left_reveal_mm
        case bay.door_mode
        when :left
          [DoorPlacement.new(
            name: door_name(:left, bay.index, total_bays),
            bay_index: bay.index,
            x_start_mm: base_x,
            width_mm: clear_width_mm,
            height_mm: vertical_bounds[:clear_height_mm],
            bottom_z_mm: vertical_bounds[:bottom_z_mm]
          )]
        when :right
          [DoorPlacement.new(
            name: door_name(:right, bay.index, total_bays),
            bay_index: bay.index,
            x_start_mm: base_x,
            width_mm: clear_width_mm,
            height_mm: vertical_bounds[:clear_height_mm],
            bottom_z_mm: vertical_bounds[:bottom_z_mm]
          )]
        when :double
          usable_width_mm = clear_width_mm - center_gap_mm
          if usable_width_mm <= MIN_DIMENSION_MM
            warn_skip("Skipped double doors for bay #{bay.index + 1} because the gap exceeded the width.")
            return []
          end

          leaf_width_mm = usable_width_mm / 2.0
          if leaf_width_mm <= MIN_DIMENSION_MM
            warn_skip("Skipped double doors for bay #{bay.index + 1} because each leaf would be too narrow.")
            return []
          end

          [
            DoorPlacement.new(
              name: door_name(:double_left, bay.index, total_bays),
              bay_index: bay.index,
              x_start_mm: base_x,
              width_mm: leaf_width_mm,
              height_mm: vertical_bounds[:clear_height_mm],
              bottom_z_mm: vertical_bounds[:bottom_z_mm]
            ),
            DoorPlacement.new(
              name: door_name(:double_right, bay.index, total_bays),
              bay_index: bay.index,
              x_start_mm: base_x + leaf_width_mm + center_gap_mm,
              width_mm: leaf_width_mm,
              height_mm: vertical_bounds[:clear_height_mm],
              bottom_z_mm: vertical_bounds[:bottom_z_mm]
            )
          ]
        else
          []
        end
      end
      private_class_method :build_bay_fronts

      def plan_layout_from_front_mode(params)
        mode = params.front_mode
        return [] unless FRONT_MODES.include?(mode)
        return [] if mode == :empty

        vertical_bounds = door_vertical_bounds(params)
        return [] unless vertical_bounds

        left_reveal_mm = params.door_edge_reveal_mm.to_f
        right_reveal_mm = params.door_edge_reveal_mm.to_f
        clear_width_mm = params.width_mm.to_f - left_reveal_mm - right_reveal_mm
        if clear_width_mm <= MIN_DIMENSION_MM
          warn_skip('Skipped doors because reveals consumed the cabinet width.')
          return []
        end

        center_gap_mm = params.door_center_reveal_mm.to_f
        base_x = left_reveal_mm

        case mode
        when :doors_left
          [DoorPlacement.new(
            name: door_name(:left, 0, 1),
            bay_index: 0,
            x_start_mm: base_x,
            width_mm: clear_width_mm,
            height_mm: vertical_bounds[:clear_height_mm],
            bottom_z_mm: vertical_bounds[:bottom_z_mm]
          )]
        when :doors_right
          [DoorPlacement.new(
            name: door_name(:right, 0, 1),
            bay_index: 0,
            x_start_mm: base_x,
            width_mm: clear_width_mm,
            height_mm: vertical_bounds[:clear_height_mm],
            bottom_z_mm: vertical_bounds[:bottom_z_mm]
          )]
        when :doors_double
          usable_width_mm = clear_width_mm - center_gap_mm
          if usable_width_mm <= MIN_DIMENSION_MM
            warn_skip('Skipped double doors because the center gap exceeded the available width.')
            return []
          end

          leaf_width_mm = usable_width_mm / 2.0
          if leaf_width_mm <= MIN_DIMENSION_MM
            warn_skip('Skipped double doors because each leaf would be too narrow.')
            return []
          end

          [
            DoorPlacement.new(
              name: door_name(:double_left, 0, 1),
              bay_index: 0,
              x_start_mm: base_x,
              width_mm: leaf_width_mm,
              height_mm: vertical_bounds[:clear_height_mm],
              bottom_z_mm: vertical_bounds[:bottom_z_mm]
            ),
            DoorPlacement.new(
              name: door_name(:double_right, 0, 1),
              bay_index: 0,
              x_start_mm: base_x + leaf_width_mm + center_gap_mm,
              width_mm: leaf_width_mm,
              height_mm: vertical_bounds[:clear_height_mm],
              bottom_z_mm: vertical_bounds[:bottom_z_mm]
            )
          ]
        else
          []
        end
      end
      private_class_method :plan_layout_from_front_mode

      def door_vertical_bounds(params)
        thickness_mm = params.door_thickness_mm.to_f
        unless thickness_mm > MIN_DIMENSION_MM
          warn_skip('Skipped doors because door_thickness_mm was not positive.')
          return nil
        end

        total_height_mm = params.height_mm.to_f
        toe_kick_offset_mm = toe_kick_clearance_mm(params)
        available_height_mm = total_height_mm - toe_kick_offset_mm
        top_reveal_mm = params.door_top_reveal_mm.to_f
        bottom_reveal_mm = params.door_bottom_reveal_mm.to_f

        clear_height_mm = available_height_mm - top_reveal_mm - bottom_reveal_mm
        if clear_height_mm <= MIN_DIMENSION_MM
          warn_skip('Skipped doors because reveals consumed the cabinet height.')
          return nil
        end

        {
          clear_height_mm: clear_height_mm,
          bottom_z_mm: toe_kick_offset_mm + bottom_reveal_mm
        }
      end
      private_class_method :door_vertical_bounds

      def door_name(mode, bay_index, total_bays)
        suffix =
          case mode
          when :left
            'Hinge Left'
          when :right
            'Hinge Right'
          when :double_left
            'Left'
          when :double_right
            'Right'
          else
            'Door'
          end

        return "Door (#{suffix})" if total_bays <= 1

        "Door (Bay #{bay_index + 1}, #{suffix})"
      end
      private_class_method :door_name

      def validate_parent!(parent_entities)
        unless parent_entities.is_a?(Sketchup::Entities)
          raise ArgumentError, 'parent_entities must be Sketchup::Entities'
        end
      end
      private_class_method :validate_parent!

      def warn_skip(message)
        warn("AI Cabinets: #{message}")
      end
      private_class_method :warn_skip
    end
  end
end
