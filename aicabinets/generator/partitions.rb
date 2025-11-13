# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/generator/parts/partition_panel')
Sketchup.require('aicabinets/ops/units')

module AICabinets
  module Generator
    module Partitions
      module_function

      MIN_DIMENSION_MM = 1.0e-3

      Placement = Struct.new(
        :name,
        :orientation,
        :left_face_mm,
        :thickness_mm,
        :depth_mm,
        :height_mm,
        :bottom_z_mm,
        :width_mm,
        :x_offset_mm,
        :y_offset_mm,
        keyword_init: true
      )

      def build(parent_entities:, params:, material: nil)
        placements = plan_layout(params)
        return [] if placements.empty?

        placements.each_with_object([]) do |placement, memo|
          component =
            case placement.orientation
            when :horizontal
              build_horizontal_partition(parent_entities, placement)
            else
              build_vertical_partition(parent_entities, placement)
            end
          next unless component&.valid?

          if material && component.respond_to?(:material=)
            component.material = material
          end
          memo << component
        end
      end

      def plan_layout(params)
        case partition_orientation(params)
        when :horizontal
          plan_horizontal_layout(params)
        else
          plan_vertical_layout(params)
        end
      end

      def length_mm(value)
        Ops::Units.to_length_mm(value)
      end
      private_class_method :length_mm

      def partition_orientation(params)
        return unless params.respond_to?(:partition_orientation)

        params.partition_orientation
      end
      private_class_method :partition_orientation

      def plan_vertical_layout(params)
        left_faces = Array(params.partition_left_faces_mm).map { |value| value.to_f }.sort
        return [] if left_faces.empty?

        thickness_mm = params.partition_thickness_mm.to_f
        depth_mm = params.interior_depth_mm.to_f
        height_mm = params.interior_clear_height_mm.to_f
        bottom_z_mm = params.interior_bottom_z_mm.to_f

        return [] if [thickness_mm, depth_mm, height_mm].any? { |value| value <= MIN_DIMENSION_MM }

        left_faces.each_with_index.map do |left_mm, index|
          Placement.new(
            name: "Partition #{index + 1}",
            orientation: :vertical,
            left_face_mm: left_mm,
            thickness_mm: thickness_mm,
            depth_mm: depth_mm,
            height_mm: height_mm,
            bottom_z_mm: bottom_z_mm
          )
        end
      end
      private_class_method :plan_vertical_layout

      def plan_horizontal_layout(params)
        faces = Array(params.partition_left_faces_mm).map { |value| value.to_f }.sort
        return [] if faces.empty?

        thickness_mm = params.partition_thickness_mm.to_f
        depth_mm = params.interior_depth_mm.to_f
        width_mm = horizontal_partition_width_mm(params)
        x_offset_mm = params.panel_thickness_mm.to_f
        y_offset_mm = 0.0

        return [] if [thickness_mm, depth_mm, width_mm].any? { |value| value <= MIN_DIMENSION_MM }

        faces.each_with_index.map do |bottom_mm, index|
          Placement.new(
            name: "Partition #{index + 1}",
            orientation: :horizontal,
            bottom_z_mm: bottom_mm,
            thickness_mm: thickness_mm,
            depth_mm: depth_mm,
            width_mm: width_mm,
            x_offset_mm: x_offset_mm,
            y_offset_mm: y_offset_mm
          )
        end
      end
      private_class_method :plan_horizontal_layout

      def horizontal_partition_width_mm(params)
        width_mm = params.width_mm.to_f - (params.panel_thickness_mm.to_f * 2.0)
        [width_mm, 0.0].max
      end
      private_class_method :horizontal_partition_width_mm

      def build_vertical_partition(parent_entities, placement)
        Parts::PartitionPanel.build(
          parent_entities: parent_entities,
          name: placement.name,
          thickness: length_mm(placement.thickness_mm),
          depth: length_mm(placement.depth_mm),
          height: length_mm(placement.height_mm),
          x_offset: length_mm(placement.left_face_mm),
          z_offset: length_mm(placement.bottom_z_mm)
        )
      end
      private_class_method :build_vertical_partition

      def build_horizontal_partition(parent_entities, placement)
        width = length_mm(placement.width_mm)
        depth = length_mm(placement.depth_mm)
        thickness = length_mm(placement.thickness_mm)
        return unless width > 0 && depth > 0 && thickness > 0

        group = parent_entities.add_group
        group.name = placement.name if group.respond_to?(:name=)

        face = group.entities.add_face(
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(width, 0, 0),
          Geom::Point3d.new(width, depth, 0),
          Geom::Point3d.new(0, depth, 0)
        )
        face.reverse! if face.normal.z < 0
        face.pushpull(thickness)

        translation = Geom::Transformation.translation([
          length_mm(placement.x_offset_mm),
          length_mm(placement.y_offset_mm || 0.0),
          length_mm(placement.bottom_z_mm)
        ])
        group.transform!(translation)

        component = group.to_component
        definition = component.definition
        if definition.respond_to?(:name=)
          definition.name = placement.name
        end
        component.name = placement.name if component.respond_to?(:name=)
        component
      end
      private_class_method :build_horizontal_partition
    end
  end
end

