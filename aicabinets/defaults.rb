# frozen_string_literal: true

require 'json'

module AICabinets
  module Defaults
    module_function

    DATA_DIR = File.expand_path('data', __dir__)
    DEFAULTS_PATH = File.join(DATA_DIR, 'defaults.json')
    DEFAULT_VERSION = 1

    FRONT_OPTIONS = %w[empty doors_left doors_right doors_double].freeze
    PARTITION_MODES = %w[none even positions].freeze
    MAX_PARTITION_COUNT = 20

    PARTITIONS_FALLBACK = {
      mode: 'none',
      count: 0,
      positions_mm: [].freeze,
      panel_thickness_mm: nil
    }.freeze

    FALLBACK_MM = {
      width_mm: 600.0,
      depth_mm: 600.0,
      height_mm: 720.0,
      panel_thickness_mm: 18.0,
      toe_kick_height_mm: 100.0,
      toe_kick_depth_mm: 50.0,
      front: 'doors_double',
      shelves: 2,
      partitions: PARTITIONS_FALLBACK
    }.freeze

    RECOGNIZED_ROOT_KEYS = %w[version cabinet_base].freeze
    RECOGNIZED_KEYS = FALLBACK_MM.keys.map(&:to_s).freeze
    RECOGNIZED_PARTITION_KEYS = PARTITIONS_FALLBACK.keys.map(&:to_s).freeze

    def load_mm
      raw = read_defaults_file(DEFAULTS_PATH)
      sanitized = sanitize_defaults(raw)
      canonicalize(sanitized)
    rescue StandardError => error
      warn("AI Cabinets: defaults load failed (#{error.message}); using built-in fallbacks.")
      deep_dup(FALLBACK_MM)
    end

    def read_defaults_file(path)
      return nil unless path

      unless File.file?(path)
        warn("AI Cabinets: defaults file not found (#{path}); using built-in fallbacks.")
        return nil
      end

      content = File.read(path, mode: 'r:BOM|UTF-8')
      JSON.parse(content)
    rescue JSON::ParserError => error
      warn("AI Cabinets: defaults JSON parse error (#{error.message}); using built-in fallbacks.")
      nil
    rescue StandardError => error
      warn("AI Cabinets: defaults file read error (#{error.message}); using built-in fallbacks.")
      nil
    end
    private_class_method :read_defaults_file

    def sanitize_defaults(raw)
      return deep_dup(FALLBACK_MM) if raw.nil?

      unless raw.is_a?(Hash)
        warn('AI Cabinets: defaults root must be an object; using built-in fallbacks.')
        return deep_dup(FALLBACK_MM)
      end

      warn_unknown_keys(raw, RECOGNIZED_ROOT_KEYS, 'defaults root')

      version = sanitize_version(raw['version'])
      if version != DEFAULT_VERSION
        warn("AI Cabinets: defaults version #{version} is not supported; using built-in fallbacks.")
        return deep_dup(FALLBACK_MM)
      end

      base_raw = raw['cabinet_base']
      unless base_raw.is_a?(Hash)
        warn('AI Cabinets: defaults cabinet_base must be an object; using built-in fallbacks.')
        return deep_dup(FALLBACK_MM)
      end

      sanitize_cabinet_base(base_raw)
    end
    private_class_method :sanitize_defaults

    def sanitize_cabinet_base(raw)
      warn_unknown_keys(raw, RECOGNIZED_KEYS, 'defaults.cabinet_base')

      FALLBACK_MM.each_with_object({}) do |(key, fallback), result|
        label = "cabinet_base.#{key}"

        result[key] =
          case key
          when :front
            sanitize_enum_field(label, raw[key.to_s], FRONT_OPTIONS, fallback)
          when :shelves
            sanitize_integer_field(label, raw[key.to_s], fallback, min: 0, max: 20)
          when :partitions
            sanitize_partitions(raw[key.to_s])
          else
            sanitize_numeric_field(label, raw[key.to_s], fallback)
          end
      end
    end
    private_class_method :sanitize_cabinet_base

    def sanitize_partitions(raw)
      unless raw.is_a?(Hash)
        warn('AI Cabinets: defaults cabinet_base.partitions must be an object; using built-in fallbacks.')
        return deep_dup(PARTITIONS_FALLBACK)
      end

      warn_unknown_keys(raw, RECOGNIZED_PARTITION_KEYS, 'defaults.cabinet_base.partitions')

      sanitized = {}

      mode = sanitize_enum_field(
        'cabinet_base.partitions.mode',
        raw['mode'],
        PARTITION_MODES,
        PARTITIONS_FALLBACK[:mode]
      )
      sanitized[:mode] = mode

      sanitized[:count] = sanitize_integer_field(
        'cabinet_base.partitions.count',
        raw['count'],
        PARTITIONS_FALLBACK[:count],
        min: 0,
        max: MAX_PARTITION_COUNT
      )

      sanitized[:panel_thickness_mm] = sanitize_optional_numeric_field(
        'cabinet_base.partitions.panel_thickness_mm',
        raw['panel_thickness_mm'],
        PARTITIONS_FALLBACK[:panel_thickness_mm]
      )

      sanitized[:positions_mm] =
        if mode == 'positions'
          sanitize_positions(raw['positions_mm'])
        else
          []
        end

      canonicalize_partitions(sanitized)
    end
    private_class_method :sanitize_partitions

    def sanitize_positions(raw)
      unless raw.is_a?(Array)
        warn('AI Cabinets: defaults cabinet_base.partitions.positions_mm must be an array; using built-in fallbacks.')
        return PARTITIONS_FALLBACK[:positions_mm].dup
      end

      values = []
      raw.each_with_index do |value, index|
        numeric = parse_numeric(value)
        unless numeric
          warn("AI Cabinets: defaults cabinet_base.partitions.positions_mm[#{index}] must be a non-negative number; discarding positions.")
          return PARTITIONS_FALLBACK[:positions_mm].dup
        end

        if numeric.negative?
          warn("AI Cabinets: defaults cabinet_base.partitions.positions_mm[#{index}] cannot be negative; discarding positions.")
          return PARTITIONS_FALLBACK[:positions_mm].dup
        end

        values << numeric
      end

      if values.empty?
        warn('AI Cabinets: defaults cabinet_base.partitions.positions_mm is empty; using built-in fallbacks.')
        return PARTITIONS_FALLBACK[:positions_mm].dup
      end

      values
    end
    private_class_method :sanitize_positions

    def sanitize_version(value)
      numeric = parse_numeric(value)
      if numeric && numeric >= 0 && numeric.round == numeric
        numeric.round
      else
        warn("AI Cabinets: defaults version must be a non-negative integer; using #{DEFAULT_VERSION}.")
        DEFAULT_VERSION
      end
    end
    private_class_method :sanitize_version

    def sanitize_numeric_field(label, value, fallback)
      numeric = parse_numeric(value)
      unless numeric
        warn("AI Cabinets: defaults #{label} must be a non-negative number; using #{fallback}.")
        return fallback
      end

      if numeric.negative?
        warn("AI Cabinets: defaults #{label} cannot be negative; using #{fallback}.")
        return fallback
      end

      numeric
    end
    private_class_method :sanitize_numeric_field

    def sanitize_optional_numeric_field(label, value, fallback)
      return fallback if value.nil?

      numeric = parse_numeric(value)
      unless numeric
        warn("AI Cabinets: defaults #{label} must be a non-negative number or null; using #{fallback || 'nil'}.")
        return fallback
      end

      if numeric.negative?
        warn("AI Cabinets: defaults #{label} cannot be negative; using #{fallback || 'nil'}.")
        return fallback
      end

      numeric
    end
    private_class_method :sanitize_optional_numeric_field

    def sanitize_integer_field(label, value, fallback, min:, max: nil)
      numeric = parse_numeric(value)
      unless numeric
        warn("AI Cabinets: defaults #{label} must be a non-negative integer; using #{fallback}.")
        return fallback
      end

      integer = numeric.round
      if integer < min || (max && integer > max)
        warn("AI Cabinets: defaults #{label} out of range; using #{fallback}.")
        return fallback
      end

      integer
    end
    private_class_method :sanitize_integer_field

    def sanitize_enum_field(label, value, allowed, fallback)
      if value.is_a?(String)
        normalized = value.strip
        return normalized if allowed.include?(normalized)
      end

      warn("AI Cabinets: defaults #{label} must be one of #{allowed.join(', ')}; using #{fallback}.")
      fallback
    end
    private_class_method :sanitize_enum_field

    def warn_unknown_keys(raw, known_keys, label)
      raw.each_key do |key|
        next if known_keys.include?(key.to_s)

        warn("AI Cabinets: ignoring unknown #{label} key '#{key}'.")
      end
    end
    private_class_method :warn_unknown_keys

    def canonicalize(sanitized)
      result = {}
      FALLBACK_MM.each_key do |key|
        value = sanitized[key]
        value = FALLBACK_MM[key] if value.nil? && key != :partitions
        result[key] =
          if key == :partitions
            canonicalize_partitions(value)
          else
            deep_dup(value)
          end
      end
      result
    end
    private_class_method :canonicalize

    def canonicalize_partitions(value)
      raw = value.is_a?(Hash) ? value : {}
      result = {}

      PARTITIONS_FALLBACK.each_key do |key|
        current = raw.fetch(key, PARTITIONS_FALLBACK[key])
        result[key] =
          if key == :positions_mm
            current.is_a?(Array) ? current.map { |value| value.to_f } : PARTITIONS_FALLBACK[:positions_mm].dup
          else
            deep_dup(current)
          end
      end

      result[:positions_mm] = result[:positions_mm].map { |value| value.to_f }
      result[:mode] = PARTITIONS_FALLBACK[:mode] unless PARTITION_MODES.include?(result[:mode])
      result
    end
    private_class_method :canonicalize_partitions

    def parse_numeric(value)
      case value
      when Numeric
        return value.to_f if value.finite?
      when String
        stripped = value.strip
        return nil if stripped.empty?
        numeric = Float(stripped)
        return numeric if numeric.finite?
      end
      nil
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :parse_numeric

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
    private_class_method :deep_dup
  end
end
