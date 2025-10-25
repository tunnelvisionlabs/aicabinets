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
        :left_face_mm,
        :thickness_mm,
        :depth_mm,
        :height_mm,
        :bottom_z_mm,
        keyword_init: true
      )

      def build(parent_entities:, params:, material: nil)
        placements = plan_layout(params)
        return [] if placements.empty?

        placements.each_with_object([]) do |placement, memo|
          component = Parts::PartitionPanel.build(
            parent_entities: parent_entities,
            name: placement.name,
            thickness: length_mm(placement.thickness_mm),
            depth: length_mm(placement.depth_mm),
            height: length_mm(placement.height_mm),
            x_offset: length_mm(placement.left_face_mm),
            z_offset: length_mm(placement.bottom_z_mm)
          )
          next unless component&.valid?

          if material && component.respond_to?(:material=)
            component.material = material
          end
          memo << component
        end
      end

      def plan_layout(params)
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
            left_face_mm: left_mm,
            thickness_mm: thickness_mm,
            depth_mm: depth_mm,
            height_mm: height_mm,
            bottom_z_mm: bottom_z_mm
          )
        end
      end

      def length_mm(value)
        Ops::Units.to_length_mm(value)
      end
      private_class_method :length_mm
    end
  end
end

