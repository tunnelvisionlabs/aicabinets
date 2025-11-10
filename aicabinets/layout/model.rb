# frozen_string_literal: true

module AICabinets
  module Layout
    module Model
      EPS_MM = 1.0e-3
      CABINET_BAY_ID = 'cabinet'

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
        partition_mode = normalize_partition_mode(params, partitions_hash)
        partitions_active = partitions_active?(partition_mode)

        bay_specs = partitions_active ? extract_bay_specs(partitions_hash) : []
        orientation = normalize_orientation(partitions_hash[:orientation])

        bay_rects, normalization_warning =
          build_bays(partitions_hash, bay_specs, outer_width_mm, outer_height_mm, orientation)

        partitions_info = build_partitions_info(
          partitions_hash,
          bay_rects,
          outer_width_mm,
          outer_height_mm,
          orientation,
          partitions_active
        )

        shelves = build_shelves(
          params,
          bay_specs,
          bay_rects,
          outer_height_mm,
          partitions_active
        )
        fronts = build_fronts(params, bay_specs, bay_rects, outer_width_mm, outer_height_mm)

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

      def build_bays(partitions, bay_specs, outer_width_mm, outer_height_mm, orientation)
        bay_count = bay_specs.length

        return [[], nil] if bay_count.zero? || outer_width_mm <= 0.0 || outer_height_mm <= 0.0

        axis_length_mm = orientation == 'horizontal' ? outer_height_mm : outer_width_mm

        spans_mm = compute_initial_spans(partitions, bay_specs, axis_length_mm, orientation)
        spans_mm = adjust_span_count(spans_mm, bay_count)
        spans_mm = sanitize_spans(spans_mm)

        spans_mm, warning = normalize_spans(spans_mm, axis_length_mm)

        rectangles = []
        cursor = 0.0
        spans_mm.each_with_index do |span_mm, index|
          bay_id = bay_identifier(bay_specs[index], index)

          if orientation == 'horizontal'
            rectangles << {
              id: bay_id,
              role: 'bay',
              x_mm: 0.0,
              y_mm: cursor,
              w_mm: outer_width_mm,
              h_mm: span_mm
            }
          else
            rectangles << {
              id: bay_id,
              role: 'bay',
              x_mm: cursor,
              y_mm: 0.0,
              w_mm: span_mm,
              h_mm: outer_height_mm
            }
          end
          cursor += span_mm
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

      def build_partitions_info(partitions_hash, bay_rects, outer_width_mm, outer_height_mm, orientation = nil,
                                partitions_active = true)
        orientation ||= normalize_orientation(partitions_hash[:orientation])
        positions_mm = if partitions_active
                         partition_positions(partitions_hash, bay_rects, orientation, outer_width_mm, outer_height_mm)
                       else
                         []
                       end

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

      def build_shelves(params, bay_specs, bay_rects, outer_height_mm, partitions_active)
        unless partitions_active && !bay_rects.empty?
          return build_cabinet_shelves(params, outer_height_mm)
        end

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

      def build_cabinet_shelves(params, outer_height_mm)
        count = extract_global_shelf_count(params)
        integer = count.to_i
        return [] if integer <= 0 || outer_height_mm <= 0.0

        bay = { y_mm: 0.0, h_mm: outer_height_mm }
        preview_shelf_positions_from_count(bay, integer).map do |position|
          { bay_id: CABINET_BAY_ID, y_mm: position }
        end
      end
      private_class_method :build_cabinet_shelves

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

      def extract_global_shelf_count(params)
        return 0 unless params.is_a?(Hash)

        if params.key?(:shelf_count)
          return normalize_count(params[:shelf_count])
        end
        if params.key?('shelf_count')
          return normalize_count(params['shelf_count'])
        end

        state = hash_or_nil(params[:fronts_shelves_state]) || hash_or_nil(params['fronts_shelves_state'])
        return 0 unless state.is_a?(Hash)

        if state.key?(:shelf_count)
          return normalize_count(state[:shelf_count])
        end
        if state.key?('shelf_count')
          return normalize_count(state['shelf_count'])
        end

        0
      end
      private_class_method :extract_global_shelf_count

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

      def build_fronts(params, bay_specs, bay_rects, outer_width_mm, outer_height_mm)
        fronts = []

        fallback_style = extract_global_door_style(params)
        fallback_available = !fallback_style.nil?

        if bay_rects.empty?
          if fallback_available && outer_width_mm.positive? && outer_height_mm.positive?
            fronts << {
              id: 'cabinet-door',
              role: 'door',
              style: fallback_style,
              x_mm: 0.0,
              y_mm: 0.0,
              w_mm: outer_width_mm,
              h_mm: outer_height_mm
            }
          end
          return fronts
        end

        bay_rects.each_with_index do |bay, index|
          spec = bay_specs[index] || {}
          style = extract_door_style(spec)
          if style.nil? && fallback_available && !door_mode_explicit?(spec)
            style = fallback_style
          end
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

      def door_mode_explicit?(spec)
        return false unless spec.is_a?(Hash)

        if spec.key?(:door_mode) || spec.key?('door_mode')
          true
        else
          state = hash_or_nil(spec[:fronts_shelves_state]) || hash_or_nil(spec['fronts_shelves_state'])
          state && (state.key?(:door_mode) || state.key?('door_mode'))
        end
      end
      private_class_method :door_mode_explicit?

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

      def extract_global_door_style(params)
        state =
          if params.is_a?(Hash)
            hash_or_nil(params[:fronts_shelves_state]) || hash_or_nil(params['fronts_shelves_state'])
          end

        door_mode = state && (state[:door_mode] || state['door_mode'])
        if door_mode.nil? && params.is_a?(Hash)
          door_mode = params[:door_mode] || params['door_mode']
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
      private_class_method :extract_global_door_style

      def compute_initial_spans(partitions, bay_specs, axis_length_mm, orientation)
        hints = spans_from_hints(bay_specs, orientation)
        return hints if hints

        mode = partitions[:mode].to_s.strip.downcase
        bay_count = bay_specs.length

        return spans_from_positions(partitions, bay_count, axis_length_mm) if mode == 'positions'

        even_spans(bay_count, axis_length_mm)
      end
      private_class_method :compute_initial_spans

      def spans_from_hints(bay_specs, orientation)
        hints = bay_specs.map do |bay|
          layout = hash_or_nil(bay[:layout]) || hash_or_nil(bay['layout'])
          next nil unless layout

          key = orientation == 'horizontal' ? :height_mm : :width_mm
          string_key = key.to_s
          length = layout[key] || layout[string_key]
          length ? dimension_mm(length) : nil
        end

        return nil if hints.compact.empty?

        hints.map { |value| value || 0.0 }
      end
      private_class_method :spans_from_hints

      def spans_from_positions(partitions, bay_count, axis_length_mm)
        positions = Array(partitions[:positions_mm])
        numeric = positions.map { |value| dimension_mm(value) }.compact
        sorted = numeric.sort
        trimmed = sorted.first([bay_count - 1, 0].max)

        boundaries = [0.0]
        trimmed.each do |position|
          clamped = clamp(position, 0.0, axis_length_mm)
          next if (clamped - boundaries.last).abs <= EPS_MM

          boundaries << clamped
        end
        boundaries << axis_length_mm unless (boundaries.last - axis_length_mm).abs <= EPS_MM

        widths = []
        boundaries.each_cons(2) do |left, right|
          widths << [right - left, 0.0].max
        end
        widths
      end
      private_class_method :spans_from_positions

      def even_spans(bay_count, axis_length_mm)
        return [] if bay_count <= 0

        width = bay_count.positive? ? axis_length_mm.to_f / bay_count : 0.0
        Array.new(bay_count, width)
      end
      private_class_method :even_spans

      def adjust_span_count(widths, bay_count)
        widths = Array(widths)
        if widths.length > bay_count
          widths.first(bay_count)
        elsif widths.length < bay_count
          widths + Array.new(bay_count - widths.length, 0.0)
        else
          widths
        end
      end
      private_class_method :adjust_span_count

      def sanitize_spans(widths)
        widths.map do |width|
          value = width.to_f
          value.negative? ? 0.0 : value
        end
      end
      private_class_method :sanitize_spans

      def normalize_spans(widths, axis_length_mm)
        sum = widths.sum
        difference = axis_length_mm - sum
        return [widths, nil] if difference.abs <= EPS_MM

        if sum <= EPS_MM
          recalculated = even_spans(widths.length, axis_length_mm)
          message = format('Normalized bay spans to sum to axis length (delta %.3f mm).', difference)
          return [recalculated, message]
        end

        scale = axis_length_mm / sum
        scaled = widths.map { |width| width * scale }
        correction = axis_length_mm - scaled.sum
        scaled[-1] = scaled[-1] + correction if scaled.any?

        message = format('Normalized bay spans to sum to axis length (delta %.3f mm).', difference)
        [scaled, message]
      end
      private_class_method :normalize_spans

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

      def normalize_partition_mode(params, partitions_hash)
        if params.is_a?(Hash)
          candidate = params[:partition_mode] || params['partition_mode']
          text = candidate.to_s.strip
          return text.downcase unless text.empty?
        end

        if partitions_hash.is_a?(Hash)
          candidate = partitions_hash[:mode] || partitions_hash['mode']
          text = candidate.to_s.strip
          return text.downcase unless text.empty?
        end

        'none'
      end
      private_class_method :normalize_partition_mode

      def partitions_active?(mode)
        mode != 'none'
      end
      private_class_method :partitions_active?

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

      def normalize_count(value)
        number = value.to_s.to_i
        number.negative? ? 0 : number
      rescue NoMethodError
        0
      end
      private_class_method :normalize_count

      def clamp(value, min_value, max_value)
        [[value, max_value].min, min_value].max
      end
      private_class_method :clamp
    end
  end
end
