# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/capabilities')
Sketchup.require('aicabinets/ops/units')

module AICabinets
  module Geometry
    module FivePiece
      # Builds a Shaker-profile frame with 45-degree mitered corners. The
      # geometry is generated in the local coordinate system of the supplied
      # entities so the outside FLB corner aligns with the frame origin.
      class MiterBuilder
        Units = AICabinets::Ops::Units

        CUT_TOLERANCE_MM = 0.02
        EPSILON_MM = 1.0e-6
        MM_PER_INCH = 25.4
        PLANE_SIZE_SCALE = 4.0

        Result = Struct.new(:stiles, :rails, :miter_mode, :warnings, keyword_init: true)

        class << self
          attr_reader :last_debug_reports

          def debug_report_for(group)
            return unless group && group.respond_to?(:entityID)

            (@last_debug_reports || {})[group.entityID]
          end

          def store_debug_reports(reports)
            @last_debug_reports = reports
          end
        end

        def initialize(entities:, open_width_mm:, open_height_mm:, stile_width_mm:, rail_width_mm:, thickness_mm:, material:, front_tag:)
          @entities = entities
          @open_width_mm = open_width_mm
          @open_height_mm = open_height_mm
          @stile_width_mm = stile_width_mm
          @rail_width_mm = rail_width_mm
          @thickness_mm = thickness_mm
          @material = material
          @front_tag = front_tag

          @warnings = []
          @miter_mode = nil
          @debug_reports = {}
        end

        def build
          outside_width_mm = @open_width_mm + (2.0 * @stile_width_mm)
          outside_height_mm = @open_height_mm + (2.0 * @rail_width_mm)

          profile_depth_mm = [[FivePiece::SHAKER_PROFILE_DEPTH_MM, @thickness_mm].min, FivePiece::MIN_DIMENSION_MM].max
          stile_profile_run_mm = [[FivePiece::SHAKER_PROFILE_RUN_MM, @stile_width_mm].min, FivePiece::MIN_DIMENSION_MM].max
          rail_profile_run_mm = [[FivePiece::SHAKER_PROFILE_RUN_MM, @rail_width_mm].min, FivePiece::MIN_DIMENSION_MM].max

          stiles = build_stiles(outside_height_mm, profile_depth_mm, stile_profile_run_mm, outside_width_mm)
          rails = build_rails(outside_width_mm, profile_depth_mm, rail_profile_run_mm, outside_height_mm)

          self.class.store_debug_reports(@debug_reports)

          Result.new(
            stiles: stiles,
            rails: rails,
            miter_mode: (@miter_mode || default_miter_mode),
            warnings: @warnings.dup
          )
        end

        private

        def default_miter_mode
          AICabinets::Capabilities.solid_booleans? ? :boolean : :intersect
        end

        def build_stiles(outside_height_mm, profile_depth_mm, profile_run_mm, outside_width_mm)
          stiles = []

          left = FivePiece.send(
            :create_stile_group,
            @entities,
            width_mm: @stile_width_mm,
            height_mm: outside_height_mm,
            thickness_mm: @thickness_mm,
            profile_depth_mm: profile_depth_mm,
            profile_run_mm: profile_run_mm,
            inside_facing: :positive
          )
          left = apply_stile_miters!(
            left,
            outside_height_mm,
            orientation: :left
          )
          apply_metadata(left, role: FivePiece::GROUP_ROLE_STILE, name: 'Stile-L')
          stiles << left

          right = FivePiece.send(
            :create_stile_group,
            @entities,
            width_mm: @stile_width_mm,
            height_mm: outside_height_mm,
            thickness_mm: @thickness_mm,
            profile_depth_mm: profile_depth_mm,
            profile_run_mm: profile_run_mm,
            inside_facing: :negative
          )
          right = apply_stile_miters!(
            right,
            outside_height_mm,
            orientation: :right
          )
          FivePiece.send(:translate_group!, right, x_mm: outside_width_mm - @stile_width_mm)
          apply_metadata(right, role: FivePiece::GROUP_ROLE_STILE, name: 'Stile-R')
          stiles << right

          stiles
        end

        def build_rails(outside_width_mm, profile_depth_mm, profile_run_mm, outside_height_mm)
          rails = []

          bottom = FivePiece.send(
            :create_rail_group,
            @entities,
            length_mm: outside_width_mm,
            rail_width_mm: @rail_width_mm,
            thickness_mm: @thickness_mm,
            profile_depth_mm: profile_depth_mm,
            profile_run_mm: profile_run_mm,
            inside_edge: :top
          )
          bottom = apply_rail_miters!(
            bottom,
            outside_width_mm,
            position: :bottom
          )
          apply_metadata(bottom, role: FivePiece::GROUP_ROLE_RAIL, name: 'Rail-Bottom')
          rails << bottom

          top = FivePiece.send(
            :create_rail_group,
            @entities,
            length_mm: outside_width_mm,
            rail_width_mm: @rail_width_mm,
            thickness_mm: @thickness_mm,
            profile_depth_mm: profile_depth_mm,
            profile_run_mm: profile_run_mm,
            inside_edge: :bottom
          )
          top = apply_rail_miters!(
            top,
            outside_width_mm,
            position: :top
          )
          FivePiece.send(:translate_group!, top, z_mm: outside_height_mm - @rail_width_mm)
          apply_metadata(top, role: FivePiece::GROUP_ROLE_RAIL, name: 'Rail-Top')
          rails << top

          rails
        end

        def apply_metadata(group, role:, name:)
          FivePiece.send(:apply_group_metadata, group, role: role, name: name, tag: @front_tag, material: @material)
        end

        def apply_stile_miters!(group, outside_height_mm, orientation:)
          interior_point = [@stile_width_mm * 0.5, @thickness_mm * 0.5, outside_height_mm * 0.5]

          group =
            case orientation
            when :left
              group = cut_with_plane_points!(
                group,
                a: [0.0, 0.0, 0.0],
                b: [0.0, @thickness_mm, 0.0],
                c: [@stile_width_mm, 0.0, @rail_width_mm],
                keep_point: interior_point,
                debug: { inside_span: { outer_z_mm: 0.0, inside_z_mm: @rail_width_mm } }
              )
              cut_with_plane_points!(
                group,
                a: [0.0, 0.0, outside_height_mm],
                b: [0.0, @thickness_mm, outside_height_mm],
                c: [@stile_width_mm, 0.0, outside_height_mm - @rail_width_mm],
                keep_point: interior_point,
                debug: { inside_span: { outer_z_mm: outside_height_mm, inside_z_mm: outside_height_mm - @rail_width_mm } }
              )
            when :right
              group = cut_with_plane_points!(
                group,
                a: [@stile_width_mm, 0.0, 0.0],
                b: [@stile_width_mm, @thickness_mm, 0.0],
                c: [0.0, 0.0, @rail_width_mm],
                keep_point: interior_point,
                debug: { inside_span: { outer_z_mm: 0.0, inside_z_mm: @rail_width_mm } }
              )
              cut_with_plane_points!(
                group,
                a: [@stile_width_mm, 0.0, outside_height_mm],
                b: [@stile_width_mm, @thickness_mm, outside_height_mm],
                c: [0.0, 0.0, outside_height_mm - @rail_width_mm],
                keep_point: interior_point,
                debug: { inside_span: { outer_z_mm: outside_height_mm, inside_z_mm: outside_height_mm - @rail_width_mm } }
              )
            else
              group
            end

          group
        end

        def apply_rail_miters!(group, outside_width_mm, position:)
          inside_z = position == :bottom ? @rail_width_mm : 0.0
          outer_z = position == :bottom ? 0.0 : @rail_width_mm
          mid_z = (inside_z + outer_z) * 0.5
          interior_point = [outside_width_mm * 0.5, @thickness_mm * 0.5, mid_z]

          group = cut_with_plane_points!(
            group,
            a: [0.0, 0.0, outer_z],
            b: [0.0, @thickness_mm, outer_z],
            c: [@stile_width_mm, 0.0, inside_z],
            keep_point: interior_point,
            debug: { inside_span: { outer_z_mm: outer_z, inside_z_mm: inside_z } }
          )

          group = cut_with_plane_points!(
            group,
            a: [outside_width_mm, 0.0, outer_z],
            b: [outside_width_mm, @thickness_mm, outer_z],
            c: [outside_width_mm - @stile_width_mm, 0.0, inside_z],
            keep_point: interior_point,
            debug: { inside_span: { outer_z_mm: outer_z, inside_z_mm: inside_z } }
          )

          group
        end

        def cut_with_plane_points!(group, a:, b:, c:, keep_point:, debug: nil)
          normal = cross_product(sub_vectors(b, a), sub_vectors(c, a))
          return group if vector_length(normal).zero?

          cut_with_plane!(group, normal: normal, point: a, keep_point: keep_point, debug: debug)
        end

        def cut_with_plane!(group, normal:, point:, keep: nil, keep_point: nil, debug: nil)
          return group unless group_valid?(group)

          plane = plane_data_for_group(group, normal, point)
          return group unless plane

          transformed_keep_point =
            if keep_point
              transform_point_mm(group, keep_point)
            end

          keep = determine_keep_side(plane[:normal_mm], plane[:point_mm], keep, transformed_keep_point)

          # Skip if the member already contains a capped face on this plane. This
          # protects the regeneration path from double-cutting the same corner,
          # which previously produced duplicate inside corners (AC7).
          faces_on_plane = faces_on_plane_count(group, plane[:normal_mm], plane[:point_mm])
          if faces_on_plane.positive?
            record_debug(group, build_debug_entry(group, plane, transformed_keep_point, debug).merge(
              mode: @miter_mode || default_miter_mode,
              reason_if_fallback: :already_trimmed,
              faces_on_plane_count: faces_on_plane
            ))
            return group
          end

          debug_entry = build_debug_entry(group, plane, transformed_keep_point, debug)

          if boolean_mode?
            @miter_mode ||= :boolean
            boolean_result = cut_with_boolean!(group, plane: plane, keep: keep)
            if boolean_result[:fallback]
              debug_entry[:reason_if_fallback] = boolean_result[:fallback]
              @miter_mode = :intersect
              warn_once('SketchUp solid booleans failed; reverted to geometric intersection for miters.')
              fallback = cut_with_intersection!(group, plane: plane, keep: keep)
              debug_entry.merge!(fallback)
              debug_entry[:reason_if_fallback] ||= fallback[:fallback]
            else
              debug_entry.merge!(boolean_result)
            end
          else
            @miter_mode ||= :intersect
            warn_once('SketchUp solid boolean operations unavailable; used geometric intersection for miters.')
            intersect_result = cut_with_intersection!(group, plane: plane, keep: keep)
            debug_entry.merge!(intersect_result)
            debug_entry[:reason_if_fallback] ||= intersect_result[:fallback]
          end

          debug_entry[:member][:volume_after_mm3] = safe_volume(group)

          record_debug(group, debug_entry)

          group
        end

        def determine_keep_side(normal_mm, point_mm, keep, keep_point_mm)
          if keep_point_mm
            distance = signed_distance_mm(normal_mm, point_mm, keep_point_mm)
            if distance.abs > CUT_TOLERANCE_MM
              return distance.negative? ? :negative : :positive
            end
          end

          keep || :positive
        end

        def boolean_mode?
          AICabinets::Capabilities.solid_booleans?
        end

        def warn_once(message)
          return if @warnings.any? { |existing| existing == message }

          @warnings << message
        end

        def plane_data_for_group(group, normal_mm, point_mm)
          point = Units.point_mm(*point_mm)
          normal = Units.vector_mm(*normal_mm)

          if group.respond_to?(:transformation)
            transformation = group.transformation
            point = point.transform(transformation)
            normal.transform!(transformation)
          end

          normal_length_mm = normal.length.to_f * MM_PER_INCH
          return nil if normal_length_mm <= EPSILON_MM

          normal.normalize!

          {
            point_mm: [point.x.to_f * MM_PER_INCH, point.y.to_f * MM_PER_INCH, point.z.to_f * MM_PER_INCH],
            normal_mm: [normal.x.to_f * MM_PER_INCH, normal.y.to_f * MM_PER_INCH, normal.z.to_f * MM_PER_INCH],
            point: point,
            normal: normal
          }
        rescue StandardError
          nil
        end

        def transform_point_mm(group, coords_mm)
          point = Units.point_mm(*coords_mm)
          if group.respond_to?(:transformation)
            point = point.transform(group.transformation)
          end

          [point.x.to_f * MM_PER_INCH, point.y.to_f * MM_PER_INCH, point.z.to_f * MM_PER_INCH]
        rescue StandardError
          nil
        end

        def build_solid_cutter(host_entities, group, plane, keep)
          cutter = host_entities.add_group
          extent_mm = plane_extent(group.bounds)
          extent_mm = 1.0 if extent_mm <= EPSILON_MM
          extent_length = Units.to_length_mm(extent_mm * 2.0)
          face = build_plane_face!(cutter.entities, plane, extent_length)
          raise 'Failed to construct cutter plane' unless face&.valid?

          waste_direction = plane[:normal].clone
          waste_direction.reverse! if keep == :positive
          waste_direction.normalize!
          face.reverse! if face.normal.dot(waste_direction) < 0.0

          thickness = Units.to_length_mm(extent_mm * 4.0)
          face.pushpull(thickness)

          heal_group!(cutter)
          cutter
        end

        def build_plane_face!(entities, plane, extent_length)
          u_vector, v_vector = plane_basis_vectors(plane[:normal])
          return nil unless u_vector && v_vector

          u_scaled = scaled_vector(u_vector, extent_length)
          v_scaled = scaled_vector(v_vector, extent_length)
          u_negative = u_scaled.clone.reverse!
          v_negative = v_scaled.clone.reverse!

          points = [
            plane[:point].offset(u_scaled + v_scaled),
            plane[:point].offset(u_negative + v_scaled),
            plane[:point].offset(u_negative + v_negative),
            plane[:point].offset(u_scaled + v_negative)
          ]

          entities.add_face(points)
        end

        def cut_with_intersection!(group, plane:, keep:)
          return { group: group, mode: :intersect, new_edges_count: 0, faces_on_plane_count: 0, fallback: 'Target group invalid' } unless group_valid?(group)

          target_entities = safe_entities(group)
          unless target_entities
            return {
              group: group,
              mode: :intersect,
              new_edges_count: 0,
              faces_on_plane_count: 0,
              fallback: 'Target group has no entities'
            }
          end

          host_entities, host_via = resolve_cutter_host_entities(group)
          host_debug = entities_debug_info(host_entities, host_via)
          unless host_entities.is_a?(Sketchup::Entities)
            return {
              group: group,
              mode: :intersect,
              new_edges_count: 0,
              faces_on_plane_count: faces_on_plane_count(group, plane[:normal_mm], plane[:point_mm]),
              fallback: 'Unable to resolve cutter host entities',
              cutter_host: host_debug
            }
          end

          helper = nil
          new_edges = []

          begin
            helper = host_entities.add_group
            face = build_plane_face!(helper.entities, plane, Units.to_length_mm(plane_extent(group.bounds)))
            raise 'Failed to construct cutter plane' unless face&.valid?

            new_edges = Array(
              helper.entities.intersect_with(
                true,
                helper.transformation,
                target_entities,
                group.transformation,
                true,
                [group]
              )
            )

            heal_plane_edges!(group, plane[:normal_mm], plane[:point_mm], new_edges)
            remove_faces_by_plane!(group, plane[:normal_mm], plane[:point_mm], keep)
            remove_plane_faces!(group, plane[:normal_mm], plane[:point_mm])
            heal_plane_edges!(group, plane[:normal_mm], plane[:point_mm], new_edges)
            add_cap_faces!(group, plane[:normal_mm], plane[:point_mm])
            purge_edges!(group)
            heal_plane_edges!(group, plane[:normal_mm], plane[:point_mm], new_edges)
            heal_group!(group)

            {
              group: group,
              mode: :intersect,
              new_edges_count: new_edges.length,
              faces_on_plane_count: faces_on_plane_count(group, plane[:normal_mm], plane[:point_mm]),
              cutter_host: host_debug
            }
          rescue StandardError => error
            {
              group: group,
              mode: :intersect,
              new_edges_count: Array(new_edges).length,
              faces_on_plane_count: faces_on_plane_count(group, plane[:normal_mm], plane[:point_mm]),
              fallback: error.message,
              cutter_host: host_debug
            }
          ensure
            helper.erase! if helper&.valid?
          end
        end

        def heal_plane_edges!(group, normal, point, candidate_edges = nil)
          return unless group_valid?(group)

          edges = Array(candidate_edges).compact.select { |edge| edge.respond_to?(:valid?) ? edge.valid? : true }
          if edges.empty?
            entities = safe_entities(group)
            edges = entities ? entities.grep(Sketchup::Edge) : []
          end

          edges.each do |edge|
            next unless edge&.valid?
            next unless edge.faces.empty?

            start_distance = signed_distance_mm(normal, point, edge.start.position)
            end_distance = signed_distance_mm(normal, point, edge.end.position)
            next unless start_distance.abs <= CUT_TOLERANCE_MM && end_distance.abs <= CUT_TOLERANCE_MM

            edge.find_faces
          rescue StandardError
            # Ignore failures; subsequent cleanup will cull stray geometry.
            next
          end
        end

        def cut_with_boolean!(group, plane:, keep:)
          unless group.respond_to?(:subtract)
            return { group: group, fallback: 'Group cannot perform boolean subtraction' }
          end

          host_entities, host_via = resolve_cutter_host_entities(group)
          host_debug = entities_debug_info(host_entities, host_via)
          unless host_entities.is_a?(Sketchup::Entities)
            info = boolean_preconditions(group, nil, host_entities, host_via)
            info[:target_volume_after_mm3] = safe_volume(group)
            return {
              group: group,
              fallback: 'Unable to resolve cutter host entities',
              boolean_preconditions: info,
              cutter_host: host_debug
            }
          end

          cutter = nil

          begin
            cutter = build_solid_cutter(host_entities, group, plane, keep)
            cutter_volume = safe_volume(cutter)
            cutter_solid = cutter_volume && cutter_volume.positive?
            raise 'Cutter is not a solid' unless cutter_solid

            target_volume_before = safe_volume(group)
            raise 'Target group is not a solid before subtraction' unless target_volume_before&.positive?

            boolean_result = group.subtract(cutter)
            raise 'Boolean subtraction returned nil' if boolean_result.nil?
            raise 'Group became invalid after boolean subtraction' unless group.valid?

            heal_group!(group)
            purge_edges!(group)

            {
              group: group,
              mode: :boolean,
              cutter: {
                volume_mm3: cutter_volume,
                solid: cutter_solid,
                host: host_debug
              },
              boolean_preconditions: boolean_preconditions(group, cutter, host_entities, host_via),
              faces_on_plane_count: faces_on_plane_count(group, plane[:normal_mm], plane[:point_mm])
            }
          rescue StandardError => error
            info = boolean_preconditions(group, cutter, host_entities, host_via)
            info[:target_volume_after_mm3] = safe_volume(group)
            {
              group: group,
              fallback: error.message,
              cutter: {
                volume_mm3: safe_volume(cutter),
                solid: cutter&.valid? && safe_volume(cutter)&.positive?,
                host: host_debug
              },
              boolean_preconditions: info,
              faces_on_plane_count: faces_on_plane_count(group, plane[:normal_mm], plane[:point_mm])
            }
          ensure
            cutter.erase! if cutter&.valid?
          end
        end

        def remove_plane_faces!(group, normal, point)
          return unless group_valid?(group)

          entities = safe_entities(group)
          return unless entities

          entities.grep(Sketchup::Face).each do |face|
            vertices = face.vertices
            next unless vertices.all? do |vertex|
              signed_distance_mm(normal, point, vertex.position).abs <= CUT_TOLERANCE_MM
            end

            begin
              face.erase!
            rescue StandardError
              # Ignore erase failures; stray fragments are removed by subsequent
              # cleanup passes.
            end
          end
        end

        def resolve_cutter_host_entities(group)
          return [nil, :invalid_group] unless group_valid?(group)

          parent = safe_parent(group)
          if defined?(Sketchup::Entities) && parent.is_a?(Sketchup::Entities)
            return [parent, :parent_entities]
          end

          if parent.respond_to?(:entities)
            entities = parent.entities
            return [entities, :parent_entities_method] if entities
          end

          if parent.respond_to?(:definition) && parent.definition.respond_to?(:entities)
            entities = parent.definition.entities
            return [entities, :definition_entities] if entities
          end

          if group.respond_to?(:model)
            model = group.model
            if model && model.respond_to?(:entities)
              entities = model.entities
              return [entities, :model_entities] if entities
            end
          end

          [nil, :unresolved]
        rescue StandardError
          model = group.respond_to?(:model) ? group.model : nil
          if model && model.respond_to?(:entities)
            [model.entities, :model_entities]
          else
            [nil, :error]
          end
        end

        def boolean_preconditions(group, cutter, container, container_via)
          volume_before = safe_volume(group)
          cutter_valid = cutter&.valid?
          group_parent = safe_parent(group)
          cutter_parent = safe_parent(cutter)

          {
            requested: boolean_mode?,
            target_volume_before_mm3: volume_before,
            target_solid_before: volume_before&.positive?,
            cutter_exists: cutter_valid,
            container_class: container&.class&.name,
            container_can_add_group: safe_can_add_group?(container),
            container_path: container_path(container),
            container_via: container_via,
            same_context: cutter_valid && group_parent ? cutter_parent == group_parent : nil
          }
        end

        def safe_can_add_group?(container)
          container.respond_to?(:add_group)
        rescue StandardError
          false
        end

        def group_valid?(group)
          group.respond_to?(:valid?) ? group.valid? : false
        rescue StandardError
          false
        end

        def safe_entities(group)
          return unless group_valid?(group)

          group.entities
        rescue StandardError
          nil
        end

        def heal_group!(group)
          entities = safe_entities(group)
          return unless entities

          entities.grep(Sketchup::Edge).each do |edge|
            next unless edge&.valid?

            begin
              edge.find_faces
            rescue StandardError
              next
            end
          end
        end

        def safe_parent(entity)
          return unless entity
          return unless entity.respond_to?(:parent)

          valid = !entity.respond_to?(:valid?) || entity.valid?
          return entity.parent if valid

          nil
        rescue StandardError
          nil
        end

        def container_path(container)
          return nil unless container

          labels = []
          current = container
          seen = {}.compare_by_identity

          while current && !seen[current]
            seen[current] = true
            labels.unshift(container_label(current))
            current =
              if current.respond_to?(:parent)
                current.parent
              elsif current.respond_to?(:model)
                current.model
              end
          end

          labels.compact.join(' > ')
        end

        def container_label(object)
          return 'Model' if defined?(Sketchup::Model) && object.is_a?(Sketchup::Model)
          return '(Entities)' if defined?(Sketchup::Entities) && object.is_a?(Sketchup::Entities)
          if object.respond_to?(:name)
            if defined?(Sketchup::ComponentDefinition) && object.is_a?(Sketchup::ComponentDefinition)
              return "Definition:#{object.name}"
            end
            if defined?(Sketchup::Group) && object.is_a?(Sketchup::Group)
              return "Group:#{object.name}"
            end
            if defined?(Sketchup::ComponentInstance) && object.is_a?(Sketchup::ComponentInstance)
              return "Instance:#{object.name}"
            end
          end

          object.class.name
        end

        def container_debug_info(group)
          container = safe_parent(group)
          {
            class: container&.class&.name,
            can_add_group: safe_can_add_group?(container),
            path: container_path(container)
          }
        end

        def entities_debug_info(entities, resolved_via = nil)
          return nil unless entities

          {
            class: entities.class.name,
            parent_class: entities.respond_to?(:parent) ? entities.parent&.class&.name : nil,
            path: container_path(entities),
            resolved_via: resolved_via
          }
        rescue StandardError
          nil
        end

        def opening_face_stability(group)
          entities = safe_entities(group)
          return {} unless entities

          front_faces = []
          loops_valid = true

          entities.grep(Sketchup::Face).each do |face|
            normal = face.normal
            next unless normal

            if normal.respond_to?(:y) && normal.y.abs >= 0.99
              front_faces << face
              loops_valid &&= face.loops.all? do |loop|
                !loop.respond_to?(:valid?) || loop.valid?
              end
            end
          rescue StandardError
            loops_valid = false
          end

          {
            front_plane_faces_count: front_faces.length,
            loops_valid: loops_valid
          }
        rescue StandardError
          {}
        end

        def model_units_summary(group)
          model = group.respond_to?(:model) ? group.model : nil
          return {} unless model

          begin
            options = model.options['UnitsOptions']
            return {} unless options

            {
              length_unit: options['LengthUnit'],
              length_format: options['LengthFormat']
            }
          rescue StandardError
            {}
          end
        end

        def plane_angle_deg(normalized_normal)
          x = normalized_normal[0].abs
          z = normalized_normal[2].abs
          return nil if x.zero? && z.zero?

          Math.atan2(z, x) * 180.0 / Math::PI
        end

        def remove_faces_by_plane!(group, normal, point, keep)
          return unless group_valid?(group)

          entities = safe_entities(group)
          return unless entities

          faces = entities.grep(Sketchup::Face)
          faces.each do |face|
            distances = face.vertices.map { |vertex| signed_distance_mm(normal, point, vertex.position) }
            case keep
            when :positive
              face.erase! if distances.all? { |distance| distance < -CUT_TOLERANCE_MM }
            when :negative
              face.erase! if distances.all? { |distance| distance > CUT_TOLERANCE_MM }
            end
          end
        end

        def add_cap_faces!(group, normal, point)
          return unless group_valid?(group)

          entities = safe_entities(group)
          return unless entities

          plane_edges = entities.grep(Sketchup::Edge).select do |edge|
            vertices = edge.vertices
            vertices.all? { |vertex| signed_distance_mm(normal, point, vertex.position).abs <= CUT_TOLERANCE_MM }
          end

          loops = extract_loops_from_edges(plane_edges)
          loops.each do |loop_points|
            next unless loop_points.length >= 3

            begin
              face = entities.add_face(loop_points)
              face.reverse! if face.normal.dot(Units.vector_mm(*normal)) < 0.0
            rescue StandardError
              # Ignore face creation errors; geometry may already be closed.
            end
          end
        end

        def extract_loops_from_edges(edges)
          edges = edges.dup
          loops = []

          until edges.empty?
            edge = edges.shift
            loop_vertices = [edge.start, edge.end]

            while (next_edge = edges.find { |candidate| candidate.start == loop_vertices.last || candidate.end == loop_vertices.last })
              edges.delete(next_edge)
              next_vertex = next_edge.start == loop_vertices.last ? next_edge.end : next_edge.start
              break if next_vertex == loop_vertices.first

              loop_vertices << next_vertex
            end

            loops << loop_vertices
          end

          loops.map { |vertex_loop| vertex_loop.map(&:position) }
        end

        def purge_edges!(group)
          entities = safe_entities(group)
          return unless entities

          entities.grep(Sketchup::Edge).each do |edge|
            next if edge.deleted?
            next if edge.faces.any?

            edge.erase!
          end
        end

        def record_debug(group, entry)
          return unless group_valid?(group)

          entity_id = group.entityID
          report = (@debug_reports[entity_id] ||= new_debug_report(group))
          report[:cuts] << entry.dup

          %i[
            mode
            plane
            member
            cutter
            cutter_host
            inside_span
            faces_on_plane_count
            new_edges_count
            reason_if_fallback
            boolean_preconditions
          ].each do |key|
            report[key] = entry[key]
          end

          report[:container] = entry[:container] if entry[:container]
          report[:opening_face] = opening_face_stability(group)

          log_debug_information(group, entry) if debug_logging?
        end

        def new_debug_report(group)
          {
            group_name: (group.respond_to?(:name) ? group.name : nil),
            dims: {
              opening_w_mm: @open_width_mm,
              opening_h_mm: @open_height_mm
            },
            widths: {
              stile_mm: @stile_width_mm,
              rail_mm: @rail_width_mm
            },
            container: container_debug_info(group),
            model_units: model_units_summary(group),
            opening_face: opening_face_stability(group),
            cuts: []
          }
        end

        def debug_logging?
          ENV['AIC_DEBUG'] == '1'
        end

        def log_debug_information(group, entry)
          message = "[FivePiece::MiterBuilder] #{group.name || group.entityID}: #{entry.inspect}"
          puts(message)
        rescue StandardError
          nil
        end

        def build_debug_entry(group, plane, keep_point, debug)
          normalized = normalize_vector(plane[:normal_mm].dup)
          {
            mode: nil,
            plane: {
              point: plane[:point_mm].dup,
              normal: normalized,
              tol_mm: CUT_TOLERANCE_MM,
              angle_deg: plane_angle_deg(normalized)
            },
            member: {
              name: group.respond_to?(:name) ? group.name : nil,
              volume_before_mm3: safe_volume(group)
            },
            cutter: nil,
            inside_span: debug&.fetch(:inside_span, nil),
            faces_on_plane_count: 0,
            new_edges_count: nil,
            reason_if_fallback: nil,
            keep_point: keep_point,
            container: container_debug_info(group),
            boolean_preconditions: nil
          }
        end

        def faces_on_plane_count(group, normal, point)
          entities = safe_entities(group)
          return 0 unless entities

          entities.grep(Sketchup::Face).count do |face|
            face.vertices.all? do |vertex|
              signed_distance_mm(normal, point, vertex.position).abs <= CUT_TOLERANCE_MM
            end
          end
        end

        def plane_extent(bounds)
          max = [
            bounds.width,
            bounds.height,
            bounds.depth,
            Units.to_length_mm(@stile_width_mm),
            Units.to_length_mm(@rail_width_mm)
          ].compact.map { |length| length_to_mm(length) }.max || (@stile_width_mm + @rail_width_mm)
          max * PLANE_SIZE_SCALE
        end

        def plane_basis(normal)
          n = normalize_vector(normal)
          u = if n[0].abs > n[2].abs
                normalize_vector([-(n[1] || 0.0), n[0], 0.0])
              else
                normalize_vector([0.0, -(n[2] || 0.0), n[1]])
              end
          u = normalize_vector([1.0, 0.0, 0.0]) if vector_length(u).zero?
          v = cross_product(n, u)
          { u: u, v: normalize_vector(v) }
        end

        def plane_basis_vectors(normal)
          return [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1)] unless normal && normal.respond_to?(:clone)

          basis_normal = normal.clone
          length_mm = basis_normal.length.to_f * MM_PER_INCH
          return [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1)] if length_mm <= EPSILON_MM

          basis_normal.normalize!
          up = Geom::Vector3d.new(0, 0, 1)
          up = Geom::Vector3d.new(1, 0, 0) if basis_normal.parallel?(up)
          u = basis_normal.cross(up)
          if u.length.to_f * MM_PER_INCH <= EPSILON_MM
            up = Geom::Vector3d.new(0, 1, 0)
            u = basis_normal.cross(up)
          end
          return [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1)] if u.length.to_f * MM_PER_INCH <= EPSILON_MM

          u.normalize!
          v = basis_normal.cross(u)
          v.normalize!

          [u, v]
        end

        def scaled_vector(vector, length)
          copy = vector.clone
          scale = length.respond_to?(:to_f) ? length.to_f : length
          copy.length = scale if scale
          copy
        end

        def normalize_vector(vector)
          length = vector_length(vector)
          return [0.0, 0.0, 0.0] if length <= EPSILON_MM

          vector.map { |component| component / length }
        end

        def vector_length(vector)
          Math.sqrt(vector.reduce(0.0) { |sum, component| sum + (component * component) })
        end

        def cross_product(a, b)
          [
            (a[1] * b[2]) - (a[2] * b[1]),
            (a[2] * b[0]) - (a[0] * b[2]),
            (a[0] * b[1]) - (a[1] * b[0])
          ]
        end

        def scale_vector(vector, scale)
          vector.map { |component| component * scale }
        end

        def add_vectors(a, b)
          [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
        end

        def sub_vectors(a, b)
          [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
        end

        def safe_volume(entity)
          return unless entity && entity.respond_to?(:volume)

          volume = entity.volume
          return unless volume.respond_to?(:to_f)

          volume.to_f * (MM_PER_INCH**3)
        rescue StandardError
          nil
        end

        def signed_distance_mm(normal, point, candidate)
          coords_mm =
            if candidate.respond_to?(:x)
              [candidate.x, candidate.y, candidate.z].map { |component| component.to_f * MM_PER_INCH }
            elsif candidate.is_a?(Array) && candidate.length >= 3
              [candidate[0], candidate[1], candidate[2]]
            else
              return 0.0
            end

          vector = [coords_mm[0] - point[0], coords_mm[1] - point[1], coords_mm[2] - point[2]]
          dot = (normal[0] * vector[0]) + (normal[1] * vector[1]) + (normal[2] * vector[2])
          normal_length = vector_length(normal)
          return dot if normal_length <= EPSILON_MM

          dot / normal_length
        end

        def length_to_mm(length)
          length_class = Units.const_defined?(:LENGTH_CLASS) ? Units::LENGTH_CLASS : nil
          if length_class && length.is_a?(length_class)
            length.to_f * MM_PER_INCH
          elsif length.respond_to?(:to_f)
            length.to_f
          else
            length
          end
        end
      end
    end
  end
end
