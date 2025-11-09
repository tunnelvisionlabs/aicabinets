# frozen_string_literal: true

module AICabinets
  module Layout
    module Model
      EPS_MM = 1.0e-3

      module_function

      # Builds a hash describing the cabinet's front-view layout in millimeters.
      #
      # @param params_mm [Hash] Canonical cabinet parameters expressed in mm.
      # @return [Hash] Structured layout model with outer bounds, bay rectangles,
      #   optional fronts, and warnings when normalization is applied.
      def build(params_mm)
        params = params_mm.is_a?(Hash) ? params_mm : {}

        outer_width_mm = dimension_mm(params[:width_mm])
        outer_height_mm = dimension_mm(params[:height_mm])

        bay_rects, normalization_warning = build_bays(params[:partitions], outer_width_mm, outer_height_mm)

        {
          outer: {
            w_mm: outer_width_mm,
            h_mm: outer_height_mm
          },
          bays: bay_rects,
          fronts: [],
          warnings: build_warnings(normalization_warning)
        }
      end

      def build_warnings(normalization_warning)
        warnings = []
        warnings << normalization_warning if normalization_warning
        warnings
      end
      private_class_method :build_warnings

      def build_bays(partitions, outer_width_mm, outer_height_mm)
        partitions_hash = partitions.is_a?(Hash) ? partitions : {}
        bay_specs = Array(partitions_hash[:bays]).map { |bay| bay.is_a?(Hash) ? bay.dup : {} }
        bay_count = bay_specs.length

        return [[], nil] if bay_count.zero? || outer_width_mm <= 0.0

        widths_mm = compute_initial_widths(partitions_hash, bay_specs, outer_width_mm)
        widths_mm = adjust_widths_count(widths_mm, bay_count)
        widths_mm = sanitize_widths(widths_mm)

        widths_mm, warning = normalize_widths(widths_mm, outer_width_mm)

        rectangles = []
        cursor = 0.0
        widths_mm.each_with_index do |width_mm, index|
          rectangles << {
            id: bay_identifier(bay_specs[index], index),
            role: 'bay',
            x_mm: cursor,
            y_mm: 0.0,
            w_mm: width_mm,
            h_mm: outer_height_mm
          }
          cursor += width_mm
        end

        [rectangles, warning]
      end
      private_class_method :build_bays

      def compute_initial_widths(partitions, bay_specs, outer_width_mm)
        hints = widths_from_hints(bay_specs)
        return hints if hints

        mode = partitions[:mode].to_s.strip.downcase
        bay_count = bay_specs.length

        return widths_from_positions(partitions, bay_count, outer_width_mm) if mode == 'positions'

        even_widths(bay_count, outer_width_mm)
      end
      private_class_method :compute_initial_widths

      def widths_from_hints(bay_specs)
        hints = bay_specs.map do |bay|
          layout = hash_or_nil(bay[:layout]) || hash_or_nil(bay['layout'])
          width = layout && (layout[:width_mm] || layout['width_mm'])
          width ? dimension_mm(width) : nil
        end

        return nil if hints.compact.empty?

        hints.map { |value| value || 0.0 }
      end
      private_class_method :widths_from_hints

      def widths_from_positions(partitions, bay_count, outer_width_mm)
        positions = Array(partitions[:positions_mm])
        numeric = positions.map { |value| dimension_mm(value) }.compact
        sorted = numeric.sort
        trimmed = sorted.first([bay_count - 1, 0].max)

        boundaries = [0.0]
        trimmed.each do |position|
          clamped = clamp(position, 0.0, outer_width_mm)
          next if (clamped - boundaries.last).abs <= EPS_MM

          boundaries << clamped
        end
        boundaries << outer_width_mm unless (boundaries.last - outer_width_mm).abs <= EPS_MM

        widths = []
        boundaries.each_cons(2) do |left, right|
          widths << [right - left, 0.0].max
        end
        widths
      end
      private_class_method :widths_from_positions

      def even_widths(bay_count, outer_width_mm)
        return [] if bay_count <= 0

        width = bay_count.positive? ? outer_width_mm.to_f / bay_count : 0.0
        Array.new(bay_count, width)
      end
      private_class_method :even_widths

      def adjust_widths_count(widths, bay_count)
        widths = Array(widths)
        if widths.length > bay_count
          widths.first(bay_count)
        elsif widths.length < bay_count
          widths + Array.new(bay_count - widths.length, 0.0)
        else
          widths
        end
      end
      private_class_method :adjust_widths_count

      def sanitize_widths(widths)
        widths.map do |width|
          value = width.to_f
          value.negative? ? 0.0 : value
        end
      end
      private_class_method :sanitize_widths

      def normalize_widths(widths, outer_width_mm)
        sum = widths.sum
        difference = outer_width_mm - sum
        return [widths, nil] if difference.abs <= EPS_MM

        if sum <= EPS_MM
          recalculated = even_widths(widths.length, outer_width_mm)
          message = format('Normalized bay widths to sum to outer.w_mm (delta %.3f mm).', difference)
          return [recalculated, message]
        end

        scale = outer_width_mm / sum
        scaled = widths.map { |width| width * scale }
        correction = outer_width_mm - scaled.sum
        scaled[-1] = scaled[-1] + correction if scaled.any?

        message = format('Normalized bay widths to sum to outer.w_mm (delta %.3f mm).', difference)
        [scaled, message]
      end
      private_class_method :normalize_widths

      def bay_identifier(bay_spec, index)
        id = bay_spec[:id] || bay_spec['id']
        normalized = normalize_identifier(id, index)
        return normalized unless normalized.nil?

        format('bay-%d', index + 1)
      end
      private_class_method :bay_identifier

      def normalize_identifier(identifier, index)
        case identifier
        when nil
          nil
        when String
          text = identifier.strip
          return nil if text.empty?

          text
        when Numeric
          value = identifier.to_i
          value = index + 1 if value <= 0
          format('bay-%d', value)
        else
          text = identifier.to_s.strip
          return nil if text.empty?

          text
        end
      end
      private_class_method :normalize_identifier

      def dimension_mm(value)
        return 0.0 if value.nil?

        if value.is_a?(Numeric)
          value.to_f
        else
          Float(value)
        end
      rescue ArgumentError, TypeError
        0.0
      end
      private_class_method :dimension_mm

      def hash_or_nil(value)
        value.is_a?(Hash) ? value : nil
      end
      private_class_method :hash_or_nil

      def clamp(value, min_value, max_value)
        [[value, max_value].min, min_value].max
      end
      private_class_method :clamp
    end
  end
end
