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
  module Geom
    module FivePiece
      module_function

      Units = AICabinets::Ops::Units
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
        outside_h_mm = length_to_mm(bbox.height)

        open_w_mm = outside_w_mm - (2.0 * params[:stile_width_mm].to_f)
        open_h_mm = outside_h_mm - (2.0 * params[:rail_width_mm].to_f)

        raise AICabinets::ValidationError, 'Unable to infer opening width' unless open_w_mm > MIN_DIMENSION_MM
        raise AICabinets::ValidationError, 'Unable to infer opening height' unless open_h_mm > MIN_DIMENSION_MM

        [open_w_mm, open_h_mm]
      end

      def resolve_style(explicit, param_style)
        candidate = explicit || param_style || :flat
        candidate = candidate.to_sym if candidate.respond_to?(:to_sym)

        return candidate if %i[flat raised reverse_raised].include?(candidate)

        :flat
      end
      private_class_method :resolve_style

      def ensure_panel_seats!(params)
        thickness_mm = params[:panel_thickness_mm].to_f
        groove_depth_mm = params[:groove_depth_mm].to_f

        max_allowed = groove_depth_mm - SEATING_CLEARANCE_MM
        return if thickness_mm <= max_allowed

        message = format(
          'panel_thickness_mm %.2f exceeds groove_depth_mm %.2f minus seating clearance %.2f',
          thickness_mm,
          groove_depth_mm,
          SEATING_CLEARANCE_MM
        )
        raise AICabinets::ValidationError, message
      end
      private_class_method :ensure_panel_seats!

      def resolve_opening(open_w_mm, open_h_mm, definition, params)
        width_mm = open_w_mm
        height_mm = open_h_mm

        unless width_mm && height_mm
          inferred_w_mm, inferred_h_mm = opening_from_frame(definition: definition)
          width_mm ||= inferred_w_mm
          height_mm ||= inferred_h_mm
        end

        [width_mm, height_mm]
      end
      private_class_method :resolve_opening

      def panel_y_start(params)
        door_thickness_mm = params[:door_thickness_mm]
        door_thickness_mm = params[:groove_depth_mm] unless door_thickness_mm.is_a?(Numeric)
        panel_thickness_mm = params[:panel_thickness_mm]
        offset_mm = params[:panel_offset_y_mm].to_f

        base_mm = door_thickness_mm.to_f
        start_mm = (base_mm - panel_thickness_mm) / 2.0
        start_mm = 0.0 if start_mm.nan? || start_mm.negative?
        start_mm + offset_mm
      end
      private_class_method :panel_y_start

      def build_flat_panel(entities, width_mm:, height_mm:, thickness_mm:)
        group = entities.add_group
        face = group.entities.add_face(
          Units.point_mm(0.0, 0.0, 0.0),
          Units.point_mm(width_mm, 0.0, 0.0),
          Units.point_mm(width_mm, 0.0, height_mm),
          Units.point_mm(0.0, 0.0, height_mm)
        )
        ensure_face_normal!(face, axis: :y)
        face.pushpull(Units.to_length_mm(thickness_mm))
        group
      end
      private_class_method :build_flat_panel

      def apply_style!(group, style:, width_mm:, height_mm:, thickness_mm:, cove_radius_mm:)
        return group unless group&.valid?
        return group if style == :flat

        target_front = style == :raised
        inset_mm = [cove_radius_mm.to_f, width_mm / 4.0, height_mm / 4.0].select { |v| v > MIN_DIMENSION_MM }.min
        depth_mm = [cove_radius_mm.to_f, thickness_mm - MIN_DIMENSION_MM].select { |v| v > MIN_DIMENSION_MM }.min

        return group unless inset_mm && depth_mm

        apply_bevel!(
          group,
          width_mm: width_mm,
          height_mm: height_mm,
          depth_mm: depth_mm,
          inset_mm: inset_mm,
          front: target_front
        )

        group
      end
      private_class_method :apply_style!

      def apply_bevel!(group, width_mm:, height_mm:, depth_mm:, inset_mm:, front: true)
        target_y = front ? 0.0 : length_to_mm(group.bounds.depth)
        face = find_face_at_y(group, target_y)
        return group unless face

        path_edges = face.outer_loop.edges
        start_vertex = face.outer_loop.vertices.first
        return group unless start_vertex

        offset_y = front ? depth_mm : -depth_mm

        profile_points = [
          Units.point_mm(0.0, 0.0, 0.0),
          Units.point_mm(inset_mm, offset_y, 0.0),
          Units.point_mm(0.0, offset_y, 0.0)
        ]

        translation = Geom::Transformation.translation(start_vertex.position.to_a)
        profile_points.map! { |point| point.transform(translation) }

        profile_face = group.entities.add_face(profile_points)
        return group unless profile_face

        profile_face.followme(path_edges)
        group.entities.erase_entities(profile_face) if profile_face.valid?

        group
      rescue StandardError
        group
      end
      private_class_method :apply_bevel!

      def find_face_at_y(group, y_mm)
        faces = group.entities.grep(Sketchup::Face)
        tolerance = Units.to_length_mm(0.1)
        faces.find do |face|
          vertices = face.vertices
          next if vertices.empty?

          vertices.all? { |vertex| (vertex.position.y - Units.to_length_mm(y_mm)).abs <= tolerance }
        end
      end
      private_class_method :find_face_at_y

      def apply_panel_metadata(group, model:, material_id:)
        return group unless group&.valid?

        dictionary = group.attribute_dictionary(PANEL_DICTIONARY, true)
        dictionary[PANEL_ROLE_KEY] = PANEL_ROLE_VALUE

        group.name = 'Panel' if group.respond_to?(:name=)

        tag = ensure_fronts_tag(model)
        group.layer = tag if tag

        material = resolve_panel_material(model, material_id)
        assign_material(group, material) if material

        group
      end
      private_class_method :apply_panel_metadata

      def resolve_panel_material(model, material_id)
        return nil unless model

        name = material_id.to_s
        if name.empty?
          AICabinets::Ops::Materials.default_door(model)
        else
          ensure_material(model, name)
        end
      end
      private_class_method :resolve_panel_material

      def ensure_material(model, name)
        materials = model.materials
        materials[name] || materials.add(name)
      rescue StandardError
        nil
      end
      private_class_method :ensure_material

      def ensure_fronts_tag(model)
        return unless model.is_a?(Sketchup::Model)

        tag_name = AICabinets::Generator::Fronts::FRONTS_TAG_NAME
        AICabinets::Ops::Tags.ensure_tag(model, tag_name)
      rescue StandardError
        nil
      end
      private_class_method :ensure_fronts_tag

      def assign_material(group, material)
        group.material = material if group.respond_to?(:material=)
        faces = group.entities.grep(Sketchup::Face)
        faces.each { |face| face.material = material }
      rescue StandardError
        nil
      end
      private_class_method :assign_material

      def translate_group!(group, x_mm: 0.0, y_mm: 0.0, z_mm: 0.0)
        return group unless group&.valid?

        translation = Geom::Transformation.translation([
          Units.to_length_mm(x_mm),
          Units.to_length_mm(y_mm),
          Units.to_length_mm(z_mm)
        ])
        group.transform!(translation)
        group
      end
      private_class_method :translate_group!

      def remove_existing_panel(entities)
        groups = entities.grep(Sketchup::Group).select do |group|
          dictionary = group.attribute_dictionary(PANEL_DICTIONARY)
          dictionary && dictionary[PANEL_ROLE_KEY] == PANEL_ROLE_VALUE
        end
        entities.erase_entities(groups) if groups.any?
      end
      private_class_method :remove_existing_panel

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

      def ensure_face_normal!(face, axis:, expected_positive: true)
        return unless face&.valid?

        component =
          case axis
          when :x then face.normal.x
          when :y then face.normal.y
          when :z then face.normal.z
          else 0.0
          end

        if expected_positive
          face.reverse! if component.negative?
        else
          face.reverse! if component.positive?
        end
      end
      private_class_method :ensure_face_normal!

      def length_to_mm(length_or_numeric)
        if length_or_numeric.respond_to?(:to_mm)
          length_or_numeric.to_mm
        else
          length_or_numeric.to_f * 25.4
        end
      end
      private_class_method :length_to_mm
    end
  end
end
