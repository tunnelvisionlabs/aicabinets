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
        end

        def build
          outside_width_mm = @open_width_mm + (2.0 * @stile_width_mm)
          outside_height_mm = @open_height_mm + (2.0 * @rail_width_mm)

          profile_depth_mm = [[FivePiece::SHAKER_PROFILE_DEPTH_MM, @thickness_mm].min, FivePiece::MIN_DIMENSION_MM].max
          stile_profile_run_mm = [[FivePiece::SHAKER_PROFILE_RUN_MM, @stile_width_mm].min, FivePiece::MIN_DIMENSION_MM].max
          rail_profile_run_mm = [[FivePiece::SHAKER_PROFILE_RUN_MM, @rail_width_mm].min, FivePiece::MIN_DIMENSION_MM].max

          stiles = build_stiles(outside_height_mm, profile_depth_mm, stile_profile_run_mm, outside_width_mm)
          rails = build_rails(outside_width_mm, profile_depth_mm, rail_profile_run_mm, outside_height_mm)

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
                keep_point: interior_point
              )
              cut_with_plane_points!(
                group,
                a: [0.0, 0.0, outside_height_mm],
                b: [0.0, @thickness_mm, outside_height_mm],
                c: [@stile_width_mm, 0.0, outside_height_mm - @rail_width_mm],
                keep_point: interior_point
              )
            when :right
              group = cut_with_plane_points!(
                group,
                a: [@stile_width_mm, 0.0, 0.0],
                b: [@stile_width_mm, @thickness_mm, 0.0],
                c: [0.0, 0.0, @rail_width_mm],
                keep_point: interior_point
              )
              cut_with_plane_points!(
                group,
                a: [@stile_width_mm, 0.0, outside_height_mm],
                b: [@stile_width_mm, @thickness_mm, outside_height_mm],
                c: [0.0, 0.0, outside_height_mm - @rail_width_mm],
                keep_point: interior_point
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
            keep_point: interior_point
          )

          group = cut_with_plane_points!(
            group,
            a: [outside_width_mm, 0.0, outer_z],
            b: [outside_width_mm, @thickness_mm, outer_z],
            c: [outside_width_mm - @stile_width_mm, 0.0, inside_z],
            keep_point: interior_point
          )

          group
        end

        def cut_with_plane_points!(group, a:, b:, c:, keep_point:)
          normal = cross_product(sub_vectors(b, a), sub_vectors(c, a))
          return group if vector_length(normal).zero?

          cut_with_plane!(group, normal: normal, point: a, keep_point: keep_point)
        end

        def cut_with_plane!(group, normal:, point:, keep: nil, keep_point: nil)
          return group unless group&.valid?

          keep = determine_keep_side(normal, point, keep, keep_point)

          if boolean_mode?
            @miter_mode ||= :boolean
            cut_with_boolean!(group, normal: normal, point: point, keep: keep)
          else
            @miter_mode ||= :intersect
            warn_once('SketchUp solid boolean operations unavailable; used geometric intersection for miters.')
            cut_with_intersection!(group, normal: normal, point: point, keep: keep)
          end
        end

        def determine_keep_side(normal, point, keep, keep_point)
          if keep_point
            distance = signed_distance_mm(normal, point, Units.point_mm(*keep_point))
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

        def build_cutter!(entities, bounds, normal, point)
          extent = plane_extent(bounds)
          basis = plane_basis(normal)
          origin = point

          u = scale_vector(basis[:u], extent)
          v = scale_vector(basis[:v], extent)
          plane_point = origin

          points = [
            add_vectors(add_vectors(plane_point, u), v),
            add_vectors(sub_vectors(plane_point, u), v),
            sub_vectors(sub_vectors(plane_point, u), v),
            add_vectors(sub_vectors(plane_point, u), v)
          ]

          face = entities.add_face(points.map { |coords| Units.point_mm(*coords) })
          raise 'Failed to construct cutter plane' unless face

          normal_vector = Units.vector_mm(*normal)
          face.reverse! if face.normal.dot(normal_vector) < 0.0
          face
        end

        def cut_with_intersection!(group, normal:, point:, keep:)
          new_edges = add_plane_intersection_edges!(group, normal, point)
          heal_plane_edges!(group, normal, point, new_edges)
          remove_faces_by_plane!(group, normal, point, keep)
          remove_plane_faces!(group, normal, point)
          heal_plane_edges!(group, normal, point, new_edges)
          add_cap_faces!(group, normal, point)
          purge_edges!(group)
          heal_plane_edges!(group, normal, point, new_edges)
          group
        end

        def add_plane_intersection_edges!(group, normal, point)
          return [] unless group&.valid?

          helper = group.entities.add_group
          build_cutter!(helper.entities, group.bounds, normal, point)

          source_entities = helper.entities
          target_entities = group.entities

          Array(
            source_entities.intersect_with(
              false,
              helper.transformation,
              target_entities,
              group.transformation,
              false,
              group
            )
          )
        ensure
          helper.erase! if helper&.valid?
        end

        def heal_plane_edges!(group, normal, point, candidate_edges = nil)
          edges = Array(candidate_edges)
          edges = group.entities.grep(Sketchup::Edge) if edges.empty?

          edges.each do |edge|
            next unless edge.valid?
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

        def cut_with_boolean!(group, normal:, point:, keep:)
          unless group.respond_to?(:subtract)
            @miter_mode = :intersect
            return cut_with_intersection!(group, normal: normal, point: point, keep: keep)
          end

          parent = group.parent
          unless parent.respond_to?(:add_group)
            @miter_mode = :intersect
            return cut_with_intersection!(group, normal: normal, point: point, keep: keep)
          end

          cutter = parent.add_group

          begin
            face = build_cutter!(cutter.entities, group.bounds, normal, point)
            raise 'Failed to create cutter face for boolean trim' unless face&.valid?

            distance_mm = plane_extent(group.bounds)
            distance_mm = 1.0 if distance_mm <= EPSILON_MM

            direction = keep == :positive ? -1.0 : 1.0
            pushpull_length = Units.to_length_mm(distance_mm * direction)
            face.pushpull(pushpull_length)

            cutter.transform!(group.transformation) if group.respond_to?(:transformation)

            boolean_result = group.subtract(cutter)
            if boolean_result.nil? || !group.valid?
              raise 'Boolean subtraction failed'
            end

            group
          rescue StandardError
            @miter_mode = :intersect
            warn_once('SketchUp solid booleans failed; reverted to geometric intersection for miters.')
            cut_with_intersection!(group, normal: normal, point: point, keep: keep)
          ensure
            cutter.erase! if cutter&.valid?
          end
        end

        def remove_plane_faces!(group, normal, point)
          group.entities.grep(Sketchup::Face).each do |face|
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

        def remove_faces_by_plane!(group, normal, point, keep)
          faces = group.entities.grep(Sketchup::Face)
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
          plane_edges = group.entities.grep(Sketchup::Edge).select do |edge|
            vertices = edge.vertices
            vertices.all? { |vertex| signed_distance_mm(normal, point, vertex.position).abs <= CUT_TOLERANCE_MM }
          end

          loops = extract_loops_from_edges(plane_edges)
          loops.each do |loop_points|
            next unless loop_points.length >= 3

            begin
              face = group.entities.add_face(loop_points)
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
          group.entities.grep(Sketchup::Edge).each do |edge|
            next if edge.deleted?
            next if edge.faces.any?

            edge.erase!
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

        def signed_distance_mm(normal, point, geom_point)
          coords = [geom_point.x, geom_point.y, geom_point.z].map { |component| component.to_f * MM_PER_INCH }
          vector = [coords[0] - point[0], coords[1] - point[1], coords[2] - point[2]]
          dot = (normal[0] * vector[0]) + (normal[1] * vector[1]) + (normal[2] * vector[2])
          normal_length = vector_length(normal)
          return dot if normal_length <= EPSILON_MM

          dot / normal_length
        end

        def length_to_mm(length)
          return length if length.is_a?(Numeric)

          length.to_f * MM_PER_INCH
        end
      end
    end
  end
end
