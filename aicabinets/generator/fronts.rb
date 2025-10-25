# frozen_string_literal: true

require 'sketchup.rb'

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
        :x_start_mm,
        :width_mm,
        :height_mm,
        :bottom_z_mm,
        keyword_init: true
      )

      def build(parent_entities:, params:)
        validate_parent!(parent_entities)
        return [] unless params&.respond_to?(:front_mode)

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
        mode = params.front_mode
        return [] unless FRONT_MODES.include?(mode)
        return [] if mode == :empty

        thickness_mm = params.door_thickness_mm.to_f
        unless thickness_mm > MIN_DIMENSION_MM
          warn_skip('Skipped doors because door_thickness_mm was not positive.')
          return []
        end

        width_mm = params.width_mm.to_f
        height_mm = params.height_mm.to_f
        left_reveal_mm = params.door_edge_reveal_mm.to_f
        right_reveal_mm = params.door_edge_reveal_mm.to_f
        top_reveal_mm = params.door_top_reveal_mm.to_f
        bottom_reveal_mm = params.door_bottom_reveal_mm.to_f
        center_gap_mm = params.door_center_reveal_mm.to_f

        clear_width_mm = width_mm - left_reveal_mm - right_reveal_mm
        if clear_width_mm <= MIN_DIMENSION_MM
          warn_skip('Skipped doors because reveals consumed the cabinet width.')
          return []
        end

        clear_height_mm = height_mm - top_reveal_mm - bottom_reveal_mm
        if clear_height_mm <= MIN_DIMENSION_MM
          warn_skip('Skipped doors because reveals consumed the cabinet height.')
          return []
        end

        bottom_z_mm = bottom_reveal_mm

        case mode
        when :doors_left
          [DoorPlacement.new(
            name: 'Left Door',
            x_start_mm: left_reveal_mm,
            width_mm: clear_width_mm,
            height_mm: clear_height_mm,
            bottom_z_mm: bottom_z_mm
          )]
        when :doors_right
          [DoorPlacement.new(
            name: 'Right Door',
            x_start_mm: left_reveal_mm,
            width_mm: clear_width_mm,
            height_mm: clear_height_mm,
            bottom_z_mm: bottom_z_mm
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
              name: 'Left Door',
              x_start_mm: left_reveal_mm,
              width_mm: leaf_width_mm,
              height_mm: clear_height_mm,
              bottom_z_mm: bottom_z_mm
            ),
            DoorPlacement.new(
              name: 'Right Door',
              x_start_mm: left_reveal_mm + leaf_width_mm + center_gap_mm,
              width_mm: leaf_width_mm,
              height_mm: clear_height_mm,
              bottom_z_mm: bottom_z_mm
            )
          ]
        else
          []
        end
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
        definition.name = placement.name if definition&.respond_to?(:name=)
        component.name = placement.name if component.respond_to?(:name=)
        component
      end
      private_class_method :build_single_door

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
