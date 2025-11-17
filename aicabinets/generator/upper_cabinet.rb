# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/generator/parts/side_panel')
Sketchup.require('aicabinets/generator/parts/bottom_panel')
Sketchup.require('aicabinets/generator/parts/top_panel')
Sketchup.require('aicabinets/generator/parts/back_panel')
Sketchup.require('aicabinets/generator/fronts')
Sketchup.require('aicabinets/generator/shelves')
Sketchup.require('aicabinets/ops/materials')
Sketchup.require('aicabinets/ops/tags')
Sketchup.require('aicabinets/ops/units')

module AICabinets
  module Generator
    module UpperCabinet
      module_function

      Result = Struct.new(:instances, :bounds, :dimensions_mm, keyword_init: true)

      def build!(parent:, params_mm:)
        Builder.new(parent: parent, params_mm: params_mm).build
      end

      class Builder
        REQUIRED_KEYS = %i[width_mm depth_mm height_mm panel_thickness_mm].freeze

        def initialize(parent:, params_mm:)
          @parent = parent
          @raw_params = normalize_keys(params_mm)
          validate_parent!
          validate_params!
          freeze_dimensions!
        end

        def build
          entities = resolve_entities(@parent)
          model = entities.respond_to?(:model) ? entities.model : nil
          default_material = model.is_a?(Sketchup::Model) ? Ops::Materials.default_carcass(model) : nil
          front_material = model.is_a?(Sketchup::Model) ? Ops::Materials.default_door(model) : nil

          instances = {}
          created = []

          instances[:left_side] = Parts::SidePanel.build(
            parent_entities: entities,
            name: 'Left Side',
            panel_thickness: params.panel_thickness,
            height: params.height,
            depth: params.depth,
            toe_kick_height: params.zero_length,
            toe_kick_depth: params.zero_length,
            toe_kick_thickness: params.zero_length,
            x_offset: 0
          )
          register_created(created, instances[:left_side])
          apply_category(instances[:left_side], 'AICabinets/Sides', default_material)

          instances[:right_side] = Parts::SidePanel.build(
            parent_entities: entities,
            name: 'Right Side',
            panel_thickness: params.panel_thickness,
            height: params.height,
            depth: params.depth,
            toe_kick_height: params.zero_length,
            toe_kick_depth: params.zero_length,
            toe_kick_thickness: params.zero_length,
            x_offset: params.width - params.panel_thickness
          )
          register_created(created, instances[:right_side])
          apply_category(instances[:right_side], 'AICabinets/Sides', default_material)

          bottom_depth = params.depth_without_back
          bottom_width = params.width - (params.panel_thickness * 2)
          instances[:bottom] = Parts::BottomPanel.build(
            parent_entities: entities,
            name: 'Bottom',
            width: bottom_width,
            depth: bottom_depth,
            thickness: params.bottom_thickness,
            x_offset: params.panel_thickness,
            y_offset: params.zero_length,
            z_offset: params.zero_length
          )
          register_created(created, instances[:bottom])
          apply_category(instances[:bottom], 'AICabinets/Bottom', default_material)

          instances[:top] = Parts::TopPanel.build(
            parent_entities: entities,
            name: 'Top',
            width: bottom_width,
            depth: bottom_depth,
            thickness: params.top_thickness,
            x_offset: params.panel_thickness,
            y_offset: params.zero_length,
            z_offset: params.height - params.top_thickness
          )
          register_created(created, instances[:top])
          apply_category(instances[:top], 'AICabinets/Top', default_material)

          if params.has_back
            instances[:back] = Parts::BackPanel.build(
              parent_entities: entities,
              name: 'Back',
              width: bottom_width,
              height: params.height,
              thickness: params.back_thickness,
              x_offset: params.panel_thickness,
              y_offset: params.depth - params.back_thickness,
              z_offset: params.zero_length
            )
            register_created(created, instances[:back])
            apply_category(instances[:back], 'AICabinets/Back', default_material)
          end

          shelves = build_shelves(entities, default_material)
          unless shelves.empty?
            instances[:shelves] = shelves
            register_created(created, shelves)
            apply_category(shelves, 'AICabinets/Shelves', default_material)
          end

          fronts = build_fronts(entities)
          unless fronts.empty?
            shift_fronts_forward(fronts)
            instances[:fronts] = fronts
            register_created(created, fronts)
            apply_category(fronts, 'AICabinets/Fronts', front_material)
          end

          bounds = Geom::BoundingBox.new
          instances.each_value do |container|
            Array(container).each do |entity|
              next unless entity&.valid?

              bounds.add(entity.bounds)
            end
          end

          Result.new(
            instances: instances,
            bounds: bounds,
            dimensions_mm: {
              width_mm: params.width_mm,
              depth_mm: params.depth_mm,
              height_mm: params.height_mm
            }
          )
        rescue StandardError
          created.reverse_each do |entity|
            next unless entity&.valid?

            entity.erase!
          end
          raise
        end

        private

        attr_reader :params

        def resolve_entities(parent)
          case parent
          when Sketchup::Entities
            parent
          when Sketchup::ComponentDefinition
            parent.entities
          else
            raise ArgumentError, 'parent must be Sketchup::Entities or Sketchup::ComponentDefinition'
          end
        end

        def validate_parent!
          return if @parent.is_a?(Sketchup::Entities) || @parent.is_a?(Sketchup::ComponentDefinition)

          raise ArgumentError, 'parent must be Sketchup::Entities or Sketchup::ComponentDefinition'
        end

        def validate_params!
          missing = REQUIRED_KEYS.reject { |key| @raw_params.key?(key) }
          raise ArgumentError, "Missing parameters: #{missing.join(', ')}" if missing.any?

          REQUIRED_KEYS.each do |key|
            ensure_numeric!(key, @raw_params[key])
            ensure_positive!(key, @raw_params[key])
          end

          back_thickness_mm = @raw_params[:back_thickness_mm] || @raw_params[:panel_thickness_mm]
          top_thickness_mm = @raw_params[:top_thickness_mm] || @raw_params[:panel_thickness_mm]
          bottom_thickness_mm = @raw_params[:bottom_thickness_mm] || @raw_params[:panel_thickness_mm]
          overlay_mm = @raw_params[:overlay_mm] || 0.0

          ensure_positive!(:back_thickness_mm, back_thickness_mm)
          ensure_positive!(:top_thickness_mm, top_thickness_mm)
          ensure_positive!(:bottom_thickness_mm, bottom_thickness_mm)
          ensure_non_negative!(:overlay_mm, overlay_mm)

          upper_block = @raw_params[:upper] || @raw_params['upper'] || {}
          ensure_non_negative!(:num_shelves, upper_block[:num_shelves] || upper_block['num_shelves'] || 0)
        end

        def ensure_numeric!(key, value)
          return if value.is_a?(Numeric)

          raise ArgumentError, "Parameter #{key} must be numeric"
        end

        def ensure_positive!(key, value)
          return if value.to_f.positive?

          raise ArgumentError, "Parameter #{key} must be greater than zero"
        end

        def ensure_non_negative!(key, value)
          return if value.to_f >= 0.0

          raise ArgumentError, "Parameter #{key} must be zero or greater"
        end

        def freeze_dimensions!
          @params = ParameterSet.new(@raw_params)
        end

        def normalize_keys(hash)
          unless hash.respond_to?(:each)
            raise ArgumentError, 'params_mm must be a hash of numeric values'
          end

          hash.each_with_object({}) do |(key, value), acc|
            acc[key.to_sym] = value
          end
        end

        def register_created(created, container)
          Array(container).each do |entity|
            next unless entity&.valid?

            created << entity
          end
        end

        def apply_category(container, tag_name, material)
          Array(container).each do |entity|
            next unless entity&.valid?

            Ops::Tags.assign!(entity, tag_name)
            next unless material && entity.respond_to?(:material=)

            entity.material = material
          end
        end

        def build_shelves(entities, material)
          count = params.num_shelves
          return [] unless count.positive?

          placements = plan_shelves(count)
          return [] if placements.empty?

          placements.each_with_object([]) do |placement, memo|
            shelf = Shelves.send(:build_single_shelf, entities, placement)
            next unless shelf&.valid?

            shelf.material = material if material && shelf.respond_to?(:material=)
            memo << shelf
          end
        end

        def plan_shelves(count)
          thickness_mm = params.shelf_thickness_mm
          interior_height_mm = params.interior_height_mm
          gap_mm = Shelves.send(:resolve_gap, interior_height_mm, thickness_mm, count)
          return [] unless gap_mm

          depth_mm = params.interior_depth_mm - Shelves::FRONT_SETBACK_MM - Shelves::REAR_CLEARANCE_MM
          return [] if depth_mm <= Shelves::MIN_DEPTH_MM

          width_mm = params.interior_width_mm
          return [] if width_mm <= Shelves::MIN_BAY_WIDTH_MM

          placements = []
          current_bottom_mm = params.bottom_thickness_mm + gap_mm
          count.times do
            top_z_mm = current_bottom_mm + thickness_mm
            placements << Shelves::Placement.new(
              name: 'Shelf',
              bay_index: 0,
              width_mm: width_mm,
              depth_mm: depth_mm,
              top_z_mm: top_z_mm,
              x_start_mm: params.panel_thickness_mm,
              thickness_mm: thickness_mm,
              front_offset_mm: Shelves::FRONT_SETBACK_MM
            )
            current_bottom_mm += thickness_mm + gap_mm
          end

          placements
        end

        def build_fronts(entities)
          placements_params = FrontParams.new(params)
          Fronts.build(parent_entities: entities, params: placements_params)
        end

        def shift_fronts_forward(fronts)
          Array(fronts).each do |front|
            next unless front&.valid?

            translation = Geom::Transformation.translation([0, params.door_thickness, 0])
            front.transform!(translation)
          end
        end
      end

      class ParameterSet
        attr_reader :width_mm, :depth_mm, :height_mm, :panel_thickness_mm,
                    :back_thickness_mm, :top_thickness_mm, :bottom_thickness_mm,
                    :overlay_mm, :door_thickness_mm, :num_shelves, :has_back,
                    :door_edge_reveal_mm, :door_top_reveal_mm, :door_bottom_reveal_mm,
                    :door_center_reveal_mm

        def initialize(params_mm)
          @width_mm = params_mm[:width_mm].to_f
          @depth_mm = params_mm[:depth_mm].to_f
          @height_mm = params_mm[:height_mm].to_f
          @panel_thickness_mm = params_mm[:panel_thickness_mm].to_f
          @back_thickness_mm = (params_mm[:back_thickness_mm] || @panel_thickness_mm).to_f
          @top_thickness_mm = (params_mm[:top_thickness_mm] || @panel_thickness_mm).to_f
          @bottom_thickness_mm = (params_mm[:bottom_thickness_mm] || @panel_thickness_mm).to_f
          @overlay_mm = (params_mm[:overlay_mm] || 0.0).to_f
          @door_thickness_mm = (params_mm[:door_thickness_mm] || Fronts::DOOR_THICKNESS_MM).to_f

          style = params_mm[:upper] || params_mm['upper'] || {}
          @num_shelves = coerce_count(style[:num_shelves] || style['num_shelves'])
          @has_back = style.key?(:has_back) ? !!style[:has_back] : !!style['has_back']
          @has_back = true if style.empty?

          @door_edge_reveal_mm = coerce_non_negative(params_mm[:door_reveal_mm] || params_mm[:door_reveal]) || Fronts::REVEAL_EDGE_MM
          @door_top_reveal_mm = coerce_non_negative(params_mm[:top_reveal_mm] || params_mm[:top_reveal]) || Fronts::REVEAL_TOP_MM
          @door_bottom_reveal_mm = coerce_non_negative(params_mm[:bottom_reveal_mm] || params_mm[:bottom_reveal]) || Fronts::REVEAL_BOTTOM_MM
          @door_center_reveal_mm = coerce_non_negative(params_mm[:door_gap_mm] || params_mm[:door_gap]) || Fronts::REVEAL_CENTER_MM
        end

        def width
          length_mm(@width_mm)
        end

        def depth
          length_mm(@depth_mm)
        end

        def height
          length_mm(@height_mm)
        end

        def panel_thickness
          length_mm(@panel_thickness_mm)
        end

        def back_thickness
          length_mm(@back_thickness_mm)
        end

        def top_thickness
          length_mm(@top_thickness_mm)
        end

        def bottom_thickness
          length_mm(@bottom_thickness_mm)
        end

        def door_thickness
          length_mm(@door_thickness_mm)
        end

        def zero_length
          length_mm(0.0)
        end

        def depth_without_back
          has_back ? length_mm(@depth_mm - @back_thickness_mm) : depth
        end

        def interior_width_mm
          [@width_mm - (panel_thickness_mm * 2.0), 0.0].max
        end

        def interior_depth_mm
          [@depth_mm - (has_back ? @back_thickness_mm : 0.0), 0.0].max
        end

        def interior_height_mm
          [@height_mm - @top_thickness_mm - @bottom_thickness_mm, 0.0].max
        end

        def shelf_thickness_mm
          @panel_thickness_mm
        end

        def door_edge_reveal
          length_mm(@door_edge_reveal_mm)
        end

        def door_edge_reveal_mm_for(side)
          @door_edge_reveal_mm if %i[left right].include?(side)
        end

        def door_top_reveal
          length_mm(@door_top_reveal_mm)
        end

        def door_bottom_reveal
          length_mm(@door_bottom_reveal_mm)
        end

        def door_center_reveal
          length_mm(@door_center_reveal_mm)
        end

        def front_mode
          threshold_mm = Fronts.min_double_leaf_width_mm * 4.0
          if double_allowed? && @width_mm >= threshold_mm
            :doors_double
          else
            :doors_left
          end
        end

        def toe_kick_height_mm
          0.0
        end

        def toe_kick_depth_mm
          0.0
        end

        private

        def double_allowed?
          reveal_total_mm = @door_edge_reveal_mm * 2.0
          Fronts.double_allowed?(
            bay_interior_width_mm: @width_mm,
            overlay_mm: @overlay_mm,
            reveal_mm: reveal_total_mm,
            door_gap_mm: @door_center_reveal_mm
          )
        end

        def coerce_count(value)
          return 0 if value.nil?

          Integer(value)
        rescue ArgumentError, TypeError
          0
        end

        def coerce_non_negative(value)
          return nil if value.nil?

          numeric = Float(value)
          numeric >= 0 ? numeric : nil
        rescue ArgumentError, TypeError
          nil
        end

        def length_mm(value)
          Ops::Units.to_length_mm(value)
        end
      end

      class FrontParams
        def initialize(params)
          @params = params
        end

        def method_missing(name, *args, &block)
          if @params.respond_to?(name)
            @params.public_send(name, *args, &block)
          else
            super
          end
        end

        def respond_to_missing?(name, include_private = false)
          @params.respond_to?(name, include_private) || super
        end

        # Front layout helpers expect callers to optionally provide partition
        # bay metadata. Upper cabinets do not partition bays, so expose an
        # empty collection to keep front planning code paths consistent with
        # base cabinets without triggering method_missing.
        def partition_bays
          []
        end
      end
    end
  end
end
