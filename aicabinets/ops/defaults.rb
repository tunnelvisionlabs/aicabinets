# frozen_string_literal: true

require 'json'

module AICabinets
  module Ops
    module Defaults
      module_function

      DEFAULTS_PATH = File.expand_path('../data/defaults.json', __dir__)

      SAFE_INSERT_BASE_CABINET_DEFAULTS = {
        width_mm: 600.0,
        depth_mm: 600.0,
        height_mm: 720.0,
        panel_thickness_mm: 18.0,
        toe_kick_height_mm: 100.0,
        toe_kick_depth_mm: 50.0,
        front: 'doors_double',
        shelves: 2,
        partitions: {
          mode: 'none',
          count: 0,
          positions_mm: [],
          panel_thickness_mm: nil
        }
      }.freeze

      FRONT_OPTIONS = %w[empty doors_left doors_right doors_double].freeze
      PARTITION_MODES = %w[none even positions].freeze

      # Clamps keep values within realistic cabinet construction ranges to avoid
      # surprising UI formatting or downstream geometry issues.
      LENGTH_CLAMP_MM = {
        width_mm: { min: 100.0, max: 5000.0 },
        depth_mm: { min: 100.0, max: 1500.0 },
        height_mm: { min: 100.0, max: 4000.0 },
        panel_thickness_mm: { min: 3.0, max: 100.0 },
        toe_kick_height_mm: { min: 10.0, max: 400.0 },
        toe_kick_depth_mm: { min: 10.0, max: 500.0 }
      }.freeze

      MAX_SHELVES = 20
      MAX_PARTITIONS = 20
      MAX_PARTITION_POSITION_MM = 5000.0

      def load_insert_base_cabinet
        defaults = (@insert_base_cabinet_defaults ||= load_insert_base_cabinet_once)
        deep_copy(defaults)
      end

      def load_insert_base_cabinet_once
        data = read_defaults_file
        sanitized = sanitize_insert_base_cabinet_defaults(data)
        deep_copy(sanitized)
      rescue StandardError => error
        warn_insert_base_cabinet_defaults(error)
        deep_copy(SAFE_INSERT_BASE_CABINET_DEFAULTS)
      end
      private_class_method :load_insert_base_cabinet_once

      def read_defaults_file
        unless File.file?(DEFAULTS_PATH)
          raise IOError, "Defaults file not found: #{DEFAULTS_PATH}"
        end

        content = File.read(DEFAULTS_PATH, mode: 'r:BOM|UTF-8')
        JSON.parse(content)
      end
      private_class_method :read_defaults_file

      def sanitize_insert_base_cabinet_defaults(raw)
        raise ArgumentError, 'Defaults JSON must be an object.' unless raw.is_a?(Hash)

        sanitized = {}

        SAFE_INSERT_BASE_CABINET_DEFAULTS.each_key do |key|
          next unless key.to_s.end_with?('_mm')

          sanitized[key] = coerce_length_mm(raw, key)
        end

        sanitized[:front] = coerce_front(raw['front'])
        sanitized[:shelves] = coerce_non_negative_integer(raw['shelves'], :shelves, MAX_SHELVES)
        sanitized[:partitions] = coerce_partitions(raw['partitions'])
        sanitized
      end
      private_class_method :sanitize_insert_base_cabinet_defaults

      def coerce_length_mm(raw, key)
        json_key = key.to_s
        limits = LENGTH_CLAMP_MM.fetch(key)
        value = raw.fetch(json_key) { raise ArgumentError, "Missing #{json_key}" }

        numeric = Float(value)
        raise ArgumentError, "#{json_key} must be positive" unless numeric.positive?

        clamp(numeric, limits[:min], limits[:max])
      rescue KeyError
        raise ArgumentError, "Missing #{json_key}"
      rescue TypeError
        raise ArgumentError, "#{json_key} must be numeric"
      end
      private_class_method :coerce_length_mm

      def coerce_front(value)
        front = String(value)
        return front if FRONT_OPTIONS.include?(front)

        raise ArgumentError, 'front must be one of: empty, doors_left, doors_right, doors_double'
      rescue ArgumentError, TypeError
        raise ArgumentError, 'front must be one of: empty, doors_left, doors_right, doors_double'
      end
      private_class_method :coerce_front

      def coerce_non_negative_integer(value, label, max_value)
        integer = Integer(value)
        raise ArgumentError, "#{label} must be zero or greater" if integer.negative?

        clamp(integer, 0, max_value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{label} must be a non-negative integer"
      end
      private_class_method :coerce_non_negative_integer

      def coerce_partitions(raw)
        raise ArgumentError, 'partitions must be an object' unless raw.is_a?(Hash)

        mode = String(raw['mode'])
        raise ArgumentError, 'partitions.mode must be one of: none, even, positions' unless PARTITION_MODES.include?(mode)

        count = coerce_non_negative_integer(raw['count'], 'partitions.count', MAX_PARTITIONS)
        positions = coerce_partition_positions(raw['positions_mm'])
        panel_thickness =
          if raw.key?('panel_thickness_mm') && !raw['panel_thickness_mm'].nil?
            coerce_partition_thickness(raw['panel_thickness_mm'])
          else
            nil
          end

        if mode == 'positions'
          raise ArgumentError, 'partitions.positions_mm must not be empty when mode is positions' if positions.empty?
        else
          positions = []
        end

        {
          mode: mode,
          count: count,
          positions_mm: positions,
          panel_thickness_mm: panel_thickness
        }
      end
      private_class_method :coerce_partitions

      def coerce_partition_positions(raw)
        raise ArgumentError, 'partitions.positions_mm must be an array' unless raw.is_a?(Array)

        values = raw.map do |value|
          numeric = Float(value)
          raise ArgumentError, 'partition positions must be non-negative' if numeric.negative?

          clamp(numeric, 0.0, MAX_PARTITION_POSITION_MM)
        rescue ArgumentError, TypeError
          raise ArgumentError, 'partition positions must be numeric'
        end

        values.each_cons(2) do |previous, current|
          raise ArgumentError, 'partition positions must be strictly increasing' unless current > previous
        end

        values
      end
      private_class_method :coerce_partition_positions

      def coerce_partition_thickness(raw)
        numeric = Float(raw)
        raise ArgumentError, 'partition panel thickness must be positive' unless numeric.positive?

        limits = LENGTH_CLAMP_MM.fetch(:panel_thickness_mm)
        clamp(numeric, limits[:min], limits[:max])
      rescue KeyError
        raise ArgumentError, 'partition panel thickness must be positive'
      rescue ArgumentError, TypeError
        raise ArgumentError, 'partition panel thickness must be a positive number'
      end
      private_class_method :coerce_partition_thickness

      def clamp(value, min_value, max_value)
        [[value, max_value].min, min_value].max
      end
      private_class_method :clamp

      def deep_copy(object)
        Marshal.load(Marshal.dump(object))
      end
      private_class_method :deep_copy

      def warn_insert_base_cabinet_defaults(error)
        return if @warned_insert_base_cabinet_defaults

        message = error.is_a?(StandardError) ? error.message : error.to_s
        warn(
          "AI Cabinets: using built-in Insert Base Cabinet defaults (#{message}). " \
          "Source: #{DEFAULTS_PATH}"
        )
        @warned_insert_base_cabinet_defaults = true
      end
      private_class_method :warn_insert_base_cabinet_defaults
    end
  end
end
