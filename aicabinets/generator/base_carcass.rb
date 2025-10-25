# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module Carcass
      module_function

      # Public entry point for building a base cabinet carcass.
      #
      # @param parent [Sketchup::Entities, Sketchup::ComponentDefinition]
      # @param params_mm [Hash]
      # @return [Hash] opaque result for callers/tests. Currently returns
      #   { instances: { key => Sketchup::ComponentInstance }, bounds: Geom::BoundingBox }
      def build_base_carcass!(parent:, params_mm:)
        builder = Builder.new(parent, params_mm)
        builder.build
      end

      class Builder
        REQUIRED_PARAMS = %i[
          width_mm depth_mm height_mm panel_thickness_mm back_thickness_mm
          toe_kick_height_mm toe_kick_depth_mm
        ].freeze

        OPTIONAL_NUMERIC_PARAMS = %i[
          top_inset_mm bottom_inset_mm back_inset_mm shelf_count
          top_stringer_width_mm
        ].freeze

        DEFAULTS_MM = {
          top_inset_mm: 0.0,
          bottom_inset_mm: 0.0,
          back_inset_mm: 0.0,
          top_stringer_width_mm: 100.0,
          shelf_count: 0
        }.freeze

        TOP_TYPES = %i[panel stringers].freeze

        Result = Struct.new(:instances, :bounds, keyword_init: true)

        def initialize(parent, params_mm)
          @parent = parent
          @params_mm = DEFAULTS_MM.merge(params_mm.transform_keys(&:to_sym))
          validate_parent!
          validate_params!
          convert_units!
          @instances = {}
        end

        def build
          target_entities = resolve_entities(@parent)
          @carcass_group = target_entities.add_group
          build_sides
          build_bottom
          build_top
          build_back
          build_shelves

          bbox = Geom::BoundingBox.new
          @carcass_group.entities.each do |ent|
            bbox.add(ent.bounds) if ent.respond_to?(:bounds)
          end

          Result.new(instances: @instances, bounds: bbox)
        rescue StandardError
          undo_partial_build
          raise
        end

        private

        attr_reader :params

        def validate_parent!
          return if @parent.is_a?(Sketchup::Entities) || @parent.is_a?(Sketchup::ComponentDefinition)

          raise ArgumentError, 'parent must be Sketchup::Entities or Sketchup::ComponentDefinition'
        end

        def validate_params!
          missing = REQUIRED_PARAMS.reject { |key| @params_mm.key?(key) }
          raise ArgumentError, "Missing parameters: #{missing.join(', ')}" if missing.any?

          (REQUIRED_PARAMS + OPTIONAL_NUMERIC_PARAMS).each do |key|
            next unless @params_mm.key?(key)

            value = @params_mm[key]
            if value.nil?
              raise ArgumentError, "Parameter #{key} cannot be nil"
            end

            next if key == :top_type

            unless value.is_a?(Numeric) && value >= 0
              raise ArgumentError, "Parameter #{key} must be a non-negative number"
            end
          end

          top_type = (@params_mm[:top_type] || :panel).to_sym
          unless TOP_TYPES.include?(top_type)
            raise ArgumentError, "Unsupported top_type #{top_type}. Supported: #{TOP_TYPES.join(', ')}"
          end
        end

        def convert_units!
          @params = {
            width: length_mm(@params_mm[:width_mm]),
            depth: length_mm(@params_mm[:depth_mm]),
            height: length_mm(@params_mm[:height_mm]),
            panel_thickness: length_mm(@params_mm[:panel_thickness_mm]),
            back_thickness: length_mm(@params_mm[:back_thickness_mm]),
            toe_kick_height: length_mm(@params_mm[:toe_kick_height_mm]),
            toe_kick_depth: length_mm(@params_mm[:toe_kick_depth_mm]),
            top_inset: length_mm(@params_mm[:top_inset_mm]),
            bottom_inset: length_mm(@params_mm[:bottom_inset_mm]),
            back_inset: length_mm(@params_mm[:back_inset_mm]),
            top_type: (@params_mm[:top_type] || :panel).to_sym,
            top_stringer_width: length_mm(@params_mm[:top_stringer_width_mm]),
            shelf_count: @params_mm[:shelf_count].to_i,
            hole_columns: normalize_hole_columns(@params_mm[:hole_columns] || [])
          }

          @params[:cabinet_material] = @params_mm[:cabinet_material]
        end

        def resolve_entities(parent)
          return parent.entities if parent.is_a?(Sketchup::ComponentDefinition)

          parent
        end

        def length_mm(value)
          value.to_f.mm
        end

        def normalize_hole_columns(columns_mm)
          columns_mm.map do |col|
            {
              distance: length_mm(col[:distance_mm] || col[:distance] || 0),
              from: col[:from]&.to_sym,
              spacing: length_mm(col[:spacing_mm] || col[:spacing] || 32.0),
              diameter: length_mm(col[:diameter_mm] || col[:diameter] || 5.0),
              depth: length_mm(col[:depth_mm] || col[:depth] || 13.0),
              skip: col[:skip].to_i,
              first_hole: length_mm(col[:first_hole_mm] || col[:first_hole] || 0),
              count: col[:count].to_i
            }
          end
        end

        def cabinet_material
          AICabinets.respond_to?(:material) ? AICabinets.material(@params[:cabinet_material]) : nil
        end

        def build_sides
          left = @carcass_group.entities.add_group
          left.entities.add_face(
            [0, 0, @params[:toe_kick_height]],
            [0, @params[:depth], @params[:toe_kick_height]],
            [0, @params[:depth], @params[:height]],
            [0, 0, @params[:height]]
          ).pushpull(@params[:panel_thickness])
          left_comp = left.to_component
          left_comp.material = cabinet_material

          drill_hole_columns(
            left.entities,
            x: @params[:panel_thickness],
            from_right: false
          )

          right = @carcass_group.entities.add_group
          right.entities.add_face(
            [@params[:width], 0, @params[:toe_kick_height]],
            [@params[:width], @params[:depth], @params[:toe_kick_height]],
            [@params[:width], @params[:depth], @params[:height]],
            [@params[:width], 0, @params[:height]]
          ).pushpull(-@params[:panel_thickness])
          right_comp = right.to_component
          right_comp.material = cabinet_material

          drill_hole_columns(
            right.entities,
            x: @params[:width] - @params[:panel_thickness],
            from_right: true
          )

          @instances[:sides] = { left: left_comp, right: right_comp }
        end

        def build_bottom
          bottom = @carcass_group.entities.add_group
          bottom.entities.add_face(
            [@params[:panel_thickness], 0, @params[:bottom_inset] + @params[:panel_thickness]],
            [@params[:width] - @params[:panel_thickness], 0, @params[:bottom_inset] + @params[:panel_thickness]],
            [@params[:width] - @params[:panel_thickness], @params[:depth], @params[:bottom_inset] + @params[:panel_thickness]],
            [@params[:panel_thickness], @params[:depth], @params[:bottom_inset] + @params[:panel_thickness]]
          ).pushpull(-@params[:panel_thickness])
          bottom_comp = bottom.to_component
          bottom_comp.material = cabinet_material
          @instances[:bottom] = bottom_comp
        end

        def build_top
          case @params[:top_type]
          when :stringers
            build_top_stringers
          else
            top = @carcass_group.entities.add_group
            top.entities.add_face(
              [@params[:panel_thickness], 0, top_elevation],
              [@params[:width] - @params[:panel_thickness], 0, top_elevation],
              [@params[:width] - @params[:panel_thickness], @params[:depth], top_elevation],
              [@params[:panel_thickness], @params[:depth], top_elevation]
            ).pushpull(@params[:panel_thickness])
            top_comp = top.to_component
            top_comp.material = cabinet_material
            @instances[:top] = top_comp
          end
        end

        def build_top_stringers
          front = @carcass_group.entities.add_group
          front.entities.add_face(
            [@params[:panel_thickness], 0, top_elevation],
            [@params[:width] - @params[:panel_thickness], 0, top_elevation],
            [@params[:width] - @params[:panel_thickness], @params[:top_stringer_width], top_elevation],
            [@params[:panel_thickness], @params[:top_stringer_width], top_elevation]
          ).pushpull(@params[:panel_thickness])
          front_comp = front.to_component
          front_comp.material = cabinet_material

          back = @carcass_group.entities.add_group
          back.entities.add_face(
            [@params[:panel_thickness], @params[:depth] - @params[:top_stringer_width], top_elevation],
            [@params[:width] - @params[:panel_thickness], @params[:depth] - @params[:top_stringer_width], top_elevation],
            [@params[:width] - @params[:panel_thickness], @params[:depth], top_elevation],
            [@params[:panel_thickness], @params[:depth], top_elevation]
          ).pushpull(@params[:panel_thickness])
          back_comp = back.to_component
          back_comp.material = cabinet_material

          @instances[:top] = { front: front_comp, back: back_comp }
        end

        def build_back
          back = @carcass_group.entities.add_group
          back.entities.add_face(
            [@params[:panel_thickness], @params[:depth] - @params[:back_inset], back_bottom],
            [@params[:width] - @params[:panel_thickness], @params[:depth] - @params[:back_inset], back_bottom],
            [@params[:width] - @params[:panel_thickness], @params[:depth] - @params[:back_inset], top_elevation],
            [@params[:panel_thickness], @params[:depth] - @params[:back_inset], top_elevation]
          ).pushpull(@params[:back_thickness])
          back_comp = back.to_component
          back_comp.material = cabinet_material
          @instances[:back] = back_comp
        end

        def build_shelves
          return if @params[:shelf_count].to_i <= 0

          interior_height = @params[:height] - @params[:top_inset] - @params[:bottom_inset] - @params[:panel_thickness] * 2
          spacing = interior_height / (@params[:shelf_count] + 1)
          depth = @params[:depth] - @params[:back_inset] - @params[:back_thickness]

          shelves = []
          @params[:shelf_count].times do |index|
            z = @params[:bottom_inset] + @params[:panel_thickness] + spacing * (index + 1)
            shelf = @carcass_group.entities.add_group
            shelf.entities.add_face(
              [@params[:panel_thickness], 0, z],
              [@params[:width] - @params[:panel_thickness], 0, z],
              [@params[:width] - @params[:panel_thickness], depth, z],
              [@params[:panel_thickness], depth, z]
            ).pushpull(-@params[:panel_thickness])
            shelf_comp = shelf.to_component
            shelf_comp.material = cabinet_material
            shelves << shelf_comp
          end

          @instances[:shelves] = shelves
        end

        def top_elevation
          @params[:height] - @params[:top_inset] - @params[:panel_thickness]
        end

        def back_bottom
          @params[:bottom_inset] + @params[:panel_thickness]
        end

        def drill_hole_columns(entities, x:, from_right:)
          depth = @params[:depth] - @params[:back_inset]
          panel_thickness = @params[:panel_thickness] + @params[:bottom_inset]

          AICabinets::Generator::Carcass.drill_hole_columns(
            entities,
            x: x,
            depth: depth,
            panel_thickness: panel_thickness,
            back_thickness: @params[:back_thickness],
            hole_diameter: first_column[:diameter],
            hole_depth: first_column[:depth],
            hole_spacing: first_column[:spacing],
            columns: @params[:hole_columns],
            from_right: from_right
          ) if @params[:hole_columns].any?
        end

        def first_column
          @params[:hole_columns].first
        end

        def undo_partial_build
          return unless defined?(@carcass_group) && @carcass_group.valid?

          @carcass_group.erase!
        end
      end

      module_function

      def drill_hole_columns(
        entities,
        x:,
        depth:,
        panel_thickness:,
        back_thickness:,
        hole_diameter:,
        hole_depth:,
        hole_spacing:,
        columns:,
        from_right: false
      )
        normal = Geom::Vector3d.new(from_right ? -1 : 1, 0, 0)

        columns.each do |col|
          dist = col[:distance]
          y = if col[:from] == :rear
                depth - back_thickness - dist
              else
                dist
              end

          spacing = col[:spacing]
          diameter = col[:diameter]
          depth_drill = col[:depth]
          radius = diameter / 2
          skip = col[:skip].to_i
          first = col[:first_hole]
          z_start = panel_thickness + first + spacing * skip
          count = col[:count].to_i

          count.times do |i|
            z = z_start + spacing * i
            center = Geom::Point3d.new(x, y, z)
            edges = entities.add_circle(center, normal, radius)
            face = entities.add_face(edges)
            face ||= edges.first.faces.min_by(&:area)
            next unless face
            face.pushpull(-depth_drill)
          end
        end
      end
    end
  end
end
