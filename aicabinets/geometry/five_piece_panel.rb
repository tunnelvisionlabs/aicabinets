# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/capabilities')
Sketchup.require('aicabinets/generator/fronts')
Sketchup.require('aicabinets/geometry/five_piece')
Sketchup.require('aicabinets/ops/materials')
Sketchup.require('aicabinets/ops/tags')
Sketchup.require('aicabinets/ops/units')
Sketchup.require('aicabinets/params/five_piece')
Sketchup.require('aicabinets/validation_error')

module AICabinets
  module Geometry
    module FivePiecePanel
      module_function

      Units = AICabinets::Ops::Units
      IDENTITY = Geom::Transformation.new
      MIN_DIMENSION_MM = AICabinets::Geometry::FivePiece::MIN_DIMENSION_MM

      PANEL_DICTIONARY = 'AICabinets::FivePiecePanel'.freeze
      PANEL_ROLE_KEY = 'role'.freeze
      PANEL_ROLE_VALUE = 'panel'.freeze

      OPERATION_NAME = 'Five-Piece Panel'.freeze
      DEFAULT_COVE_RADIUS_MM = 12.0
      SEATING_CLEARANCE_MM = 0.5

      def build_panel!(target:, params:, style: nil, cove_radius_mm: nil, open_w_mm: nil, open_h_mm: nil)
        definition = ensure_mutable_definition(target)
        model = definition.model
        raise ArgumentError, 'Definition has no owning model' unless model

        validated = AICabinets::Params::FivePiece.validate!(params: params)

        resolved_style = resolve_style(style, validated[:panel_style])
        cove_radius_mm ||= validated[:panel_cove_radius_mm]
        cove_radius_mm = DEFAULT_COVE_RADIUS_MM unless cove_radius_mm.is_a?(Numeric) && cove_radius_mm.positive?

        ensure_panel_seats!(validated)

        open_w_mm, open_h_mm = resolve_opening(open_w_mm, open_h_mm, definition, validated)

        clearance_mm = validated[:panel_clearance_per_side_mm]
        fit_w_mm = open_w_mm - (2.0 * clearance_mm)
        fit_h_mm = open_h_mm - (2.0 * clearance_mm)

        raise AICabinets::ValidationError, 'Panel fit width must be positive' unless fit_w_mm > MIN_DIMENSION_MM
        raise AICabinets::ValidationError, 'Panel fit height must be positive' unless fit_h_mm > MIN_DIMENSION_MM

        y_start_mm = panel_y_start(validated)

        warnings = []
        panel_group = nil
        operation_open = false

        begin
          operation_open = model.start_operation(OPERATION_NAME, true)

          remove_existing_panel(definition.entities)

          panel_group = build_flat_panel(
            definition.entities,
            width_mm: fit_w_mm,
            height_mm: fit_h_mm,
            thickness_mm: validated[:panel_thickness_mm]
          )

          apply_style!(
            panel_group,
            style: resolved_style,
            width_mm: fit_w_mm,
            height_mm: fit_h_mm,
            thickness_mm: validated[:panel_thickness_mm],
            cove_radius_mm: cove_radius_mm
          )

          translate_group!(
            panel_group,
            x_mm: validated[:stile_width_mm] + clearance_mm,
            y_mm: y_start_mm,
            z_mm: validated[:rail_width_mm] + clearance_mm
          )

          apply_panel_metadata(
            panel_group,
            model: model,
            material_id: validated[:panel_material_id]
          )

          warnings << 'Panel volume unavailable; geometry may not be solid.' unless panel_group.volume

          model.commit_operation if operation_open
          operation_open = false
        ensure
          model.abort_operation if operation_open
        end

        {
          panel: panel_group,
          style: resolved_style,
          warnings: warnings.compact
        }
      end

      def opening_from_frame(definition:)
        definition = ensure_valid_definition(definition)
        params = AICabinets::Params::FivePiece.read(definition)

        bbox = definition.bounds
        outside_w_mm = length_to_mm(bbox.width)
        outside_h_mm = length_to_mm(bbox.depth)

        open_w_mm = outside_w_mm - (2.0 * params[:stile_width_mm].to_f)
        open_h_mm = outside_h_mm - (2.0 * params[:rail_width_mm].to_f)

        raise AICabinets::ValidationError, 'Unable to infer opening width' unless open_w_mm > MIN_DIMENSION_MM
        raise AICabinets::ValidationError, 'Unable to infer opening height' unless open_h_mm > MIN_DIMENSION_MM

        [open_w_mm, open_h_mm]
      end

      def ensure_mutable_definition(target)
        definition_class = Sketchup.const_defined?(:ComponentDefinition) ? Sketchup::ComponentDefinition : nil
        instance_class = Sketchup.const_defined?(:ComponentInstance) ? Sketchup::ComponentInstance : nil

        case target
        when definition_class
          ensure_valid_definition(target)
        when instance_class
          ensure_valid_instance(target)
          target.make_unique if target.respond_to?(:make_unique)
          definition = target.definition
          ensure_valid_definition(definition)
        else
          raise ArgumentError, 'target must be a ComponentDefinition or ComponentInstance'
        end
      end
      private_class_method :ensure_mutable_definition

      def ensure_valid_definition(definition)
        raise ArgumentError, 'ComponentDefinition is required' unless definition
        raise ArgumentError, 'ComponentDefinition is no longer valid' unless definition.valid?

        definition
      end
      private_class_method :ensure_valid_definition

      def ensure_valid_instance(instance)
        raise ArgumentError, 'ComponentInstance is required' unless instance
        raise ArgumentError, 'ComponentInstance is no longer valid' unless instance.valid?
      end
      private_class_method :ensure_valid_instance

      def resolve_style(explicit_style, param_style)
        style = explicit_style || param_style || :flat
        style = style.to_sym if style.respond_to?(:to_sym)

        case style
        when :flat, :raised, :reverse_raised
          style
        else
          raise AICabinets::ValidationError, "Unsupported panel style: #{style.inspect}"
        end
      end
      private_class_method :resolve_style

      def resolve_opening(open_w_mm, open_h_mm, definition, validated)
        open_w_mm ||= nil
        open_h_mm ||= nil

        if open_w_mm.is_a?(Numeric) && open_w_mm.positive? && open_h_mm.is_a?(Numeric) && open_h_mm.positive?
          [open_w_mm, open_h_mm]
        else
          opening_from_frame(definition: definition)
        end
      end
      private_class_method :resolve_opening

      def ensure_panel_seats!(validated)
        thickness_mm = validated[:panel_thickness_mm]
        groove_depth_mm = validated[:groove_depth_mm]

        return unless thickness_mm > (groove_depth_mm - SEATING_CLEARANCE_MM)

        raise AICabinets::ValidationError,
              "Panel thickness (#{thickness_mm} mm) exceeds groove depth (#{groove_depth_mm} mm) minus seating clearance"
      end
      private_class_method :ensure_panel_seats!

      def panel_y_start(validated)
        thickness_mm = validated[:panel_thickness_mm]
        offset_y_mm = validated[:panel_offset_y_mm] || 0.0

        ((validated[:door_thickness_mm] - thickness_mm) / 2.0) + offset_y_mm
      end
      private_class_method :panel_y_start

      def build_flat_panel(entities, width_mm:, height_mm:, thickness_mm:)
        group = entities.add_group
        group.name = 'Panel'

        points = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(width_mm, 0, 0),
          Geom::Point3d.new(width_mm, 0, height_mm),
          Geom::Point3d.new(0, 0, height_mm)
        ]

        face = group.entities.add_face(points)
        face.reverse! unless face.normal.y.positive?
        face.pushpull(thickness_mm)

        group
      end
      private_class_method :build_flat_panel

      def apply_style!(group, style:, width_mm:, height_mm:, thickness_mm:, cove_radius_mm:)
        case style
        when :flat
          group
        when :raised
          apply_cove!(group, width_mm: width_mm, height_mm: height_mm, thickness_mm: thickness_mm, cove_radius_mm: cove_radius_mm)
          group
        when :reverse_raised
          apply_cove!(group, width_mm: width_mm, height_mm: height_mm, thickness_mm: thickness_mm, cove_radius_mm: cove_radius_mm)
          flip_y!(group)
          group
        else
          raise AICabinets::ValidationError, "Unsupported panel style: #{style.inspect}"
        end
      end
      private_class_method :apply_style!

      def apply_cove!(group, width_mm:, height_mm:, thickness_mm:, cove_radius_mm:)
        entities = group.entities
        profile = build_cove_profile(width_mm: width_mm, height_mm: height_mm, radius_mm: cove_radius_mm)
        cutter = entities.add_group(profile)
        cutter.name = 'Panel::CoveProfile'

        cutter_origin = Geom::Transformation.new([0, thickness_mm, 0])
        cutter.move!(cutter_origin)

        entities.intersect_with(true, IDENTITY, entities, IDENTITY, true, cutter.entities.to_a)
        cutter.erase!

        group
      end
      private_class_method :apply_cove!

      def build_cove_profile(width_mm:, height_mm:, radius_mm:)
        group = Sketchup.active_model.entities.add_group
        profile_entities = group.entities

        outer_points = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(width_mm, 0, 0),
          Geom::Point3d.new(width_mm, 0, height_mm),
          Geom::Point3d.new(0, 0, height_mm)
        ]
        profile_entities.add_face(outer_points)

        inset_w_mm = [radius_mm, width_mm / 2.0].min
        inset_h_mm = [radius_mm, height_mm / 2.0].min

        inner_points = [
          Geom::Point3d.new(inset_w_mm, 0, inset_h_mm),
          Geom::Point3d.new(width_mm - inset_w_mm, 0, inset_h_mm),
          Geom::Point3d.new(width_mm - inset_w_mm, 0, height_mm - inset_h_mm),
          Geom::Point3d.new(inset_w_mm, 0, height_mm - inset_h_mm)
        ]

        inner_face = profile_entities.add_face(inner_points)
        inner_face.erase!

        profile_entities.grep(Sketchup::Face).each do |face|
          next unless face.normal.y.positive?

          edges = face.edges
          next unless edges.size == 4

          edges.each do |edge|
            vector = edge.line[1]
            next unless vector.parallel?(Geom::Vector3d.new(1, 0, 0)) || vector.parallel?(Geom::Vector3d.new(0, 0, 1))

            midpoint = edge.start.position.offset(edge.line[1], edge.length / 2.0)
            face.pushpull(-radius_mm, true)
            arc_edges = profile_entities.add_arc(midpoint, edge.line[1], edge.line[1].axes[2], radius_mm, 0, Math::PI / 2.0)
            profile_entities.add_face(arc_edges)
          end
        end

        group
      end
      private_class_method :build_cove_profile

      def flip_y!(group)
        bounds = group.bounds
        y_center = bounds.center.y
        transform = Geom::Transformation.scaling(Geom::Point3d.new(0, y_center, 0), 1, -1, 1)
        group.transform!(transform)
      end
      private_class_method :flip_y!

      def translate_group!(group, x_mm:, y_mm:, z_mm:)
        transform = Geom::Transformation.new([x_mm, y_mm, z_mm])
        group.transform!(transform)
      end
      private_class_method :translate_group!

      def apply_panel_metadata(group, model:, material_id:)
        group.name = 'Panel'
        tag = AICabinets::Ops::Tags.ensure_tag(model, 'AICabinets/Fronts')
        group.layer = tag if tag

        material = AICabinets::Ops::Materials.find_or_default(model: model, material_id: material_id)
        group.material = material if material

        dictionary = group.attribute_dictionary(PANEL_DICTIONARY, true)
        dictionary[PANEL_ROLE_KEY] = PANEL_ROLE_VALUE

        group
      end
      private_class_method :apply_panel_metadata

      def remove_existing_panel(entities)
        entities.grep(Sketchup::Group).each do |group|
          dictionary = group.attribute_dictionary(PANEL_DICTIONARY)
          next unless dictionary && dictionary[PANEL_ROLE_KEY] == PANEL_ROLE_VALUE

          group.erase!
        end
      end
      private_class_method :remove_existing_panel

      def length_to_mm(length)
        Units.length_to_mm(length)
      end
      private_class_method :length_to_mm
    end
  end
end

