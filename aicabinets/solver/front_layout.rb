# frozen_string_literal: true

require 'aicabinets/face_frame'

module AICabinets
  module Solver
    module FrontLayout
      module_function

      ROUND_PRECISION_MM = 0.1
      SCHEMA_VERSION = 1
      MIN_DOOR_WIDTH_MM = 200.0
      MIN_DRAWER_FACE_HEIGHT_MM = 120.0

      # Deterministically split the opening into fronts using closed-form math so
      # widths/heights and reveal gaps recombine after rounding to 0.1 mm. The
      # solver keeps all math in millimeters and distributes rounding residue to
      # the outermost elements for stability.
      def solve(opening_mm:, params:)
        opening = normalize_opening(opening_mm)
        return failure('opening_mm must be a Hash with numeric :w and :h', opening_mm) unless opening

        face_frame = normalize_face_frame(params)
        preset = extract_preset(face_frame)
        reveal_mm = face_frame[:reveal_mm].to_f
        overlay_mm = face_frame[:overlay_mm].to_f

        layout_result =
          case preset[:kind]
          when 'double_doors'
            split_double_doors(opening, reveal_mm: reveal_mm, overlay_mm: overlay_mm)
          when 'drawer_stack'
            split_drawer_stack(opening, preset[:drawers], face_frame, reveal_mm: reveal_mm, overlay_mm: overlay_mm)
          else
            { fronts: [], mid_members: empty_mid_members, warnings: ["Unsupported layout preset: #{preset[:kind]}"] }
          end

        front_layout = {
          preset: preset,
          fronts: layout_result[:fronts],
          mid_members: layout_result[:mid_members],
          meta: {
            reveal_mm: round_mm(reveal_mm),
            overlay_mm: round_mm(overlay_mm),
            schema_version: SCHEMA_VERSION
          }
        }

        {
          front_layout: front_layout,
          warnings: Array(layout_result[:warnings]).compact
        }
      end

      def normalize_opening(opening_mm)
        return nil unless opening_mm.is_a?(Hash)

        x = numeric(opening_mm[:x] || opening_mm['x']) || 0.0
        z = numeric(opening_mm[:z] || opening_mm['z']) || 0.0
        w = numeric(opening_mm[:w] || opening_mm['w'])
        h = numeric(opening_mm[:h] || opening_mm['h'])
        return nil unless w && h
        return nil unless w.positive? && h.positive?

        { x: w >= 0 ? x.to_f : 0.0, z: z.to_f, w: w.to_f, h: h.to_f }
      end
      private_class_method :normalize_opening

      def normalize_face_frame(params)
        defaults = AICabinets::FaceFrame.defaults_mm
        face_frame_raw = params.is_a?(Hash) ? (params[:face_frame] || params['face_frame']) : nil
        normalized, = AICabinets::FaceFrame.normalize(face_frame_raw, defaults: defaults)
        normalized
      end
      private_class_method :normalize_face_frame

      def extract_preset(face_frame)
        layout = face_frame[:layout].is_a?(Array) ? face_frame[:layout] : AICabinets::FaceFrame::DEFAULT_LAYOUT
        entry = layout.first || { kind: 'double_doors' }
        kind = entry[:kind] || entry['kind'] || 'double_doors'
        drawers = entry[:drawers] || entry['drawers']

        preset = { kind: kind }
        preset[:drawers] = Integer(drawers) if kind == 'drawer_stack' && drawers
        preset
      rescue ArgumentError, TypeError
        { kind: 'drawer_stack', drawers: 1 }
      end
      private_class_method :extract_preset

      def split_double_doors(opening, reveal_mm:, overlay_mm:)
        gap_count = 3.0
        clear_width_total = opening[:w] - (reveal_mm * gap_count)
        clear_height_total = opening[:h] - (reveal_mm * 2.0)

        if clear_width_total <= 0.0 || clear_height_total <= 0.0
          warning = format(
            'Opening too small for double doors after reveals (w: %.1f mm, h: %.1f mm)',
            clear_width_total,
            clear_height_total
          )
          return { fronts: [], mid_members: empty_mid_members, warnings: [warning] }
        end

        widths = distribute_rounding(Array.new(2, clear_width_total / 2.0), target_total: clear_width_total)
        clear_height = round_mm(clear_height_total)

        warnings = []
        widths.each do |width|
          warnings << format('Minimum door width %.1f mm not met (%.1f mm)', MIN_DOOR_WIDTH_MM, width) if width < MIN_DOOR_WIDTH_MM
        end

        fronts = if warnings.any?
                   []
                 else
                   build_doors(widths, clear_height, reveal_mm, overlay_mm)
                 end

        { fronts: fronts, mid_members: empty_mid_members, warnings: warnings }
      end
      private_class_method :split_double_doors

      # Builds equal-width doors. Meeting edges do not receive overlay; frame
      # edges extend outward by the overlay amount while preserving reveal
      # clearances inside the opening.
      def build_doors(widths, clear_height, reveal_mm, overlay_mm)
        z_clear = reveal_mm
        z = z_clear - overlay_mm
        height = clear_height + (overlay_mm * 2.0)

        left_width, right_width = widths

        left_x_clear = reveal_mm
        right_x_clear = reveal_mm + left_width + reveal_mm

        left_bbox = {
          kind: 'door',
          bbox_mm: {
            x: round_mm(left_x_clear - overlay_mm),
            z: round_mm(z),
            w: round_mm(left_width + overlay_mm),
            h: round_mm(height)
          },
          hinge_hint: 'left'
        }

        right_bbox = {
          kind: 'door',
          bbox_mm: {
            x: round_mm(right_x_clear),
            z: round_mm(z),
            w: round_mm(right_width + overlay_mm),
            h: round_mm(height)
          },
          hinge_hint: 'right'
        }

        [left_bbox, right_bbox]
      end
      private_class_method :build_doors

      def split_drawer_stack(opening, drawer_count, face_frame, reveal_mm:, overlay_mm:)
        drawers = [drawer_count.to_i, 1].max
        clear_width = opening[:w] - (reveal_mm * 2.0)
        clear_height_total = opening[:h] - (reveal_mm * (drawers + 1))

        if clear_width <= 0.0 || clear_height_total <= 0.0
          warning = format(
            'Opening too small for drawer stack after reveals (w: %.1f mm, h: %.1f mm)',
            clear_width,
            clear_height_total
          )
          return { fronts: [], mid_members: empty_mid_members, warnings: [warning] }
        end

        clear_heights = distribute_rounding(Array.new(drawers, clear_height_total / drawers), target_total: clear_height_total)

        warnings = []
        clear_heights.each do |height|
          warnings << format('Minimum drawer face height %.1f mm not met (%.1f mm)', MIN_DRAWER_FACE_HEIGHT_MM, height) if height < MIN_DRAWER_FACE_HEIGHT_MM
        end

        fronts = if warnings.any?
                   []
                 else
                   build_drawers(clear_width, clear_heights, reveal_mm, overlay_mm)
                 end

        mid_members = build_mid_members_for_drawers(drawers, reveal_mm, clear_heights, face_frame)

        { fronts: fronts, mid_members: mid_members, warnings: warnings }
      end
      private_class_method :split_drawer_stack

      # Builds a vertical drawer stack. Frame-adjacent edges extend outward by
      # overlay_mm while inter-drawer gaps stay at the reveal thickness.
      def build_drawers(clear_width, clear_heights, reveal_mm, overlay_mm)
        x_clear = reveal_mm
        bbox_width = clear_width + (2.0 * overlay_mm)
        z_cursor = reveal_mm

        clear_heights.each_with_index.map do |clear_height, index|
          bottom_overlay = index.zero? ? overlay_mm : 0.0
          top_overlay = index == clear_heights.length - 1 ? overlay_mm : 0.0

          z = z_cursor - bottom_overlay
          height = clear_height + bottom_overlay + top_overlay

          front = {
            kind: 'drawer',
            bbox_mm: {
              x: round_mm(x_clear - overlay_mm),
              z: round_mm(z),
              w: round_mm(bbox_width),
              h: round_mm(height)
            }
          }

          z_cursor += clear_height + reveal_mm
          front
        end
      end
      private_class_method :build_drawers

      def build_mid_members_for_drawers(drawer_count, reveal_mm, clear_heights, face_frame)
        return empty_mid_members if drawer_count <= 1

        mid_rail_mm = face_frame[:mid_rail_mm].to_f
        return empty_mid_members unless mid_rail_mm.positive?

        z_cursor = reveal_mm
        mid_rails = []

        clear_heights.each_with_index do |clear_height, index|
          z_cursor += clear_height
          break if index == clear_heights.length - 1

          gap_center = z_cursor + (reveal_mm / 2.0)
          mid_rails << { z: round_mm(gap_center) }
          z_cursor += reveal_mm
        end

        { mid_stiles: [], mid_rails: mid_rails }
      end
      private_class_method :build_mid_members_for_drawers

      def empty_mid_members
        { mid_stiles: [], mid_rails: [] }
      end
      private_class_method :empty_mid_members

      def numeric(value)
        case value
        when Numeric
          return nil unless value.finite?

          value.to_f
        when String
          stripped = value.strip
          return nil if stripped.empty?

          Float(stripped)
        end
      rescue ArgumentError, TypeError
        nil
      end
      private_class_method :numeric

      def round_mm(value)
        (value.to_f / ROUND_PRECISION_MM).round * ROUND_PRECISION_MM
      end
      private_class_method :round_mm

      def distribute_rounding(values, target_total:, precision: ROUND_PRECISION_MM)
        scale = (1.0 / precision).round
        scaled_values = values.map { |value| (value * scale).round }
        scaled_target = (target_total * scale).round
        diff = scaled_target - scaled_values.sum

        adjust_indices = values.each_index.to_a
        adjust_indices.reverse! if diff.negative?

        diff.abs.times do |index|
          target_index = adjust_indices[index % adjust_indices.length]
          scaled_values[target_index] += diff.positive? ? 1 : -1
        end

        scaled_values.map { |value| value / scale.to_f }
      end
      private_class_method :distribute_rounding

      def failure(message, opening_mm)
        {
          front_layout: {
            preset: { kind: 'double_doors' },
            fronts: [],
            mid_members: empty_mid_members,
            meta: { reveal_mm: 0.0, overlay_mm: 0.0, schema_version: SCHEMA_VERSION }
          },
          warnings: [format('%s (got: %s)', message, opening_mm.inspect)]
        }
      end
      private_class_method :failure
    end
  end
end
