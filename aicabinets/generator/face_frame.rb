# frozen_string_literal: true

require 'sketchup.rb'

require 'aicabinets/face_frame'

Sketchup.require('aicabinets/ops/units')
Sketchup.require('aicabinets/ops/tags')

module AICabinets
  module Generator
    module FaceFrame
      module_function

      FACE_FRAME_NAME = 'Face Frame'
      FRONT_TAG_NAME = 'AICabinets/Fronts'
      MIN_DIMENSION_MM = 0.1

      def build(parent_entities:, params:, face_frame_mm:)
        validate_parent!(parent_entities)
        frame = normalized_face_frame(face_frame_mm)
        return nil unless frame[:enabled]

        thickness_mm = frame[:thickness_mm].to_f
        return nil unless thickness_mm.positive?

        width_mm = params.width_mm
        height_mm = params.height_mm
        return nil unless width_mm.positive? && height_mm.positive?

        model = parent_entities.respond_to?(:model) ? parent_entities.model : nil
        active_operation_name =
          model.respond_to?(:active_operation_name) ? model.active_operation_name.to_s : ''
        operation_started = false
        operation_transparent = false
        begin
          if model && model.respond_to?(:start_operation)
            start_transparent = !active_operation_name.empty?
            started = model.start_operation(
              'AI Cabinets: Face Frame',
              true,
              false,
              start_transparent
            )
            operation_started = started
            operation_transparent = start_transparent if started
          end

          thickness = Ops::Units.to_length_mm(thickness_mm)

          group = parent_entities.add_group
          group.name = FACE_FRAME_NAME if group.respond_to?(:name=)

          members = []
          members << build_member(
            parent: group,
            name: 'Stile Left',
            x_start_mm: 0.0,
            width_mm: frame[:stile_left_mm],
            z_start_mm: 0.0,
            height_mm: height_mm,
            thickness: thickness
          )

          right_x_mm = width_mm - frame[:stile_right_mm]
          members << build_member(
            parent: group,
            name: 'Stile Right',
            x_start_mm: right_x_mm,
            width_mm: frame[:stile_right_mm],
            z_start_mm: 0.0,
            height_mm: height_mm,
            thickness: thickness
          )

          top_z_mm = height_mm - frame[:rail_top_mm]
          members << build_member(
            parent: group,
            name: 'Rail Top',
            x_start_mm: 0.0,
            width_mm: width_mm,
            z_start_mm: top_z_mm,
            height_mm: frame[:rail_top_mm],
            thickness: thickness
          )

          members << build_member(
            parent: group,
            name: 'Rail Bottom',
            x_start_mm: 0.0,
            width_mm: width_mm,
            z_start_mm: 0.0,
            height_mm: frame[:rail_bottom_mm],
            thickness: thickness
          )

          mid_members = build_mid_members(group: group, frame: frame, thickness: thickness, params: params)
          members.concat(mid_members) if mid_members.any?

          Ops::Tags.assign!(group, FRONT_TAG_NAME)
          members.compact.each { |member| Ops::Tags.assign!(member, FRONT_TAG_NAME) }

          group
        rescue StandardError
          if operation_started && !operation_transparent && model.respond_to?(:abort_operation)
            model.abort_operation
          end
          raise
        ensure
          if operation_started && model.respond_to?(:commit_operation)
            model.commit_operation
          end
        end
      end

      def validate_parent!(entities)
        return if entities.is_a?(Sketchup::Entities)

        raise ArgumentError, 'parent_entities must be Sketchup::Entities'
      end
      private_class_method :validate_parent!

      def normalized_face_frame(face_frame_mm)
        defaults = AICabinets::FaceFrame.defaults_mm
        normalized, = AICabinets::FaceFrame.normalize(face_frame_mm, defaults: defaults)
        normalized
      end
      private_class_method :normalized_face_frame

      def build_mid_members(group:, frame:, thickness:, params:)
        opening_width_mm = params.width_mm - frame[:stile_left_mm] - frame[:stile_right_mm]
        opening_height_mm = params.height_mm - frame[:rail_top_mm] - frame[:rail_bottom_mm]
        return [] unless opening_width_mm.positive? && opening_height_mm.positive?

        members = []

        if frame[:mid_stile_mm].to_f > MIN_DIMENSION_MM
          mid_width_mm = [frame[:mid_stile_mm].to_f, opening_width_mm].min
          x_start_mm = frame[:stile_left_mm] + ((opening_width_mm - mid_width_mm) / 2.0)
          members << build_member(
            parent: group,
            name: 'Mid Stile',
            x_start_mm: x_start_mm,
            width_mm: mid_width_mm,
            z_start_mm: frame[:rail_bottom_mm],
            height_mm: opening_height_mm,
            thickness: thickness
          )
        end

        rail_count = mid_rail_count(frame[:layout])
        if frame[:mid_rail_mm].to_f > MIN_DIMENSION_MM && rail_count.positive?
          usable_width_mm = [opening_width_mm, MIN_DIMENSION_MM].max
          drawer_height_mm = opening_height_mm / (rail_count + 1)
          1.upto(rail_count) do |index|
            center_mm = frame[:rail_bottom_mm] + (drawer_height_mm * index)
            z_start_mm = center_mm - (frame[:mid_rail_mm] / 2.0)
            z_start_mm = frame[:rail_bottom_mm] if z_start_mm < frame[:rail_bottom_mm]
            z_end_mm = z_start_mm + frame[:mid_rail_mm]
            max_z_mm = frame[:rail_bottom_mm] + opening_height_mm
            z_end_mm = max_z_mm if z_end_mm > max_z_mm
            z_start_mm = max_z_mm - frame[:mid_rail_mm] if (z_end_mm - z_start_mm) < frame[:mid_rail_mm]
            height_mm = [z_end_mm - z_start_mm, frame[:mid_rail_mm]].max

            members << build_member(
              parent: group,
              name: "Mid Rail #{index}",
              x_start_mm: frame[:stile_left_mm],
              width_mm: usable_width_mm,
              z_start_mm: z_start_mm,
              height_mm: height_mm,
              thickness: thickness
            )
          end
        end

        members.compact
      end
      private_class_method :build_mid_members

      def mid_rail_count(layout)
        Array(layout).each do |entry|
          next unless entry.is_a?(Hash)

          kind = entry[:kind] || entry['kind']
          next unless kind == 'drawer_stack'

          drawers = entry[:drawers] || entry['drawers']
          return [drawers.to_i - 1, 0].max if drawers.is_a?(Numeric)
        end

        0
      end
      private_class_method :mid_rail_count

      def build_member(parent:, name:, x_start_mm:, width_mm:, z_start_mm:, height_mm:, thickness:)
        return nil unless width_mm.to_f > MIN_DIMENSION_MM
        return nil unless height_mm.to_f > MIN_DIMENSION_MM

        group = parent.entities.add_group
        group.name = name if group.respond_to?(:name=)

        x_end_mm = x_start_mm + width_mm
        z_end_mm = z_start_mm + height_mm

        face = group.entities.add_face(
          Ops::Units.point_mm(x_start_mm, 0.0, z_start_mm),
          Ops::Units.point_mm(x_end_mm, 0.0, z_start_mm),
          Ops::Units.point_mm(x_end_mm, 0.0, z_end_mm),
          Ops::Units.point_mm(x_start_mm, 0.0, z_end_mm)
        )
        face.reverse! if face.normal.y.negative?
        face.pushpull(-thickness)

        group
      end
      private_class_method :build_member
    end
  end
end
