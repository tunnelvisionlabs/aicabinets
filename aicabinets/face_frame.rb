# frozen_string_literal: true

module AICabinets
  module FaceFrame
    module_function

    LAYOUT_KINDS = %w[double_doors drawer_stack].freeze
    DEFAULT_LAYOUT = [{ kind: 'double_doors' }].freeze
    DEFAULTS_MM = {
      enabled: true,
      thickness_mm: 19.0,
      stile_left_mm: 38.0,
      stile_right_mm: 38.0,
      rail_top_mm: 38.0,
      rail_bottom_mm: 38.0,
      mid_stile_mm: 0.0,
      mid_rail_mm: 0.0,
      reveal_mm: 2.0,
      overlay_mm: 12.7,
      layout: DEFAULT_LAYOUT
    }.freeze

    BOUNDS = {
      thickness_mm: 12.0..25.0,
      stile_left_mm: 25.0..76.0,
      stile_right_mm: 25.0..76.0,
      rail_top_mm: 25.0..76.0,
      rail_bottom_mm: 25.0..76.0,
      mid_stile_mm: 25.0..76.0,
      mid_rail_mm: 25.0..76.0,
      reveal_mm: 1.0..3.0,
      overlay_mm: 6.0..19.0
    }.freeze

    def defaults_mm
      deep_dup(DEFAULTS_MM)
    end

    def normalize(raw, defaults: defaults_mm)
      normalized = deep_dup(defaults || defaults_mm)
      return [normalized, []] unless raw.is_a?(Hash)

      errors = []
      enabled_value = raw.key?(:enabled) ? raw[:enabled] : raw['enabled']
      normalized[:enabled] = !!enabled_value unless enabled_value.nil?

      numeric_keys.each do |key|
        next unless raw.key?(key) || raw.key?(key.to_s)

        value = raw[key] || raw[key.to_s]
        numeric = parse_numeric(value)
        if numeric.nil?
          errors << build_error("face_frame.#{key}", 'invalid_type', 'must be a number')
          next
        end

        normalized[key] = numeric.to_f
      end

      layout_value = raw[:layout] || raw['layout']
      layout, layout_errors = normalize_layout(layout_value, defaults[:layout])
      normalized[:layout] = layout
      errors.concat(layout_errors)

      [normalized, errors]
    end

    def validate(face_frame, opening_mm: nil)
      unless face_frame.is_a?(Hash)
        return validation_result([build_error('face_frame', 'invalid_type', 'face_frame must be an object')])
      end

      enabled =
        if face_frame.key?(:enabled)
          face_frame[:enabled]
        elsif face_frame.key?('enabled')
          face_frame['enabled']
        end
      return validation_result([]) if enabled == false

      errors = []

      BOUNDS.each do |key, range|
        value = face_frame[key]
        unless value.is_a?(Numeric) && value.finite?
          errors << build_error("face_frame.#{key}", 'invalid_type', 'must be a number')
          next
        end

        next if zero_optional?(key, value)
        next if range.cover?(value)

        errors << build_error(
          "face_frame.#{key}",
          'out_of_bounds',
          format('must be between %.1f mm and %.1f mm', range.begin, range.end)
        )
      end

      errors.concat(validate_layout(face_frame[:layout]))

      if opening_mm
        layout_errors = validate_layout_with_opening(face_frame, opening_mm)
        errors.concat(layout_errors)
      end

      validation_result(errors)
    end

    def merge(defaults, overrides)
      normalized_defaults = defaults.is_a?(Hash) ? defaults : defaults_mm
      merged = deep_dup(normalized_defaults)
      return merged unless overrides.is_a?(Hash)

      sanitized, = normalize(overrides, defaults: merged)
      deep_dup(sanitized)
    end

    def migrate_params!(params, defaults:, schema_version: nil)
      params[:schema_version] ||= schema_version if schema_version

      defaults_face_frame = defaults.is_a?(Hash) ? (defaults[:face_frame] || defaults['face_frame']) : nil
      fallback_face_frame = defaults_face_frame || defaults_mm

      face_frame_raw = params[:face_frame] || params['face_frame']
      face_frame, = normalize(face_frame_raw, defaults: fallback_face_frame)
      params[:face_frame] = face_frame
      params.delete('face_frame')

      params
    end

    def build_overrides_payload(face_frame)
      return {} unless face_frame.is_a?(Hash)

      normalized, errors = normalize(face_frame, defaults: defaults_mm)
      return {} if errors.any?

      payload = {}
      payload['enabled'] = !!normalized[:enabled]

      numeric_keys.each do |key|
        payload[key.to_s] = normalized[key]
      end

      payload['layout'] = normalized[:layout].map { |entry| stringify_layout(entry) }
      payload
    end

    def deep_dup(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, element), memo| memo[key] = deep_dup(element) }
      when Array
        value.map { |element| deep_dup(element) }
      else
        value
      end
    end

    def numeric_keys
      %i[
        thickness_mm
        stile_left_mm
        stile_right_mm
        rail_top_mm
        rail_bottom_mm
        mid_stile_mm
        mid_rail_mm
        reveal_mm
        overlay_mm
      ]
    end
    private_class_method :numeric_keys

    def normalize_layout(raw, defaults_layout)
      fallback = defaults_layout.is_a?(Array) ? defaults_layout : DEFAULT_LAYOUT
      return [deep_dup(fallback), []] if raw.nil?

      unless raw.is_a?(Array)
        return [deep_dup(fallback), [build_error('face_frame.layout', 'invalid_type', 'must be an array')]]
      end

      errors = []
      normalized = raw.each_with_index.map do |entry, index|
        unless entry.is_a?(Hash)
          errors << build_error("face_frame.layout[#{index}]", 'invalid_type', 'must be an object')
          next
        end

        symbolize_keys(entry)
      end.compact

      normalized = deep_dup(fallback) if normalized.empty?
      [normalized, errors]
    end
    private_class_method :normalize_layout

    def validate_layout(layout)
      return [build_error('face_frame.layout', 'invalid_type', 'must be an array')] unless layout.is_a?(Array)

      errors = []
      layout.each_with_index do |entry, index|
        unless entry.is_a?(Hash)
          errors << build_error("face_frame.layout[#{index}]", 'invalid_type', 'must be an object')
          next
        end

        kind = entry[:kind] || entry['kind']
        unless LAYOUT_KINDS.include?(kind)
          errors << build_error(
            "face_frame.layout[#{index}].kind",
            'invalid_enum',
            "must be one of #{LAYOUT_KINDS.join(', ')}"
          )
          next
        end

        if kind == 'drawer_stack'
          drawers = entry[:drawers] || entry['drawers']
          unless drawers.is_a?(Integer) && drawers.positive?
            errors << build_error(
              "face_frame.layout[#{index}].drawers",
              'invalid_type',
              'must be a positive integer'
            )
          end
        end
      end

      errors
    end
    private_class_method :validate_layout

    def validate_layout_with_opening(face_frame, opening_mm)
      require 'aicabinets/solver/front_layout' unless defined?(AICabinets::Solver::FrontLayout)

      result = AICabinets::Solver::FrontLayout.solve(opening_mm: opening_mm, params: { face_frame: face_frame })
      warnings = Array(result[:warnings]).compact

      layout_entry = Array(face_frame[:layout]).first
      if layout_entry.is_a?(Hash)
        kind = layout_entry[:kind] || layout_entry['kind']
        if kind == 'drawer_stack'
          drawer_count = layout_entry[:drawers] || layout_entry['drawers']
          drawer_count = drawer_count.to_i
          mid_rail_mm = face_frame[:mid_rail_mm].to_f
          height_mm = opening_mm.is_a?(Hash) ? (opening_mm[:h] || opening_mm['h']) : nil
          if drawer_count > 1 && mid_rail_mm.positive? && height_mm.is_a?(Numeric)
            reveal_mm = face_frame[:reveal_mm].to_f
            available_height_mm = height_mm.to_f - (reveal_mm * (drawer_count + 1)) - (mid_rail_mm * (drawer_count - 1))
            per_drawer_height_mm = available_height_mm / drawer_count
            if per_drawer_height_mm < AICabinets::Solver::FrontLayout::MIN_DRAWER_FACE_HEIGHT_MM
              warnings << format(
                'Minimum drawer face height %.1f mm not met (%.1f mm)',
                AICabinets::Solver::FrontLayout::MIN_DRAWER_FACE_HEIGHT_MM,
                AICabinets::Solver::FrontLayout.round_mm(per_drawer_height_mm)
              )
            end
          end
        end
      end

      warnings.uniq!
      return [] if warnings.empty?

      warnings.map do |warning|
        build_error('face_frame.layout', 'layout_unfeasible', warning)
      end
    end
    private_class_method :validate_layout_with_opening

    def zero_optional?(key, value)
      %i[mid_stile_mm mid_rail_mm].include?(key) && value.to_f.zero?
    end
    private_class_method :zero_optional?

    def stringify_layout(entry)
      return entry unless entry.is_a?(Hash)

      entry.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end
    private_class_method :stringify_layout

    def parse_numeric(value)
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
    private_class_method :parse_numeric

    def symbolize_keys(value)
      return value unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, element), memo|
        memo[key.to_sym] = element
      end
    end
    private_class_method :symbolize_keys

    def build_error(field, code, message)
      { field: field, code: code, message: message }
    end
    private_class_method :build_error

    def validation_result(errors)
      { ok: errors.empty?, errors: errors }
    end
    private_class_method :validation_result
  end
end
