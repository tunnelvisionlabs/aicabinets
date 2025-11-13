# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/generator/bay_bounds')
Sketchup.require('aicabinets/ops/units')

module AICabinets
  module Generator
    module Shelves
      module_function

      # Small clearances applied when laying out shelves. Values are in
      # millimeters so callers can tweak spacing in a single location.
      FRONT_SETBACK_MM = 3.0
      REAR_CLEARANCE_MM = 2.0
      MIN_VERTICAL_GAP_MM = 20.0
      MIN_BAY_WIDTH_MM = 5.0
      MIN_DEPTH_MM = 5.0
      EPSILON_MM = 1.0e-3

      LayoutResult = Struct.new(:placements, keyword_init: true)

      Placement = Struct.new(
        :name,
        :bay_index,
        :width_mm,
        :depth_mm,
        :top_z_mm,
        :x_start_mm,
        :thickness_mm,
        :front_offset_mm,
        keyword_init: true
      )

      def build(parent_entities:, params:, material: nil)
        layout = plan_layout(params)
        return [] unless layout

        layout.placements.each_with_object([]) do |placement, memo|
          component = build_single_shelf(parent_entities, placement)
          next unless component&.valid?

          component.material = material if material && component.respond_to?(:material=)
          memo << component
        end
      end

      def plan_layout(params)
        placements = params.partition_bays.each_with_object([]) do |bay, memo|
          next unless bay.leaf?
          next unless bay.shelf_count.positive?

          bounds = BayBounds.interior_bounds(params: params, bay: bay)
          next unless bounds
          next if bounds.width_mm <= MIN_BAY_WIDTH_MM

          depth_mm = bounds.interior_depth_mm - FRONT_SETBACK_MM - REAR_CLEARANCE_MM
          next if depth_mm <= MIN_DEPTH_MM

          bay_name = shelf_name(bay.index, params.partition_bays.length)
          plan_bay_shelves(
            memo,
            name: bay_name,
            bay_index: bay.index,
            bounds: bounds,
            depth_mm: depth_mm,
            shelf_count: bay.shelf_count,
            shelf_thickness_mm: params.shelf_thickness_mm
          )
        end

        return if placements.empty?

        LayoutResult.new(placements: placements)
      end

      def build_single_shelf(parent_entities, placement)
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
        face.pushpull(-thickness)

        translation = Geom::Transformation.translation([
          length_mm(placement.x_start_mm),
          length_mm(placement.front_offset_mm),
          length_mm(placement.top_z_mm)
        ])
        group.transform!(translation)

        component = group.to_component
        definition = component.definition
        definition.name = placement.name if definition.respond_to?(:name=)
        component.name = placement.name if component.respond_to?(:name=)
        component
      end

      def length_mm(value)
        Ops::Units.to_length_mm(value)
      end
      private_class_method :length_mm

      def plan_bay_shelves(placements, name:, bay_index:, bounds:, depth_mm:, shelf_count:, shelf_thickness_mm:)
        shelves_to_place = [shelf_count.to_i, 0].max
        return if shelves_to_place <= 0

        clear_height_mm = bounds.interior_height_mm
        return if clear_height_mm <= EPSILON_MM

        gap_mm = resolve_gap(clear_height_mm, shelf_thickness_mm, shelves_to_place)
        return unless gap_mm

        current_bottom_mm = bounds.interior_bottom_z_mm + gap_mm
        shelves_to_place.times do
          top_z_mm = current_bottom_mm + shelf_thickness_mm
          placements << Placement.new(
            name: name,
            bay_index: bay_index,
            width_mm: bounds.width_mm,
            depth_mm: depth_mm,
            top_z_mm: top_z_mm,
            x_start_mm: bounds.x_start_mm,
            thickness_mm: shelf_thickness_mm,
            front_offset_mm: FRONT_SETBACK_MM
          )
          current_bottom_mm += shelf_thickness_mm + gap_mm
        end
      end
      private_class_method :plan_bay_shelves

      def resolve_gap(clear_height_mm, shelf_thickness_mm, shelves_to_place)
        remaining_shelves = shelves_to_place
        gap_mm = nil

        while remaining_shelves.positive?
          remaining_clear_mm = clear_height_mm - (shelf_thickness_mm * remaining_shelves)
          if remaining_clear_mm <= EPSILON_MM
            remaining_shelves -= 1
            next
          end

          tentative_gap_mm = remaining_clear_mm / (remaining_shelves + 1)
          if tentative_gap_mm >= MIN_VERTICAL_GAP_MM
            gap_mm = tentative_gap_mm
            break
          end

          remaining_shelves -= 1
        end

        return unless gap_mm

        gap_mm
      end
      private_class_method :resolve_gap

      def shelf_name(bay_index, total_bays)
        return 'Shelf' if total_bays <= 1

        "Shelf (Bay #{bay_index + 1})"
      end
      private_class_method :shelf_name
    end
  end
end

