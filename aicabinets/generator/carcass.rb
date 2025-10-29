# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/generator/parts/side_panel')
Sketchup.require('aicabinets/generator/parts/bottom_panel')
Sketchup.require('aicabinets/generator/parts/top_panel')
Sketchup.require('aicabinets/generator/parts/back_panel')
Sketchup.require('aicabinets/generator/parts/toe_kick_front')
Sketchup.require('aicabinets/generator/shelves')
Sketchup.require('aicabinets/generator/fronts')
Sketchup.require('aicabinets/generator/partitions')
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
          front_material = model.is_a?(Sketchup::Model) ? Ops::Materials.default_door(model) : nil
          instances = {}
          created = []
          effective_toe_kick_thickness_mm =
            if params.toe_kick_thickness_mm && params.toe_kick_depth_mm
              [params.toe_kick_thickness_mm, params.toe_kick_depth_mm].min
            else
              0.0
            end
          effective_toe_kick_thickness = Ops::Units.to_length_mm(effective_toe_kick_thickness_mm)

          instances[:left_side] = Parts::SidePanel.build(
            parent_entities: entities,
            name: 'Left Side',
            panel_thickness: params.panel_thickness,
            height: params.height,
            depth: params.depth,
            toe_kick_height: params.toe_kick_height,
            toe_kick_depth: params.toe_kick_depth,
            toe_kick_thickness: effective_toe_kick_thickness,
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
            toe_kick_thickness: effective_toe_kick_thickness,
            x_offset: params.width - params.panel_thickness
          )
          register_created(created, instances[:right_side])
          apply_category(instances[:right_side], 'AICabinets/Sides', default_material)

          bottom_width = params.width - (params.panel_thickness * 2)
          toe_kick_enabled =
            params.toe_kick_height_mm.positive? && params.toe_kick_depth_mm.positive?
          bottom_depth = toe_kick_enabled ? params.depth : params.depth - params.toe_kick_depth
          bottom_y_offset =
            if toe_kick_enabled
              Ops::Units.to_length_mm(0.0)
            else
              params.toe_kick_depth
            end
          instances[:bottom] = Parts::BottomPanel.build(
            parent_entities: entities,
            name: 'Bottom',
            width: bottom_width,
            depth: bottom_depth,
            thickness: params.bottom_thickness,
            x_offset: params.panel_thickness,
            y_offset: bottom_y_offset,
            z_offset: params.toe_kick_height
          )
          register_created(created, instances[:bottom])
          apply_category(instances[:bottom], 'AICabinets/Bottom', default_material)

          top_width = params.width - (params.panel_thickness * 2)
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

          toe_kick_front = build_toe_kick_front(entities, effective_toe_kick_thickness_mm)
          if toe_kick_front
            instances[:toe_kick_front] = toe_kick_front
            register_created(created, toe_kick_front)
            apply_category(toe_kick_front, 'AICabinets/ToeKick', default_material)
          end

          partitions = Partitions.build(
            parent_entities: entities,
            params: params,
            material: default_material
          )
          unless partitions.empty?
            instances[:partitions] = partitions
            register_created(created, partitions)
            apply_category(partitions, 'AICabinets/Partitions', default_material)
          end

          shelves = Shelves.build(
            parent_entities: entities,
            params: params,
            material: default_material
          )
          unless shelves.empty?
            instances[:shelves] = shelves
            register_created(created, shelves)
            apply_category(shelves, 'AICabinets/Shelves', default_material)
          end

          fronts = Fronts.build(
            parent_entities: entities,
            params: params
          )
          unless fronts.empty?
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

          if @raw_params.key?(:toe_kick_thickness_mm)
            ensure_numeric!(:toe_kick_thickness_mm, @raw_params[:toe_kick_thickness_mm])
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

        def build_toe_kick_front(entities, effective_thickness_mm)
          return unless params.toe_kick_height_mm.positive?
          return unless params.toe_kick_depth_mm.positive?
          return unless params.toe_kick_thickness_mm.positive?
          return unless effective_thickness_mm.positive?

          width_mm = params.width_mm
          return unless width_mm.positive?

          thickness_length = Ops::Units.to_length_mm(effective_thickness_mm)

          front_plane_mm = params.toe_kick_depth_mm
          rear_plane_mm = front_plane_mm + effective_thickness_mm

          Parts::ToeKickFront.build(
            parent_entities: entities,
            name: 'ToeKick/Front',
            width: Ops::Units.to_length_mm(width_mm),
            height: params.toe_kick_height,
            thickness: thickness_length,
            x_offset: Ops::Units.to_length_mm(0.0),
            y_offset: Ops::Units.to_length_mm(rear_plane_mm),
            z_offset: Ops::Units.to_length_mm(0.0)
          )
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
                    :toe_kick_depth, :toe_kick_thickness, :back_thickness, :top_thickness,
                    :bottom_thickness, :width_mm, :depth_mm, :height_mm,
                    :panel_thickness_mm, :toe_kick_height_mm,
                    :toe_kick_depth_mm, :toe_kick_thickness_mm,
                    :back_thickness_mm, :top_thickness_mm,
                    :bottom_thickness_mm, :shelf_count, :shelf_thickness,
                    :shelf_thickness_mm, :interior_depth, :interior_depth_mm,
                    :interior_bottom_z_mm, :interior_top_z_mm,
                    :interior_clear_height_mm, :partition_left_faces_mm,
                    :partition_thickness_mm, :front_mode, :door_thickness,
                    :door_thickness_mm, :door_edge_reveal_mm,
                    :door_top_reveal_mm, :door_bottom_reveal_mm,
                    :door_center_reveal_mm, :door_edge_reveal,
                    :door_top_reveal, :door_bottom_reveal,
                    :door_center_reveal

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

          thickness_provided = params_mm.key?(:toe_kick_thickness_mm)
          raw_thickness = params_mm[:toe_kick_thickness_mm]
          numeric_thickness = coerce_non_negative_numeric(raw_thickness)

          @toe_kick_thickness_mm =
            if thickness_provided
              if raw_thickness.nil?
                self.class.__send__(:warn_missing_toe_kick_thickness_once)
                @panel_thickness_mm
              elsif numeric_thickness.nil?
                self.class.__send__(:warn_invalid_toe_kick_thickness_once)
                0.0
              else
                numeric_thickness
              end
            else
              self.class.__send__(:warn_missing_toe_kick_thickness_once)
              @panel_thickness_mm
            end

          @shelf_count = coerce_shelf_count(params_mm[:shelves])
          thickness_override = coerce_positive_numeric(params_mm[:shelf_thickness_mm])
          @shelf_thickness_mm = (thickness_override || @panel_thickness_mm).to_f

          @width = length_mm(@width_mm)
          @depth = length_mm(@depth_mm)
          @height = length_mm(@height_mm)
          @panel_thickness = length_mm(@panel_thickness_mm)
          @toe_kick_height = length_mm(@toe_kick_height_mm)
          @toe_kick_depth = length_mm(@toe_kick_depth_mm)
          @toe_kick_thickness = length_mm(@toe_kick_thickness_mm)
          @back_thickness = length_mm(@back_thickness_mm)
          @top_thickness = length_mm(@top_thickness_mm)
          @bottom_thickness = length_mm(@bottom_thickness_mm)
          @shelf_thickness = length_mm(@shelf_thickness_mm)

          @interior_depth_mm = @depth_mm - @back_thickness_mm
          @interior_depth = length_mm(@interior_depth_mm)
          @interior_bottom_z_mm = @toe_kick_height_mm + @bottom_thickness_mm
          @interior_top_z_mm = @height_mm - @top_thickness_mm
          @interior_clear_height_mm =
            [@interior_top_z_mm - @interior_bottom_z_mm, 0.0].max

          @front_mode = normalize_front(params_mm[:front])

          thickness_override = coerce_positive_numeric(params_mm[:door_thickness_mm])
          @door_thickness_mm =
            (thickness_override || Fronts::DOOR_THICKNESS_MM).to_f
          @door_thickness = length_mm(@door_thickness_mm)

          edge_reveal_override =
            coerce_non_negative_numeric(params_mm[:door_reveal_mm] || params_mm[:door_reveal])
          top_reveal_override =
            coerce_non_negative_numeric(params_mm[:top_reveal_mm] || params_mm[:top_reveal])
          bottom_reveal_override =
            coerce_non_negative_numeric(params_mm[:bottom_reveal_mm] || params_mm[:bottom_reveal])
          center_reveal_override =
            coerce_non_negative_numeric(params_mm[:door_gap_mm] || params_mm[:door_gap])

          @door_edge_reveal_mm =
            (edge_reveal_override || Fronts::REVEAL_EDGE_MM).to_f
          @door_top_reveal_mm =
            (top_reveal_override || Fronts::REVEAL_TOP_MM).to_f
          @door_bottom_reveal_mm =
            (bottom_reveal_override || Fronts::REVEAL_BOTTOM_MM).to_f
          @door_center_reveal_mm =
            (center_reveal_override || Fronts::REVEAL_CENTER_MM).to_f

          @door_edge_reveal = length_mm(@door_edge_reveal_mm)
          @door_top_reveal = length_mm(@door_top_reveal_mm)
          @door_bottom_reveal = length_mm(@door_bottom_reveal_mm)
          @door_center_reveal = length_mm(@door_center_reveal_mm)

          layout = compute_partition_layout(params_mm[:partitions])
          @partition_left_faces_mm = layout.partition_left_faces_mm
          @partition_thickness_mm = layout.partition_thickness_mm
          layout.warnings.each do |message|
            warn("AI Cabinets: #{message}")
          end
          @partition_bay_ranges_mm = layout.bay_ranges_mm
          if @partition_bay_ranges_mm.empty?
            left = interior_left_face_mm
            right = interior_right_face_mm
            if right - left >= Shelves::MIN_BAY_WIDTH_MM
              @partition_bay_ranges_mm = [[left, right]]
            end
          end
        end

        class << self
          def warn_missing_toe_kick_thickness_once
            return if @warned_missing_toe_kick_thickness

            warn('AI Cabinets: toe_kick_thickness_mm missing; defaulting to panel thickness.')
            @warned_missing_toe_kick_thickness = true
          end

          def warn_invalid_toe_kick_thickness_once
            return if @warned_invalid_toe_kick_thickness

            warn('AI Cabinets: toe_kick_thickness_mm invalid; treating as 0 mm.')
            @warned_invalid_toe_kick_thickness = true
          end
        end
        private_class_method :warn_missing_toe_kick_thickness_once, :warn_invalid_toe_kick_thickness_once

        def partition_bay_ranges_mm
          @partition_bay_ranges_mm.dup
        end

        def partition_bay_ranges
          @partition_bay_ranges ||= @partition_bay_ranges_mm.map do |start_mm, end_mm|
            [length_mm(start_mm), length_mm(end_mm)]
          end
        end

        def partition_left_faces
          @partition_left_faces ||= partition_left_faces_mm.map { |value| length_mm(value) }
        end

        def partition_thickness
          @partition_thickness ||= length_mm(@partition_thickness_mm)
        end

        private

        def length_mm(value)
          Ops::Units.to_length_mm(value)
        end

        def coerce_shelf_count(value)
          return 0 if value.nil?

          numeric =
            if value.is_a?(Numeric)
              value.to_f
            else
              Float(value)
            end
          integer = numeric.round
          return 0 if integer.negative?

          integer
        rescue ArgumentError, TypeError
          0
        end

        def coerce_positive_numeric(value)
          return nil if value.nil?

          numeric =
            if value.is_a?(Numeric)
              value.to_f
            else
              Float(value)
            end
          return nil unless numeric.positive?

          numeric
        rescue ArgumentError, TypeError
          nil
        end

        def coerce_non_negative_numeric(value)
          return nil if value.nil?

          numeric =
            if value.is_a?(Numeric)
              value.to_f
            else
              Float(value)
            end
          return nil unless numeric >= 0.0

          numeric
        rescue ArgumentError, TypeError
          nil
        end

        def normalize_front(value)
          candidate =
            case value
            when Symbol
              value
            when String
              value.strip.downcase.to_sym
            else
              nil
            end

          return candidate if Fronts::FRONT_MODES.include?(candidate)

          :empty
        rescue StandardError
          :empty
        end

        def compute_partition_layout(raw)
          PartitionLayout.new(
            raw: raw,
            panel_thickness_mm: @panel_thickness_mm,
            width_mm: @width_mm,
            min_bay_width_mm: Shelves::MIN_BAY_WIDTH_MM
          )
        end

        def interior_left_face_mm
          @panel_thickness_mm
        end

        def interior_right_face_mm
          @width_mm - @panel_thickness_mm
        end

        class PartitionLayout
          EPSILON_MM = 1.0e-3

          def initialize(raw:, panel_thickness_mm:, width_mm:, min_bay_width_mm:)
            @raw = raw
            @panel_thickness_mm = panel_thickness_mm
            @width_mm = width_mm
            @min_bay_width_mm = min_bay_width_mm
            @warnings = []
            @computed = false
          end

          def bay_ranges_mm
            ensure_computed
            @bay_ranges_mm
          end

          def partition_left_faces_mm
            ensure_computed
            @partition_left_faces_mm
          end

          def partition_thickness_mm
            return @partition_thickness_mm if defined?(@partition_thickness_mm)

            candidate = safe_float(fetch(raw, :panel_thickness_mm))
            candidate = nil unless candidate && candidate.positive?

            interior_width = interior_width_mm
            if candidate && candidate >= interior_width - EPSILON_MM
              add_warning('Partition thickness exceeded interior width; using carcass panel thickness instead.')
              candidate = nil
            end

            @partition_thickness_mm = if candidate && candidate > EPSILON_MM
                                        candidate
                                      else
                                        panel_thickness_mm
                                      end
          end

          def warnings
            ensure_computed
            @warnings.dup
          end

          private

          attr_reader :raw, :panel_thickness_mm, :width_mm, :min_bay_width_mm

          def ensure_computed
            return if @computed

            @partition_left_faces_mm = compute_partition_left_faces
            @bay_ranges_mm = compute_bay_ranges_from_faces(@partition_left_faces_mm)
            @computed = true
          end

          def interior_left_face_mm
            panel_thickness_mm
          end

          def interior_right_face_mm
            width_mm - panel_thickness_mm
          end

          def interior_width_mm
            interior_right_face_mm - interior_left_face_mm
          end

          def compute_bay_ranges_from_faces(faces)
            left = interior_left_face_mm
            right = interior_right_face_mm
            interior_width = right - left
            return [] if interior_width < min_bay_width_mm

            ranges = []
            current_left = left

            faces.each do |face|
              break if face - current_left < min_bay_width_mm - EPSILON_MM

              ranges << [current_left, face]
              current_left = face + partition_thickness_mm
              break if right - current_left < min_bay_width_mm - EPSILON_MM
            end

            if right - current_left >= min_bay_width_mm - EPSILON_MM
              ranges << [current_left, right]
            end

            ranges
          end

          def compute_partition_left_faces
            case partition_mode
            when :even
              even_partition_faces
            when :positions
              explicit_partition_faces
            else
              []
            end
          end

          def partition_mode
            @partition_mode ||= begin
              mode_value = fetch(raw, :mode)
              mode = mode_value.to_s.strip.downcase
              case mode
              when 'even'
                :even
              when 'positions'
                :positions
              else
                :none
              end
            end
          end

          def partition_count
            @partition_count ||= begin
              value = fetch(raw, :count)
              Integer(value)
            rescue ArgumentError, TypeError
              0
            end
          end

          def partition_positions
            @partition_positions ||= Array(fetch(raw, :positions_mm))
          end

          def even_partition_faces
            count = [partition_count, 0].max
            return [] if count <= 0

            thickness = partition_thickness_mm
            interior_width = interior_width_mm
            available_width = interior_width - (count * thickness)
            minimum_required = min_bay_width_mm * (count + 1)
            if available_width < minimum_required
              add_warning("Requested #{count} partitions but interior width only allows bays of at least #{format_mm(min_bay_width_mm)}; skipping even partitions.")
              return []
            end

            bay_width = available_width / (count + 1)
            if bay_width < min_bay_width_mm
              add_warning("Requested #{count} partitions but resulting bay width #{format_mm(bay_width)} is below minimum #{format_mm(min_bay_width_mm)}; skipping even partitions.")
              return []
            end

            left = interior_left_face_mm
            Array.new(count) do |index|
              left + ((index + 1) * bay_width) + (index * thickness)
            end
          end

          def explicit_partition_faces
            sorted = partition_positions.map { |value| safe_float(value) }.compact.sort
            return [] if sorted.empty?

            left_boundary = interior_left_face_mm
            right_boundary = interior_right_face_mm
            thickness = partition_thickness_mm

            offsets = []
            previous_original = nil
            sorted.each do |raw_offset|
              if previous_original && (raw_offset - previous_original).abs <= EPSILON_MM
                add_warning("Ignored duplicate partition at #{format_mm(raw_offset)} (positions mode).")
                next
              end

              clamped = clamp(raw_offset, left_boundary, right_boundary - thickness)
              if (clamped - raw_offset).abs > EPSILON_MM
                add_warning("Clamped partition from #{format_mm(raw_offset)} to #{format_mm(clamped)} to stay within cabinet interior.")
              end

              if offsets.any? && (clamped - offsets.last).abs <= EPSILON_MM
                add_warning("Ignored partition at #{format_mm(raw_offset)} because it overlaps another after clamping.")
                next
              end

              left_gap = clamped - (offsets.empty? ? left_boundary : offsets.last + thickness)
              if left_gap < min_bay_width_mm - EPSILON_MM
                add_warning("Ignored partition at #{format_mm(raw_offset)} because the bay to its left would be #{format_mm([left_gap, 0.0].max)} wide (minimum #{format_mm(min_bay_width_mm)}).")
                next
              end

              right_gap = right_boundary - (clamped + thickness)
              if right_gap < min_bay_width_mm - EPSILON_MM
                add_warning("Ignored partition at #{format_mm(raw_offset)} because the bay to its right would be #{format_mm([right_gap, 0.0].max)} wide (minimum #{format_mm(min_bay_width_mm)}).")
                next
              end

              offsets << clamped
              previous_original = raw_offset
            end

            offsets
          end

          def fetch(hash, key)
            return nil unless hash.is_a?(Hash)

            hash[key] || hash[key.to_s]
          end

          def safe_float(value)
            return value.to_f if value.is_a?(Numeric)

            Float(value)
          rescue ArgumentError, TypeError
            nil
          end

          def clamp(value, min_value, max_value)
            [[value, max_value].min, min_value].max
          end

          def add_warning(message)
            @warnings << message
          end

          def format_mm(value)
            format('%.3f mm', value.to_f)
          end
        end
      end
    end
  end
end
