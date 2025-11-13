# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/generator/bay_bounds')
Sketchup.require('aicabinets/ops/units')
Sketchup.require('aicabinets/defaults')

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

      def effective_double_leaf_width_mm(bay_interior_width_mm:, overlay_mm:, reveal_mm:, door_gap_mm:)
        width_mm = bay_interior_width_mm.to_f
        overlay_total_mm = [overlay_mm.to_f, 0.0].max
        reveal_total_mm = [reveal_mm.to_f, 0.0].max
        gap_mm = [door_gap_mm.to_f, 0.0].max

        usable_width_mm = width_mm + overlay_total_mm - reveal_total_mm - gap_mm
        return 0.0 if usable_width_mm <= MIN_DIMENSION_MM

        usable_width_mm / 2.0
      end

      def double_allowed?(bay_interior_width_mm:, overlay_mm:, reveal_mm:, door_gap_mm:, min_leaf_width_mm: nil,
                          leaf_width_mm: nil)
        minimum_mm = min_leaf_width_mm
        minimum_mm = min_double_leaf_width_mm if minimum_mm.nil? || minimum_mm <= MIN_DIMENSION_MM

        candidate_mm = leaf_width_mm ||
                       effective_double_leaf_width_mm(
                         bay_interior_width_mm: bay_interior_width_mm,
                         overlay_mm: overlay_mm,
                         reveal_mm: reveal_mm,
                         door_gap_mm: door_gap_mm
                       )

        candidate_mm >= minimum_mm - MIN_DIMENSION_MM
      end

      def min_double_leaf_width_mm
        value = extract_min_leaf_width_mm(AICabinets::Defaults.load_effective_mm)
        return value if value && value > MIN_DIMENSION_MM

        extract_min_leaf_width_mm(AICabinets::Defaults.load_mm) || 0.0
      rescue StandardError
        0.0
      end

      def extract_min_leaf_width_mm(container)
        return nil unless container.is_a?(Hash)

        constraints = container[:constraints] || container['constraints'] || {}
        value = constraints[:min_door_leaf_width_mm] || constraints['min_door_leaf_width_mm']
        numeric =
          case value
          when Numeric
            value.to_f
          when String
            Float(value)
          else
            nil
          end
        return nil if numeric.nil? || numeric <= MIN_DIMENSION_MM

        numeric
      rescue ArgumentError
        nil
      end
      private_class_method :extract_min_leaf_width_mm

      DoorPlacement = Struct.new(
        :name,
        :bay_index,
        :x_start_mm,
        :width_mm,
        :height_mm,
        :bottom_z_mm,
        keyword_init: true
      )

      FRONTS_TAG_NAME = 'AICabinets/Fronts'.freeze

      def build(parent_entities:, params:)
        validate_parent!(parent_entities)
        return [] unless params.respond_to?(:front_mode)

        clear_existing_fronts(parent_entities)

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

        return per_bay if params.respond_to?(:partition_bays) && params.partition_bays.any?

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
          ::Geom::Point3d.new(0, 0, 0),
          ::Geom::Point3d.new(width, 0, 0),
          ::Geom::Point3d.new(width, 0, height),
          ::Geom::Point3d.new(0, 0, height)
        )
        face.reverse! if face.normal.y.positive?
        face.pushpull(thickness)

        translation = ::Geom::Transformation.translation([
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
        bays = params.partition_bays
        return [] if bays.empty?

        front_presence = bays.map { |bay| bay.leaf? && bay.door_mode != :none }
        center_gap_mm = params.door_center_reveal_mm.to_f

        total_bays = bays.length
        orientation = partition_orientation(params)

        bays.each_with_object([]) do |bay, memo|
          next unless bay.leaf?

          mode = bay.door_mode
          next if mode == :none

          bounds = BayBounds.interior_bounds(params: params, bay: bay)
          next unless bounds

          opening_left_mm, opening_right_mm = bay_opening_bounds(
            params: params,
            bounds: bounds,
            total_bays: total_bays,
            orientation: orientation
          )

          next unless opening_right_mm - opening_left_mm > MIN_DIMENSION_MM

          vertical_bounds = bay_vertical_bounds(
            params: params,
            bays: bays,
            bay: bay,
            bounds: bounds,
            total_bays: total_bays,
            front_presence: front_presence,
            orientation: orientation
          )
          next unless vertical_bounds

          left_reveal_mm = bay_edge_reveal_mm(
            params: params,
            bay_index: bay.index,
            total_bays: total_bays,
            side: :left,
            front_presence: front_presence,
            orientation: orientation
          )
          right_reveal_mm = bay_edge_reveal_mm(
            params: params,
            bay_index: bay.index,
            total_bays: total_bays,
            side: :right,
            front_presence: front_presence,
            orientation: orientation
          )

          placements = build_bay_fronts(
            bay: bay,
            opening_left_mm: opening_left_mm,
            opening_right_mm: opening_right_mm,
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

      def build_bay_fronts(bay:, opening_left_mm:, opening_right_mm:, left_reveal_mm:, right_reveal_mm:, center_gap_mm:, vertical_bounds:, total_bays:)
        door_left_mm = opening_left_mm + left_reveal_mm
        door_right_mm = opening_right_mm - right_reveal_mm
        clear_width_mm = door_right_mm - door_left_mm
        if clear_width_mm <= MIN_DIMENSION_MM
          warn_skip("Skipped doors for bay #{bay.index + 1} because reveals consumed the width.")
          return []
        end

        base_x = door_left_mm
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
          opening_width_mm = opening_right_mm - opening_left_mm
          overlay_total_mm = [opening_width_mm - bay.width_mm.to_f, 0.0].max
          reveal_total_mm = left_reveal_mm + right_reveal_mm
          gap_mm = center_gap_mm.to_f

          usable_width_mm = bay.width_mm.to_f + overlay_total_mm - reveal_total_mm - gap_mm
          if usable_width_mm <= MIN_DIMENSION_MM
            warn_skip("Skipped double doors for bay #{bay.index + 1} because the gap exceeded the width.")
            return []
          end

          leaf_width_mm = usable_width_mm / 2.0
          if leaf_width_mm <= MIN_DIMENSION_MM
            warn_skip("Skipped double doors for bay #{bay.index + 1} because each leaf would be too narrow.")
            return []
          end

          min_leaf_width_mm = min_double_leaf_width_mm
          allowed = double_allowed?(
            bay_interior_width_mm: bay.width_mm.to_f,
            overlay_mm: overlay_total_mm,
            reveal_mm: reveal_total_mm,
            door_gap_mm: gap_mm,
            min_leaf_width_mm: min_leaf_width_mm,
            leaf_width_mm: leaf_width_mm
          )
          unless allowed
            warn_skip(
              format(
                'Skipped double doors for bay %<index>d because each leaf (%<leaf>.3f mm) falls below the %<min>.3f mm minimum.',
                index: bay.index + 1,
                leaf: leaf_width_mm,
                min: min_leaf_width_mm
              )
            )
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

        left_reveal_mm =
          if params.respond_to?(:door_edge_reveal_mm_for)
            params.door_edge_reveal_mm_for(:left).to_f
          else
            params.door_edge_reveal_mm.to_f
          end
        right_reveal_mm =
          if params.respond_to?(:door_edge_reveal_mm_for)
            params.door_edge_reveal_mm_for(:right).to_f
          else
            params.door_edge_reveal_mm.to_f
          end
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

          min_leaf_width_mm = min_double_leaf_width_mm
          allowed = double_allowed?(
            bay_interior_width_mm: params.width_mm.to_f,
            overlay_mm: 0.0,
            reveal_mm: left_reveal_mm + right_reveal_mm,
            door_gap_mm: center_gap_mm,
            min_leaf_width_mm: min_leaf_width_mm,
            leaf_width_mm: leaf_width_mm
          )
          unless allowed
            warn_skip(
              format(
                'Skipped double doors because each leaf (%<leaf>.3f mm) falls below the %<min>.3f mm minimum.',
                leaf: leaf_width_mm,
                min: min_leaf_width_mm
              )
            )
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

      def bay_vertical_bounds(params:, bays:, bay:, bounds:, total_bays:, front_presence:, orientation:)
        if orientation == :horizontal && bounds.axis == :z
          vertical_bounds_for_horizontal_bay(
            params: params,
            bays: bays,
            bay: bay,
            bounds: bounds,
            total_bays: total_bays,
            front_presence: front_presence,
            orientation: orientation
          )
        else
          door_vertical_bounds(params)
        end
      end
      private_class_method :bay_vertical_bounds

      def vertical_bounds_for_horizontal_bay(params:, bays:, bay:, bounds:, total_bays:, front_presence:, orientation:)
        opening_bottom_mm, opening_top_mm = bay_vertical_opening_bounds(
          params: params,
          bays: bays,
          bounds: bounds,
          total_bays: total_bays,
          orientation: orientation
        )

        bottom_reveal_mm = bay_vertical_edge_reveal_mm(
          params: params,
          bay_index: bay.index,
          total_bays: total_bays,
          side: :bottom,
          front_presence: front_presence,
          orientation: orientation
        )
        top_reveal_mm = bay_vertical_edge_reveal_mm(
          params: params,
          bay_index: bay.index,
          total_bays: total_bays,
          side: :top,
          front_presence: front_presence,
          orientation: orientation
        )

        clear_height_mm = opening_top_mm - opening_bottom_mm - top_reveal_mm - bottom_reveal_mm
        if clear_height_mm <= MIN_DIMENSION_MM
          warn_skip("Skipped doors for bay #{bay.index + 1} because vertical reveals consumed the height.")
          return nil
        end

        {
          clear_height_mm: clear_height_mm,
          bottom_z_mm: opening_bottom_mm + bottom_reveal_mm
        }
      end
      private_class_method :vertical_bounds_for_horizontal_bay

      def bay_vertical_opening_bounds(params:, bays:, bounds:, total_bays:, orientation:)
        return [bounds.interior_bottom_z_mm, bounds.interior_top_z_mm] unless orientation == :horizontal

        bottom_extension_mm = bay_vertical_extension_mm(
          params: params,
          bays: bays,
          bay_index: bounds.bay_index,
          total_bays: total_bays,
          side: :bottom,
          orientation: orientation
        )
        top_extension_mm = bay_vertical_extension_mm(
          params: params,
          bays: bays,
          bay_index: bounds.bay_index,
          total_bays: total_bays,
          side: :top,
          orientation: orientation
        )

        [
          bounds.interior_bottom_z_mm - bottom_extension_mm,
          bounds.interior_top_z_mm + top_extension_mm
        ]
      end
      private_class_method :bay_vertical_opening_bounds

      def bay_vertical_extension_mm(params:, bays:, bay_index:, total_bays:, side:, orientation:)
        return 0.0 unless orientation == :horizontal

        case side
        when :top
          return params.panel_thickness_mm.to_f if bay_index.zero?
          neighbor = bays[bay_index - 1]
          return 0.0 unless neighbor

          extension_from_partition_gap(
            params: params,
            gap_mm: neighbor.start_mm.to_f - bays[bay_index].end_mm.to_f
          )
        when :bottom
          return params.panel_thickness_mm.to_f if bay_index == total_bays - 1
          neighbor = bays[bay_index + 1]
          return 0.0 unless neighbor

          extension_from_partition_gap(
            params: params,
            gap_mm: bays[bay_index].start_mm.to_f - neighbor.end_mm.to_f
          )
        else
          0.0
        end
      end
      private_class_method :bay_vertical_extension_mm

      def extension_from_partition_gap(params:, gap_mm:)
        overlay_mm = interior_partition_half_thickness_mm(params)
        return 0.0 unless overlay_mm.positive?

        usable_gap_mm = [gap_mm, 0.0].max
        return 0.0 if usable_gap_mm <= 0.0

        [overlay_mm, usable_gap_mm / 2.0].min
      end
      private_class_method :extension_from_partition_gap

      def bay_vertical_edge_reveal_mm(params:, bay_index:, total_bays:, side:, front_presence:, orientation:)
        unless orientation == :horizontal
          case side
          when :bottom
            return params.door_bottom_reveal_mm.to_f if bay_index.zero?
          when :top
            return params.door_top_reveal_mm.to_f if bay_index == total_bays - 1
          end
          return 0.0
        end

        bottom_index = total_bays - 1
        top_index = 0
        center_reveal_mm = params.door_center_reveal_mm.to_f

        case side
        when :bottom
          return params.door_bottom_reveal_mm.to_f if bay_index == bottom_index

          neighbor_index = bay_index + 1
          if neighbor_index < total_bays && front_presence[bay_index] && front_presence[neighbor_index]
            return center_reveal_mm / 2.0
          end

          0.0
        when :top
          return params.door_top_reveal_mm.to_f if bay_index == top_index

          neighbor_index = bay_index - 1
          if neighbor_index >= 0 && front_presence[bay_index] && front_presence[neighbor_index]
            return center_reveal_mm / 2.0
          end

          0.0
        else
          0.0
        end
      end
      private_class_method :bay_vertical_edge_reveal_mm

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

      def clear_existing_fronts(parent_entities)
        parent_entities.to_a.each do |entity|
          next unless entity&.valid?
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

          next unless front_entity?(entity)

          entity.erase! if entity.valid?
        end
      end
      private_class_method :clear_existing_fronts

      def front_entity?(entity)
        tagged_as_front?(entity) || front_named?(entity)
      end
      private_class_method :front_entity?

      def partition_orientation(params)
        return unless params.respond_to?(:partition_orientation)

        params.partition_orientation
      end
      private_class_method :partition_orientation

      def tagged_as_front?(entity)
        layer = entity.respond_to?(:layer) ? entity.layer : nil
        layer_name = layer.respond_to?(:name) ? layer.name.to_s : ''
        layer_name == FRONTS_TAG_NAME
      end
      private_class_method :tagged_as_front?

      def front_named?(entity)
        names = []
        names << entity.name.to_s if entity.respond_to?(:name)
        if entity.respond_to?(:definition)
          definition = entity.definition
          names << definition.name.to_s if definition
        end

        names.any? { |value| value.start_with?('Door (') }
      end
      private_class_method :front_named?

      def bay_opening_bounds(params:, bounds:, total_bays:, orientation:)
        left_extension_mm = bay_edge_extension_mm(
          params: params,
          bay_index: bounds.bay_index,
          total_bays: total_bays,
          side: :left,
          orientation: orientation
        )
        right_extension_mm = bay_edge_extension_mm(
          params: params,
          bay_index: bounds.bay_index,
          total_bays: total_bays,
          side: :right,
          orientation: orientation
        )

        [
          bounds.x_start_mm - left_extension_mm,
          bounds.x_end_mm + right_extension_mm
        ]
      end
      private_class_method :bay_opening_bounds

      def bay_edge_extension_mm(params:, bay_index:, total_bays:, side:, orientation:)
        if orientation == :horizontal
          return params.panel_thickness_mm.to_f if side == :left || side == :right

          return 0.0
        end

        case side
        when :left
          return params.panel_thickness_mm.to_f if bay_index.zero?
          return interior_partition_half_thickness_mm(params)
        when :right
          return params.panel_thickness_mm.to_f if bay_index == total_bays - 1
          return interior_partition_half_thickness_mm(params)
        end

        0.0
      end
      private_class_method :bay_edge_extension_mm

      def interior_partition_half_thickness_mm(params)
        thickness = params.partition_thickness_mm.to_f
        thickness = params.panel_thickness_mm.to_f if thickness <= MIN_DIMENSION_MM

        [thickness / 2.0, 0.0].max
      end
      private_class_method :interior_partition_half_thickness_mm

      def bay_edge_reveal_mm(params:, bay_index:, total_bays:, side:, front_presence:, orientation:)
        edge_reveal = params.door_edge_reveal_mm.to_f
        if total_bays <= 1
          return params.door_edge_reveal_mm_for(side).to_f if params.respond_to?(:door_edge_reveal_mm_for)

          return edge_reveal
        end
        return edge_reveal if orientation == :horizontal

        case side
        when :left
          if bay_index.zero?
            return params.door_edge_reveal_mm_for(:left).to_f if params.respond_to?(:door_edge_reveal_mm_for)
            return edge_reveal
          end

          neighbor_index = bay_index - 1
          return edge_reveal unless front_presence[bay_index] && front_presence[neighbor_index]
        when :right
          if bay_index == total_bays - 1
            return params.door_edge_reveal_mm_for(:right).to_f if params.respond_to?(:door_edge_reveal_mm_for)
            return edge_reveal
          end

          neighbor_index = bay_index + 1
          return edge_reveal unless front_presence[bay_index] && front_presence[neighbor_index]
        else
          return edge_reveal
        end

        params.door_center_reveal_mm.to_f / 2.0
      end
      private_class_method :bay_edge_reveal_mm

      def warn_skip(message)
        warn("AI Cabinets: #{message}")
      end
      private_class_method :warn_skip
    end
  end
end
