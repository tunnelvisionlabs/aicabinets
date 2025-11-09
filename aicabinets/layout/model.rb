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

        partitions_hash = partitions_to_hash(params[:partitions])
        bay_specs = extract_bay_specs(partitions_hash)

        bay_rects, normalization_warning =
          build_bays(partitions_hash, bay_specs, outer_width_mm, outer_height_mm)

        partitions_info = build_partitions_info(
          partitions_hash,
          bay_rects,
          outer_width_mm,
          outer_height_mm
        )

        shelves = build_shelves(bay_specs, bay_rects)
        fronts = build_fronts(bay_specs, bay_rects)

        {
          outer: {
            w_mm: outer_width_mm,
            h_mm: outer_height_mm
          },
          bays: bay_rects,
          partitions: partitions_info,
          shelves: shelves,
          fronts: fronts,
          warnings: build_warnings(normalization_warning)
        }
      end

      def build_warnings(normalization_warning)
        warnings = []
        warnings << normalization_warning if normalization_warning
        warnings
      end
      private_class_method :build_warnings

      def build_bays(partitions, bay_specs, outer_width_mm, outer_height_mm)
        bay_count = bay_specs.length

        return [[], nil] if bay_count.zero? || outer_width_mm <= 0.0

        widths_mm = compute_initial_widths(partitions, bay_specs, outer_width_mm)
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

      def partitions_to_hash(partitions)
        partitions.is_a?(Hash) ? partitions : {}
      end
      private_class_method :partitions_to_hash

      def extract_bay_specs(partitions_hash)
        Array(partitions_hash[:bays]).map { |bay| bay.is_a?(Hash) ? bay.dup : {} }
      end
      private_class_method :extract_bay_specs

      def build_partitions_info(partitions_hash, bay_rects, outer_width_mm, outer_height_mm)
        orientation = normalize_orientation(partitions_hash[:orientation])
        positions_mm =
          partition_positions(partitions_hash, bay_rects, orientation, outer_width_mm, outer_height_mm)

        {
          orientation: orientation,
          positions_mm: positions_mm
        }
      end
      private_class_method :build_partitions_info

      def normalize_orientation(value)
        case value.to_s.strip.downcase
        when 'horizontal'
          'horizontal'
        else
          'vertical'
        end
      end
      private_class_method :normalize_orientation

      def partition_positions(partitions_hash, bay_rects, orientation, outer_width_mm, outer_height_mm)
        explicit_positions =
          positions_from_config(partitions_hash[:positions_mm], orientation, outer_width_mm, outer_height_mm)

        return explicit_positions unless explicit_positions.empty?

        if orientation == 'vertical'
          positions_from_bays(bay_rects)
        else
          positions_from_count(partitions_hash[:count], outer_height_mm)
        end
      end
      private_class_method :partition_positions

      def positions_from_config(positions, orientation, outer_width_mm, outer_height_mm)
        axis_limit = orientation == 'horizontal' ? outer_height_mm : outer_width_mm
        numeric = Array(positions).map { |value| dimension_mm(value) }.compact
        return [] if numeric.empty?

        numeric.sort.each_with_object([]) do |value, list|
          clamped = clamp(value, 0.0, axis_limit)
          next if near_boundary?(clamped, axis_limit)
          list << clamped unless duplicate_position?(list.last, clamped)
        end
      end
      private_class_method :positions_from_config

      def positions_from_bays(bay_rects)
        return [] if bay_rects.length <= 1

        boundaries = bay_rects.each_with_index.map do |bay, index|
          next if index.zero?

          bay[:x_mm].to_f
        end

        boundaries.compact.uniq do |position|
          (position / EPS_MM).round
        end.sort
      end
      private_class_method :positions_from_bays

      def positions_from_count(count, axis_length_mm)
        integer = count.to_i
        return [] if integer <= 0 || axis_length_mm <= 0.0

        spacing = axis_length_mm.to_f / (integer + 1)
        (1..integer).map { |index| spacing * index }
      end
      private_class_method :positions_from_count

      def near_boundary?(value, axis_limit)
        value <= EPS_MM || (axis_limit - value).abs <= EPS_MM
      end
      private_class_method :near_boundary?

      def duplicate_position?(previous, current)
        return false if previous.nil?

        (current - previous).abs <= EPS_MM
      end
      private_class_method :duplicate_position?

      def build_shelves(bay_specs, bay_rects)
        shelves = []
        bay_rects.each_with_index do |bay, index|
          bay_id = bay[:id] || format('bay-%d', index + 1)
          spec = bay_specs[index] || {}

          explicit = explicit_shelf_positions(spec, bay)
          positions = if explicit.empty?
                        count = extract_shelf_count(spec)
                        preview_shelf_positions_from_count(bay, count)
                      else
                        explicit
                      end

          positions.each do |position|
            shelves << { bay_id: bay_id, y_mm: position }
          end
        end
        shelves
      end
      private_class_method :build_shelves

      def explicit_shelf_positions(spec, bay)
        candidates = []
        shelf_values = Array(spec[:shelves] || spec['shelves'])
        candidates.concat(shelf_values)

        state = hash_or_nil(spec[:fronts_shelves_state]) || hash_or_nil(spec['fronts_shelves_state'])
        state_shelves = Array(state && (state[:shelves] || state['shelves']))
        candidates.concat(state_shelves)

        candidates.flat_map do |entry|
          if entry.is_a?(Hash)
            value = entry[:y_mm] || entry['y_mm']
            normalize_shelf_position(value, bay)
          else
            normalize_shelf_position(entry, bay)
          end
        end.compact.uniq do |position|
          (position / EPS_MM).round
        end.sort
      end
      private_class_method :explicit_shelf_positions

      def normalize_shelf_position(value, bay)
        position = dimension_mm(value)
        return nil if position <= 0.0

        top = bay[:y_mm].to_f
        bottom = top + bay[:h_mm].to_f

        if position < top - EPS_MM || position > bottom + EPS_MM
          relative = position
          if relative.negative?
            position = top
          elsif relative > bay[:h_mm].to_f + EPS_MM
            position = clamp(position, top, bottom)
          else
            position = top + clamp(relative, 0.0, bay[:h_mm].to_f)
          end
        end

        clamp(position, top + EPS_MM, bottom - EPS_MM)
      end
      private_class_method :normalize_shelf_position

      def extract_shelf_count(spec)
        return spec[:shelf_count] if spec.key?(:shelf_count)
        return spec['shelf_count'] if spec.key?('shelf_count')

        state = hash_or_nil(spec[:fronts_shelves_state]) || hash_or_nil(spec['fronts_shelves_state'])
        return state[:shelf_count] if state && state.key?(:shelf_count)
        return state['shelf_count'] if state && state.key?('shelf_count')

        0
      end
      private_class_method :extract_shelf_count

      def preview_shelf_positions_from_count(bay, count)
        integer = count.to_i
        return [] if integer <= 0

        height = bay[:h_mm].to_f
        return [] if height <= 0.0

        spacing = height / (integer + 1)
        Array.new(integer) do |index|
          bay[:y_mm].to_f + (spacing * (index + 1))
        end
      end
      private_class_method :preview_shelf_positions_from_count

      def build_fronts(bay_specs, bay_rects)
        fronts = []

        bay_rects.each_with_index do |bay, index|
          spec = bay_specs[index] || {}
          style = extract_door_style(spec)
          next if style.nil?

          identifier = bay[:id] || format('bay-%d', index + 1)
          fronts << {
            id: format('%s-door', identifier),
            role: 'door',
            style: style,
            x_mm: bay[:x_mm],
            y_mm: bay[:y_mm],
            w_mm: bay[:w_mm],
            h_mm: bay[:h_mm]
          }
        end

        fronts
      end
      private_class_method :build_fronts

      def extract_door_style(spec)
        door_mode =
          if spec.key?(:door_mode) || spec.key?('door_mode')
            spec[:door_mode] || spec['door_mode']
          else
            state = hash_or_nil(spec[:fronts_shelves_state]) || hash_or_nil(spec['fronts_shelves_state'])
            state && (state[:door_mode] || state['door_mode'])
          end

        normalized = door_mode.to_s.strip
        return nil if normalized.empty?

        case normalized.downcase
        when 'doors_left', 'doors_right', 'doors_double'
          normalized.downcase
        else
          nil
        end
      end
      private_class_method :extract_door_style

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
