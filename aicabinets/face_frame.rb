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
          errors << "face_frame.#{key} must be a number"
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

    def validate(face_frame)
      return ['face_frame must be an object'] unless face_frame.is_a?(Hash)

      errors = []

      BOUNDS.each do |key, range|
        value = face_frame[key]
        next unless value.is_a?(Numeric)
        next if zero_optional?(key, value)
        next if range.cover?(value)

        errors << format(
          'face_frame.%<field>s must be between %<min>.1f mm and %<max>.1f mm',
          field: key,
          min: range.begin,
          max: range.end
        )
      end

      layout_errors = validate_layout(face_frame[:layout])
      errors.concat(layout_errors)

      errors
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
        return [deep_dup(fallback), ['face_frame.layout must be an array']]
      end

      errors = []
      normalized = raw.each_with_index.map do |entry, index|
        unless entry.is_a?(Hash)
          errors << "face_frame.layout[#{index}] must be an object"
          next
        end

        symbolize_keys(entry)
      end.compact

      normalized = deep_dup(fallback) if normalized.empty?
      [normalized, errors]
    end
    private_class_method :normalize_layout

    def validate_layout(layout)
      return ['face_frame.layout must be an array'] unless layout.is_a?(Array)

      errors = []
      layout.each_with_index do |entry, index|
        unless entry.is_a?(Hash)
          errors << "face_frame.layout[#{index}] must be an object"
          next
        end

        kind = entry[:kind] || entry['kind']
        unless LAYOUT_KINDS.include?(kind)
          errors << "face_frame.layout[#{index}].kind must be one of #{LAYOUT_KINDS.join(', ')}"
          next
        end

        if kind == 'drawer_stack'
          drawers = entry[:drawers] || entry['drawers']
          unless drawers.is_a?(Integer) && drawers.positive?
            errors << "face_frame.layout[#{index}].drawers must be a positive integer"
          end
        end
      end

      errors
    end
    private_class_method :validate_layout

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
  end
end
