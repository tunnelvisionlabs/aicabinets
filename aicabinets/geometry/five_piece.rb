# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/capabilities')
Sketchup.require('aicabinets/generator/fronts')
Sketchup.require('aicabinets/ops/materials')
Sketchup.require('aicabinets/ops/tags')
Sketchup.require('aicabinets/ops/units')
Sketchup.require('aicabinets/params/five_piece')
Sketchup.require('aicabinets/tags')

module AICabinets
  module Geometry
    module FivePiece
      module_function

      Units = AICabinets::Ops::Units
      IDENTITY = Geom::Transformation.new

      OPERATION_NAME = 'AI Cabinets: Build Five-Piece Frame'.freeze
      GROUP_DICTIONARY = 'AICabinets::FivePieceFrame'.freeze
      GROUP_ROLE_KEY = 'role'.freeze
      GROUP_ROLE_STILE = 'stile'.freeze
      GROUP_ROLE_RAIL = 'rail'.freeze
      SHAKER_PROFILE_DEPTH_MM = 6.0
      SHAKER_PROFILE_ANGLE_DEGREES = 18.0
      SHAKER_PROFILE_RUN_MM = begin
        radians = SHAKER_PROFILE_ANGLE_DEGREES * Math::PI / 180.0
        depth = SHAKER_PROFILE_DEPTH_MM
        run = depth * Math.tan(radians)
        run = depth if run > depth
        run.positive? ? run : depth
      rescue StandardError
        4.0
      end
      MIN_DIMENSION_MM = 1.0e-3
      SUPPORTED_PROFILE_IDS = %w[square_inside shaker_inside shaker_bevel shaker].freeze

      def build_frame!(target:, params:, open_w_mm:, open_h_mm:)
        definition = ensure_mutable_definition(target)
        model = definition.model
        raise ArgumentError, 'Definition has no owning model' unless model

        validated = AICabinets::Params::FivePiece.validate!(params: params)
        joint_type = ensure_joint_type!(validated[:joint_type])
        ensure_supported_profile!(validated[:inside_profile_id])

        stile_width_mm = positive_length!(validated[:stile_width_mm], 'stile_width_mm')
        rail_width_mm = validated[:rail_width_mm]
        rail_width_mm = stile_width_mm unless rail_width_mm.is_a?(Numeric) && rail_width_mm > MIN_DIMENSION_MM
        thickness_mm = positive_length!(validated[:door_thickness_mm], 'door_thickness_mm')
        open_width_mm = positive_length!(open_w_mm, 'open_w_mm')
        open_height_mm = positive_length!(open_h_mm, 'open_h_mm')

        outside_w_mm = open_width_mm + (2.0 * stile_width_mm)
        outside_h_mm = open_height_mm + (2.0 * rail_width_mm)

        raise ArgumentError, 'Opening width must be positive' unless open_width_mm > MIN_DIMENSION_MM
        raise ArgumentError, 'Opening height must be positive' unless open_height_mm > MIN_DIMENSION_MM

        front_tag = ensure_fronts_tag(model)
        material = resolve_frame_material(model, validated[:frame_material_id])

        warnings = []
        stiles = []
        rails = []
        coping_mode = nil
        miter_mode = nil

        operation_open = false
        begin
          operation_open = model.start_operation(OPERATION_NAME, true)

          remove_existing_frame_groups(definition.entities)

          profile_depth_mm = [[SHAKER_PROFILE_DEPTH_MM, thickness_mm].min, MIN_DIMENSION_MM].max
          stile_profile_run_mm = [[SHAKER_PROFILE_RUN_MM, stile_width_mm].min, MIN_DIMENSION_MM].max
          rail_profile_run_mm = [[SHAKER_PROFILE_RUN_MM, rail_width_mm].min, MIN_DIMENSION_MM].max

          case joint_type
          when 'cope_stick'
            stiles = build_stiles(
              definition.entities,
              open_width_mm: outside_w_mm,
              stile_width_mm: stile_width_mm,
              height_mm: outside_h_mm,
              thickness_mm: thickness_mm,
              profile_depth_mm: profile_depth_mm,
              profile_run_mm: stile_profile_run_mm,
              material: material,
              front_tag: front_tag
            )

            inner_length_mm = outside_w_mm - (2.0 * stile_width_mm)
            raise ArgumentError, 'Opening width too small for rails' unless inner_length_mm > MIN_DIMENSION_MM

            if AICabinets::Capabilities.solid_booleans?
              rails = build_rails(
                definition.entities,
                stile_width_mm: stile_width_mm,
                inner_length_mm: inner_length_mm,
                rail_width_mm: rail_width_mm,
                thickness_mm: thickness_mm,
                profile_depth_mm: profile_depth_mm,
                profile_run_mm: rail_profile_run_mm,
                open_height_mm: outside_h_mm,
                material: material,
                front_tag: front_tag,
                _coping: true
              )
              coping_mode = :boolean_subtract
            else
              rails = build_rails(
                definition.entities,
                stile_width_mm: stile_width_mm,
                inner_length_mm: inner_length_mm,
                rail_width_mm: rail_width_mm,
                thickness_mm: thickness_mm,
                profile_depth_mm: profile_depth_mm,
                profile_run_mm: rail_profile_run_mm,
                open_height_mm: outside_h_mm,
                material: material,
                front_tag: front_tag,
                _coping: false
              )
              coping_mode = :square_fallback
              warnings << 'SketchUp solid boolean operations unavailable; generated square rail ends.'
            end
          when 'miter'
            result = build_miter_frame(
              definition.entities,
              stile_width_mm: stile_width_mm,
              rail_width_mm: rail_width_mm,
              outside_w_mm: outside_w_mm,
              outside_h_mm: outside_h_mm,
              thickness_mm: thickness_mm,
              profile_depth_mm: profile_depth_mm,
              profile_run_mm: {
                stile: stile_profile_run_mm,
                rail: rail_profile_run_mm
              },
              material: material,
              front_tag: front_tag,
              booleans_available: AICabinets::Capabilities.solid_booleans?
            )

            stiles = result[:stiles]
            rails = result[:rails]
            miter_mode = result[:miter_mode]
            warnings.concat(result[:warnings])
          end

          model.commit_operation if operation_open
          operation_open = false
        ensure
          model.abort_operation if operation_open
        end

        {
          stiles: stiles,
          rails: rails,
          coping_mode: coping_mode,
          joint_type: joint_type.to_sym,
          miter_mode: miter_mode,
          warnings: warnings
        }
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

      def ensure_supported_profile!(profile_id)
        id = profile_id.to_s
        return if SUPPORTED_PROFILE_IDS.include?(id)

        raise ArgumentError, "Unsupported inside_profile_id: #{profile_id.inspect}"
      end
      private_class_method :ensure_supported_profile!

      def ensure_joint_type!(joint_type)
        normalized = joint_type.to_s
        return normalized if %w[cope_stick miter].include?(normalized)

        raise ArgumentError, 'Five-piece frame generator only supports joint_type "cope_stick" or "miter"'
      end
      private_class_method :ensure_joint_type!

      def positive_length!(value, name)
        numeric = Float(value)
        raise ArgumentError, "#{name} must be positive" unless numeric > MIN_DIMENSION_MM

        numeric
      end
      private_class_method :positive_length!

      def remove_existing_frame_groups(entities)
        groups = entities.grep(Sketchup::Group).select do |group|
          dictionary = group.attribute_dictionary(GROUP_DICTIONARY)
          dictionary && dictionary[GROUP_ROLE_KEY]
        end
        entities.erase_entities(groups) if groups.any?
      end
      private_class_method :remove_existing_frame_groups

      def build_stiles(entities, open_width_mm:, stile_width_mm:, height_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:, material:, front_tag:)
        left = create_stile_group(
          entities,
          width_mm: stile_width_mm,
          height_mm: height_mm,
          thickness_mm: thickness_mm,
          profile_depth_mm: profile_depth_mm,
          profile_run_mm: profile_run_mm
        )
        apply_group_metadata(left, role: GROUP_ROLE_STILE, name: 'Stile-L', tag: front_tag, material: material)

        right = create_stile_group(
          entities,
          width_mm: stile_width_mm,
          height_mm: height_mm,
          thickness_mm: thickness_mm,
          profile_depth_mm: profile_depth_mm,
          profile_run_mm: profile_run_mm
        )
        translate_group!(right, x_mm: open_width_mm - stile_width_mm)
        apply_group_metadata(right, role: GROUP_ROLE_STILE, name: 'Stile-R', tag: front_tag, material: material)

        [left, right]
      end
      private_class_method :build_stiles

      def build_rails(entities, stile_width_mm:, inner_length_mm:, rail_width_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:, open_height_mm:, material:, front_tag:, _coping:)
        bottom = create_rail_group(
          entities,
          length_mm: inner_length_mm,
          rail_width_mm: rail_width_mm,
          thickness_mm: thickness_mm,
          profile_depth_mm: profile_depth_mm,
          profile_run_mm: profile_run_mm,
          inside_edge: :top
        )
        translate_group!(bottom, x_mm: stile_width_mm)
        apply_group_metadata(bottom, role: GROUP_ROLE_RAIL, name: 'Rail-Bottom', tag: front_tag, material: material)

        top = create_rail_group(
          entities,
          length_mm: inner_length_mm,
          rail_width_mm: rail_width_mm,
          thickness_mm: thickness_mm,
          profile_depth_mm: profile_depth_mm,
          profile_run_mm: profile_run_mm,
          inside_edge: :bottom
        )
        translate_group!(top, x_mm: stile_width_mm, z_mm: open_height_mm - rail_width_mm)
        apply_group_metadata(top, role: GROUP_ROLE_RAIL, name: 'Rail-Top', tag: front_tag, material: material)

        [bottom, top]
      end
      private_class_method :build_rails

      def create_stile_group(entities, width_mm:, height_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:)
        group = entities.add_group
        face = group.entities.add_face(stile_profile_points(width_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:))
        raise 'Failed to create stile profile face' unless face

        ensure_face_normal!(face, axis: :z)
        face.pushpull(Units.to_length_mm(height_mm))
        group
      end
      private_class_method :create_stile_group

      def stile_profile_points(width_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:)
        [
          Units.point_mm(0.0, 0.0, 0.0),
          Units.point_mm(width_mm - profile_run_mm, 0.0, 0.0),
          Units.point_mm(width_mm, profile_depth_mm, 0.0),
          Units.point_mm(width_mm, thickness_mm, 0.0),
          Units.point_mm(0.0, thickness_mm, 0.0)
        ]
      end
      private_class_method :stile_profile_points

      def create_rail_group(entities, length_mm:, rail_width_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:, inside_edge:)
        group = entities.add_group
        face = group.entities.add_face(rail_profile_points(rail_width_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:, inside_edge: inside_edge))
        raise 'Failed to create rail profile face' unless face

        ensure_face_normal!(face, axis: :x)
        face.pushpull(Units.to_length_mm(length_mm))

        group
      end
      private_class_method :create_rail_group

      def rail_profile_points(rail_width_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:, inside_edge:)
        base = [
          [0.0, 0.0, 0.0],
          [0.0, 0.0, rail_width_mm - profile_run_mm],
          [0.0, profile_depth_mm, rail_width_mm],
          [0.0, thickness_mm, rail_width_mm],
          [0.0, thickness_mm, 0.0]
        ]

        points =
          if inside_edge == :top
            base
          else
            base.map { |(x_mm, y_mm, z_mm)| [x_mm, y_mm, rail_width_mm - z_mm] }
          end

        points.map { |coords| Units.point_mm(*coords) }
      end
      private_class_method :rail_profile_points

      def build_miter_frame(entities, stile_width_mm:, rail_width_mm:, outside_w_mm:, outside_h_mm:, thickness_mm:, profile_depth_mm:, profile_run_mm:, material:, front_tag:, booleans_available:)
        warnings = []

        stiles = build_stiles(
          entities,
          open_width_mm: outside_w_mm,
          stile_width_mm: stile_width_mm,
          height_mm: outside_h_mm,
          thickness_mm: thickness_mm,
          profile_depth_mm: profile_depth_mm,
          profile_run_mm: profile_run_mm.fetch(:stile, stile_width_mm),
          material: material,
          front_tag: front_tag
        )

        rails = []
        %i[bottom top].each do |role|
          rail = create_rail_group(
            entities,
            length_mm: outside_w_mm,
            rail_width_mm: rail_width_mm,
            thickness_mm: thickness_mm,
            profile_depth_mm: profile_depth_mm,
            profile_run_mm: profile_run_mm.fetch(:rail, rail_width_mm),
            inside_edge: role == :bottom ? :top : :bottom
          )

          translate_group!(rail, z_mm: role == :bottom ? 0.0 : outside_h_mm - rail_width_mm)
          apply_group_metadata(rail, role: GROUP_ROLE_RAIL, name: role == :bottom ? 'Rail-Bottom' : 'Rail-Top', tag: front_tag, material: material)
          rails << rail
        end

        apply_group_metadata(stiles[0], role: GROUP_ROLE_STILE, name: 'Stile-L', tag: front_tag, material: material)
        translate_group!(stiles[1], x_mm: outside_w_mm - stile_width_mm)
        apply_group_metadata(stiles[1], role: GROUP_ROLE_STILE, name: 'Stile-R', tag: front_tag, material: material)

        miter_result = apply_miters!(
          stiles: stiles,
          rails: rails,
          height_mm: outside_h_mm,
          width_mm: outside_w_mm,
          booleans_available: booleans_available
        )
        warnings.concat(miter_result[:warnings])

        { stiles: stiles, rails: rails, miter_mode: miter_result[:miter_mode], warnings: warnings }
      end
      private_class_method :build_miter_frame

      def apply_miters!(stiles:, rails:, height_mm:, width_mm:, booleans_available:)
        miter_mode = :intersect
        warnings = []

        warnings << 'SketchUp solid boolean operations unavailable; generated miters via entity intersections.' unless booleans_available

        success = apply_miters_by_intersection!(
          stiles: stiles,
          rails: rails,
          height_mm: height_mm,
          width_mm: width_mm
        )

        { success: success, miter_mode: miter_mode, warnings: warnings }
      end
      private_class_method :apply_miters!

      def apply_miters_by_intersection!(stiles:, rails:, height_mm:, width_mm:)
        sorted_stiles = stiles.sort_by { |group| group.bounds.min.x }
        left_stile, right_stile = sorted_stiles

        cut_group_with_plane!(
          left_stile,
          point: Units.point_mm(0.0, 0.0, 0.0),
          normal: Geom::Vector3d.new(1.0, 0.0, -1.0),
          keep_positive: false
        )

        cut_group_with_plane!(
          left_stile,
          point: Units.point_mm(0.0, 0.0, height_mm),
          normal: Geom::Vector3d.new(-1.0, 0.0, -1.0),
          keep_positive: true
        )

        cut_group_with_plane!(
          right_stile,
          point: Units.point_mm(width_mm, 0.0, 0.0),
          normal: Geom::Vector3d.new(-1.0, 0.0, -1.0),
          keep_positive: false
        )

        cut_group_with_plane!(
          right_stile,
          point: Units.point_mm(width_mm, 0.0, height_mm),
          normal: Geom::Vector3d.new(1.0, 0.0, -1.0),
          keep_positive: true
        )

        sorted_rails = rails.sort_by { |group| group.bounds.min.z }
        bottom_rail, top_rail = sorted_rails

        cut_group_with_plane!(
          bottom_rail,
          point: Units.point_mm(0.0, 0.0, 0.0),
          normal: Geom::Vector3d.new(1.0, 0.0, -1.0),
          keep_positive: true
        )

        cut_group_with_plane!(
          bottom_rail,
          point: Units.point_mm(width_mm, 0.0, 0.0),
          normal: Geom::Vector3d.new(-1.0, 0.0, -1.0),
          keep_positive: true
        )

        cut_group_with_plane!(
          top_rail,
          point: Units.point_mm(0.0, 0.0, height_mm),
          normal: Geom::Vector3d.new(-1.0, 0.0, -1.0),
          keep_positive: false
        )

        cut_group_with_plane!(
          top_rail,
          point: Units.point_mm(width_mm, 0.0, height_mm),
          normal: Geom::Vector3d.new(1.0, 0.0, -1.0),
          keep_positive: false
        )

        true
      rescue StandardError
        false
      end
      private_class_method :apply_miters_by_intersection!

      def cut_group_with_plane!(group, point:, normal:, keep_positive: true)
        return false unless group&.valid?

        entities = group.entities
        plane_point = point
        plane_normal = normal
        size = (entities.bounds.diagonal.length.to_f * 1.5).clamp(Units.to_length_mm(10.0), Units.to_length_mm(5000.0))

        cutter = entities.add_group
        cutter_face = cutter.entities.add_face(plane_face_points(plane_point, plane_normal, size))
        raise 'Failed to create cutting face' unless cutter_face

        entities.intersect_with(true, IDENTITY, entities, IDENTITY, true, cutter.entities.to_a)
        cutter.erase!

        plane_origin = plane_point
        normal_vector = plane_normal
        tolerance = Units.to_length_mm(0.1)

        entities.grep(Sketchup::Face).each do |face|
          next unless face.valid?

          center = face.bounds.center
          offset = normal_vector.dot(center - plane_origin)
          erase = keep_positive ? offset < -tolerance : offset > tolerance
          entities.erase_entities(face) if erase
        end

        loose_edges = entities.grep(Sketchup::Edge).select { |edge| edge.valid? && edge.faces.empty? }
        entities.erase_entities(loose_edges) if loose_edges.any?

        true
      end
      private_class_method :cut_group_with_plane!

      def plane_face_points(origin, normal, size)
        unit_normal = normal.normalize
        axis = unit_normal.parallel?(Geom::Vector3d.new(0, 0, 1)) ? Geom::Vector3d.new(0, 1, 0) : Geom::Vector3d.new(0, 0, 1)
        u = unit_normal.cross(axis)
        u.length = size
        v = unit_normal.cross(u)
        v.length = size

        [
          origin.offset(u + v),
          origin.offset(u - v),
          origin.offset(-u - v),
          origin.offset(-u + v)
        ]
      end
      private_class_method :plane_face_points


      def apply_group_metadata(group, role:, name:, tag:, material:)
        return group unless group&.valid?

        dictionary = group.attribute_dictionary(GROUP_DICTIONARY, true)
        dictionary[GROUP_ROLE_KEY] = role

        group.name = name if group.respond_to?(:name=) && name
        assign_tag(group, tag)
        assign_material(group, material)

        group
      end
      private_class_method :apply_group_metadata

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

      def assign_tag(group, tag)
        return unless tag
        return unless group.respond_to?(:layer=)

        group.layer = tag
      rescue StandardError
        nil
      end
      private_class_method :assign_tag

      def assign_material(group, material)
        return unless material

        group.material = material if group.respond_to?(:material=)
        faces = group.entities.grep(Sketchup::Face)
        faces.each { |face| face.material = material }
      rescue StandardError
        nil
      end
      private_class_method :assign_material

      def ensure_fronts_tag(model)
        return unless model.is_a?(Sketchup::Model)

        tag_name = AICabinets::Generator::Fronts::FRONTS_TAG_NAME
        tag = AICabinets::Ops::Tags.ensure_tag(model, tag_name)
        if tag && tag.respond_to?(:name) && tag.respond_to?(:name=) && tag.name != tag_name
          begin
            tag.name = tag_name
          rescue StandardError
            # Best-effort rename; ignore if SketchUp prevents renaming due to folders.
            nil
          end
        end
        tag
      end
      private_class_method :ensure_fronts_tag

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

      def resolve_frame_material(model, material_id)
        return nil unless model

        name = material_id.to_s
        if name.empty?
          AICabinets::Ops::Materials.default_frame(model)
        else
          ensure_material(model, name)
        end
      end
      private_class_method :resolve_frame_material

      def ensure_material(model, name)
        materials = model.materials
        materials[name] || materials.add(name)
      rescue StandardError
        nil
      end
      private_class_method :ensure_material
    end
  end
end
