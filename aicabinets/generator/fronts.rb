# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/geometry/bay_openings')
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
        bay_ranges = params.partition_bay_ranges_mm
        return [] unless bay_ranges.any?

        bay_settings = params.respond_to?(:bay_settings) ? params.bay_settings : []
        return [] if bay_settings.empty?

        openings = Geometry::BayOpenings.compute(
          bay_ranges_mm: bay_ranges,
          edge_reveal_mm: params.door_edge_reveal_mm.to_f,
          top_reveal_mm: params.door_top_reveal_mm.to_f,
          bottom_reveal_mm: params.door_bottom_reveal_mm.to_f,
          toe_kick_height_mm: params.toe_kick_height_mm.to_f,
          toe_kick_depth_mm: params.toe_kick_depth_mm.to_f,
          cabinet_height_mm: params.height_mm.to_f
        )

        center_gap_mm = params.door_center_reveal_mm.to_f
        bay_count = [bay_ranges.length, bay_settings.length].min

        placements = []
        openings.each do |opening|
          setting = bay_settings[opening.index]
          next unless setting

          mode = normalize_bay_mode(setting.door_mode)
          next unless mode

          if opening.width_mm <= MIN_DIMENSION_MM
            warn_skip("Skipped doors in bay #{opening.index + 1}; reveals consumed the bay width.")
            next
          end

          if opening.height_mm <= MIN_DIMENSION_MM
            warn_skip("Skipped doors in bay #{opening.index + 1}; reveals consumed the cabinet height.")
            next
          end

          case mode
          when :doors_left
            placements << DoorPlacement.new(
              name: bay_name('Door (Hinge Left)', opening.index, bay_count),
              x_start_mm: opening.left_mm,
              width_mm: opening.width_mm,
              height_mm: opening.height_mm,
              bottom_z_mm: opening.bottom_mm
            )
          when :doors_right
            placements << DoorPlacement.new(
              name: bay_name('Door (Hinge Right)', opening.index, bay_count),
              x_start_mm: opening.left_mm,
              width_mm: opening.width_mm,
              height_mm: opening.height_mm,
              bottom_z_mm: opening.bottom_mm
            )
          when :doors_double
            usable_width_mm = opening.width_mm - center_gap_mm
            if usable_width_mm <= MIN_DIMENSION_MM
              warn_skip("Skipped double doors in bay #{opening.index + 1}; center gap exceeded available width.")
              next
            end

            leaf_width_mm = usable_width_mm / 2.0
            if leaf_width_mm <= MIN_DIMENSION_MM
              warn_skip("Skipped double doors in bay #{opening.index + 1}; each leaf would be too narrow.")
              next
            end

            left_name = bay_name('Door (Left)', opening.index, bay_count)
            right_name = bay_name('Door (Right)', opening.index, bay_count)
            placements << DoorPlacement.new(
              name: left_name,
              x_start_mm: opening.left_mm,
              width_mm: leaf_width_mm,
              height_mm: opening.height_mm,
              bottom_z_mm: opening.bottom_mm
            )
            placements << DoorPlacement.new(
              name: right_name,
              x_start_mm: opening.left_mm + leaf_width_mm + center_gap_mm,
              width_mm: leaf_width_mm,
              height_mm: opening.height_mm,
              bottom_z_mm: opening.bottom_mm
            )
          end
        end

        placements
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

      def normalize_bay_mode(value)
        return nil if value.nil?

        candidate =
          case value
          when Symbol
            value
          when String
            value.strip.downcase.to_sym
          end

        return nil unless candidate
        return nil if candidate == :none || candidate == :empty
        return candidate if FRONT_MODES.include?(candidate)

        nil
      rescue StandardError
        nil
      end
      private_class_method :normalize_bay_mode

      def bay_name(base, bay_index, total_bays)
        return base if total_bays <= 1

        "#{base} (Bay #{bay_index + 1})"
      end
      private_class_method :bay_name
    end
  end
end
