# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/generator/parts/side_panel')
Sketchup.require('aicabinets/generator/parts/bottom_panel')
Sketchup.require('aicabinets/generator/parts/top_panel')
Sketchup.require('aicabinets/generator/parts/back_panel')
Sketchup.require('aicabinets/ops/units')
Sketchup.require('aicabinets/ops/tags')
Sketchup.require('aicabinets/ops/materials')

module AICabinets
  module Generator
    module_function

    # Builds a base cabinet carcass into the given parent container using mm
    # parameters. The parent origin is treated as the carcass front-left-bottom
    # (FLB) corner and all geometry is created in the positive octant.
    #
    # @param parent [Sketchup::Entities, Sketchup::ComponentDefinition]
    # @param params_mm [Hash{Symbol=>Numeric}] lengths specified in millimeters
    # @return [Hash] structured result containing the created containers and
    #   bounding information
    def build_base_carcass!(parent:, params_mm:)
      Carcass.build_base_carcass!(parent: parent, params_mm: params_mm)
    end

    module Carcass
      module_function

      def build_base_carcass!(parent:, params_mm:)
        Builder.new(parent: parent, params_mm: params_mm).build
      end

      class Builder
        REQUIRED_PARAMS = %i[
          width_mm
          depth_mm
          height_mm
          panel_thickness_mm
          toe_kick_height_mm
          toe_kick_depth_mm
        ].freeze

        OPTIONAL_PARAMS = {
          back_thickness_mm: nil,
          top_thickness_mm: nil,
          bottom_thickness_mm: nil
        }.freeze

        Result = Struct.new(:instances, :bounds, :dimensions_mm, keyword_init: true)

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
          instances = {}
          created = []

          instances[:left_side] = Parts::SidePanel.build(
            parent_entities: entities,
            name: 'Left Side',
            panel_thickness: params.panel_thickness,
            height: params.height,
            depth: params.depth,
            toe_kick_height: params.toe_kick_height,
            toe_kick_depth: params.toe_kick_depth,
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
            toe_kick_height: params.toe_kick_height,
            toe_kick_depth: params.toe_kick_depth,
            x_offset: params.width - params.panel_thickness
          )
          register_created(created, instances[:right_side])
          apply_category(instances[:right_side], 'AICabinets/Sides', default_material)

          bottom_width = params.width - params.panel_thickness * 2
          bottom_depth = params.depth - params.toe_kick_depth
          instances[:bottom] = Parts::BottomPanel.build(
            parent_entities: entities,
            name: 'Bottom',
            width: bottom_width,
            depth: bottom_depth,
            thickness: params.bottom_thickness,
            x_offset: params.panel_thickness,
            y_offset: params.toe_kick_depth,
            z_offset: params.toe_kick_height
          )
          register_created(created, instances[:bottom])
          apply_category(instances[:bottom], 'AICabinets/Bottom', default_material)

          top_width = params.width - params.panel_thickness * 2
          instances[:top_or_stretchers] = Parts::TopPanel.build(
            parent_entities: entities,
            name: 'Top',
            width: top_width,
            depth: params.depth,
            thickness: params.top_thickness,
            x_offset: params.panel_thickness,
            y_offset: 0,
            z_offset: params.height - params.top_thickness
          )
          register_created(created, instances[:top_or_stretchers])
          apply_category(
            instances[:top_or_stretchers],
            determine_top_tag(instances[:top_or_stretchers]),
            default_material
          )

          instances[:back] = Parts::BackPanel.build(
            parent_entities: entities,
            name: 'Back',
            width: params.width,
            height: params.height - params.toe_kick_height,
            thickness: params.back_thickness,
            x_offset: 0,
            y_offset: params.depth - params.back_thickness,
            z_offset: params.toe_kick_height
          )
          register_created(created, instances[:back])
          apply_category(instances[:back], 'AICabinets/Back', default_material)

          bounds = Geom::BoundingBox.new
          instances.each_value do |container|
            next unless container&.valid?

            bounds.add(container.bounds)
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
          created.reverse_each do |container|
            next unless container&.valid?

            container.erase!
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
          missing = REQUIRED_PARAMS.reject { |key| @raw_params.key?(key) }
          raise ArgumentError, "Missing parameters: #{missing.join(', ')}" if missing.any?

          REQUIRED_PARAMS.each do |key|
            ensure_numeric!(key, @raw_params[key])
          end

          %i[width_mm depth_mm height_mm panel_thickness_mm].each do |key|
            ensure_positive!(key, @raw_params[key])
          end

          %i[toe_kick_height_mm toe_kick_depth_mm].each do |key|
            ensure_non_negative!(key, @raw_params[key])
          end

          OPTIONAL_PARAMS.each_key do |key|
            next unless @raw_params.key?(key)

            ensure_numeric!(key, @raw_params[key])
            ensure_positive!(key, @raw_params[key])
          end

          width = @raw_params[:width_mm].to_f
          depth = @raw_params[:depth_mm].to_f
          height = @raw_params[:height_mm].to_f
          panel = @raw_params[:panel_thickness_mm].to_f
          toe_height = @raw_params[:toe_kick_height_mm].to_f
          toe_depth = @raw_params[:toe_kick_depth_mm].to_f
          top = (@raw_params[:top_thickness_mm] || panel).to_f
          bottom = (@raw_params[:bottom_thickness_mm] || panel).to_f
          back = (@raw_params[:back_thickness_mm] || panel).to_f

          raise ArgumentError, 'panel_thickness_mm must be less than half of width_mm' if panel * 2 >= width
          raise ArgumentError, 'panel_thickness_mm must be less than depth_mm' if panel >= depth
          raise ArgumentError, 'panel_thickness_mm must be less than height_mm' if panel >= height
          raise ArgumentError, 'toe_kick_height_mm must be between 0 and height_mm (exclusive)' unless toe_height >= 0 && toe_height < height
          raise ArgumentError, 'toe_kick_depth_mm must be between 0 and depth_mm (exclusive)' unless toe_depth >= 0 && toe_depth < depth
          raise ArgumentError, 'top_thickness_mm must be positive and <= height_mm' unless top.positive? && top < height
          raise ArgumentError, 'bottom_thickness_mm must be positive and <= (height_mm - toe_kick_height_mm)' unless bottom.positive? && bottom < (height - toe_height)
          raise ArgumentError, 'back_thickness_mm must be positive and <= depth_mm' unless back.positive? && back < depth
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
          return if value.to_f >= 0

          raise ArgumentError, "Parameter #{key} must be zero or greater"
        end

        def freeze_dimensions!
          defaults = OPTIONAL_PARAMS.transform_values { |_| nil }
          merged = defaults.merge(@raw_params)

          @params = ParameterSet.new(merged)
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

        def determine_top_tag(container)
          entities = Array(container).compact
          return 'AICabinets/Top' if entities.empty?

          return 'AICabinets/Stretchers' if entities.length > 1

          name = entities.first.respond_to?(:name) ? entities.first.name.to_s : ''
          return 'AICabinets/Stretchers' if name.downcase.include?('stretcher')

          'AICabinets/Top'
        end
      end

      class ParameterSet
        attr_reader :width, :depth, :height, :panel_thickness, :toe_kick_height,
                    :toe_kick_depth, :back_thickness, :top_thickness,
                    :bottom_thickness, :width_mm, :depth_mm, :height_mm

        def initialize(params_mm)
          @width_mm = params_mm[:width_mm].to_f
          @depth_mm = params_mm[:depth_mm].to_f
          @height_mm = params_mm[:height_mm].to_f
          @panel_thickness_mm = params_mm[:panel_thickness_mm].to_f
          @toe_kick_height_mm = params_mm[:toe_kick_height_mm].to_f
          @toe_kick_depth_mm = params_mm[:toe_kick_depth_mm].to_f
          @back_thickness_mm = (params_mm[:back_thickness_mm] || @panel_thickness_mm).to_f
          @top_thickness_mm = (params_mm[:top_thickness_mm] || @panel_thickness_mm).to_f
          @bottom_thickness_mm = (params_mm[:bottom_thickness_mm] || @panel_thickness_mm).to_f

          @width = length_mm(@width_mm)
          @depth = length_mm(@depth_mm)
          @height = length_mm(@height_mm)
          @panel_thickness = length_mm(@panel_thickness_mm)
          @toe_kick_height = length_mm(@toe_kick_height_mm)
          @toe_kick_depth = length_mm(@toe_kick_depth_mm)
          @back_thickness = length_mm(@back_thickness_mm)
          @top_thickness = length_mm(@top_thickness_mm)
          @bottom_thickness = length_mm(@bottom_thickness_mm)
        end

        private

        def length_mm(value)
          Ops::Units.to_length_mm(value)
        end
      end
    end
  end
end
