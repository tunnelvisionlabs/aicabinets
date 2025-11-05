# frozen_string_literal: true

module AICabinets
  module ParamsSanitizer
    module_function

    FRONT_OPTIONS = %w[empty doors_left doors_right doors_double].freeze
    DEFAULT_DOOR_MODE = 'doors_double'
    DEFAULT_SHELF_COUNT = 0
    PARTITION_MODES = %w[none vertical horizontal].freeze
    DEFAULT_PARTITION_MODE = 'none'
    BAY_MODES = %w[fronts_shelves subpartitions].freeze
    DEFAULT_BAY_MODE = 'fronts_shelves'

    DEFAULT_PARTITIONS = {
      mode: 'none',
      count: 0,
      positions_mm: [],
      panel_thickness_mm: nil,
      bays: [].freeze
    }.freeze

    def sanitize!(params_mm, global_defaults: nil)
      return params_mm unless params_mm.is_a?(Hash)

      defaults = defaults_source(global_defaults) || params_mm
      params_mm[:partition_mode] = sanitize_partition_mode(params_mm, defaults)
      params_mm.delete('partition_mode')
      partitions = sanitize_partitions_container(params_mm, defaults)
      partitions[:bays] = sanitize_bays_array(partitions[:bays], partitions[:count], defaults)
      params_mm[:partitions] = partitions
      params_mm.delete('partitions')
      params_mm
    end

    def sanitize_partitions_container(params_mm, defaults)
      raw = params_mm[:partitions] || params_mm['partitions']
      partitions =
        if raw.is_a?(Hash)
          symbolize_keys(raw)
        else
          deep_dup(default_partitions(defaults))
        end

      partitions[:count] = raw_count(raw, partitions)
      partitions
    end
    private_class_method :sanitize_partitions_container

    def raw_count(raw, partitions)
      value =
        if raw.is_a?(Hash)
          raw[:count] || raw['count']
        else
          partitions[:count]
        end
      coerce_non_negative_integer(value) || 0
    end
    private_class_method :raw_count

    def sanitize_bays_array(raw_bays, count, defaults)
      template = default_bay(defaults)
      bays =
        if raw_bays.is_a?(Array)
          raw_bays.map { |bay| sanitize_bay(bay, template) }
        else
          []
        end

      desired = count.to_i + 1
      bays = bays.first(desired)
      while bays.length < desired
        bays << deep_dup(template)
      end

      bays
    end
    private_class_method :sanitize_bays_array

    def sanitize_bay(bay, template)
      return deep_dup(template) unless bay.is_a?(Hash)

      sanitized = deep_dup(template)

      sanitized[:mode] = sanitize_bay_mode(bay[:mode] || bay['mode'], sanitized[:mode])
      sanitized[:fronts_shelves_state] =
        sanitize_fronts_shelves_state(bay, sanitized[:fronts_shelves_state])
      sanitized[:shelf_count] = sanitized[:fronts_shelves_state][:shelf_count]
      sanitized[:door_mode] = sanitized[:fronts_shelves_state][:door_mode]
      sanitized[:subpartitions_state] =
        sanitize_subpartitions_state(bay[:subpartitions_state] || bay['subpartitions_state'],
                                     sanitized[:subpartitions_state])

      sanitized
    end
    private_class_method :sanitize_bay

    def sanitize_door_mode(value)
      candidate =
        case value
        when Symbol
          value.to_s
        when String
          value.strip
        end

      FRONT_OPTIONS.include?(candidate) ? candidate : nil
    end
    private_class_method :sanitize_door_mode

    def default_bay(defaults)
      fronts = {
        shelf_count: default_shelf_count(defaults),
        door_mode: default_door_mode(defaults)
      }

      {
        mode: DEFAULT_BAY_MODE,
        shelf_count: fronts[:shelf_count],
        door_mode: fronts[:door_mode],
        fronts_shelves_state: fronts,
        subpartitions_state: { count: 0 }
      }
    end
    private_class_method :default_bay

    def sanitize_bay_mode(value, fallback)
      return fallback unless value.respond_to?(:to_s)

      candidate = value.to_s.strip.downcase
      return fallback if candidate.empty?

      if BAY_MODES.include?(candidate)
        candidate
      else
        warn("AI Cabinets: Unknown bay mode '#{value}'; falling back to #{fallback}.")
        fallback
      end
    end
    private_class_method :sanitize_bay_mode

    def sanitize_fronts_shelves_state(bay, template_state)
      sanitized = template_state.is_a?(Hash) ? deep_dup(template_state) : { shelf_count: 0, door_mode: nil }
      state = bay[:fronts_shelves_state] || bay['fronts_shelves_state']

      if state.is_a?(Hash)
        shelf_value = state[:shelf_count] || state['shelf_count']
        shelf_count = coerce_non_negative_integer(shelf_value)
        sanitized[:shelf_count] = shelf_count unless shelf_count.nil?

        if state.key?(:door_mode) || state.key?('door_mode')
          door_value = state[:door_mode] || state['door_mode']
          sanitized[:door_mode] = sanitize_bay_door_mode(door_value)
        end
      end

      if bay.key?(:shelf_count) || bay.key?('shelf_count')
        fallback_shelf = coerce_non_negative_integer(bay[:shelf_count] || bay['shelf_count'])
        sanitized[:shelf_count] = fallback_shelf unless fallback_shelf.nil?
      end

      if bay.key?(:door_mode) || bay.key?('door_mode')
        sanitized[:door_mode] = sanitize_bay_door_mode(bay[:door_mode] || bay['door_mode'])
      end

      sanitized
    end
    private_class_method :sanitize_fronts_shelves_state

    def sanitize_bay_door_mode(value)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty? || text.casecmp('none').zero?

      sanitize_door_mode(text)
    end
    private_class_method :sanitize_bay_door_mode

    def sanitize_subpartitions_state(raw_state, template_state)
      sanitized = template_state.is_a?(Hash) ? deep_dup(template_state) : { count: 0 }
      state = raw_state.is_a?(Hash) ? raw_state : {}
      count_value = state[:count] || state['count']
      count = coerce_non_negative_integer(count_value)
      sanitized[:count] = count unless count.nil?
      sanitized
    end
    private_class_method :sanitize_subpartitions_state

    def default_shelf_count(defaults)
      value = fetch_value(defaults, :shelves)
      count = coerce_non_negative_integer(value)
      count.nil? ? DEFAULT_SHELF_COUNT : count
    end
    private_class_method :default_shelf_count

    def default_door_mode(defaults)
      value = fetch_value(defaults, :front)
      sanitize_door_mode(value) || DEFAULT_DOOR_MODE
    end
    private_class_method :default_door_mode

    def fetch_value(container, key)
      return nil unless container.is_a?(Hash)

      container[key] || container[key.to_s]
    end
    private_class_method :fetch_value

    def sanitize_partition_mode(params_mm, defaults)
      raw = fetch_value(params_mm, :partition_mode)
      candidate = normalize_partition_mode(raw)
      return candidate if candidate

      fallback = fetch_value(defaults, :partition_mode)
      normalize_partition_mode(fallback) || DEFAULT_PARTITION_MODE
    end
    private_class_method :sanitize_partition_mode

    def default_partitions(defaults)
      value = fetch_value(defaults, :partitions)
      return DEFAULT_PARTITIONS unless value.is_a?(Hash)

      symbolize_keys(value)
    end
    private_class_method :default_partitions

    def defaults_source(global_defaults)
      return symbolize_keys(global_defaults) if global_defaults.is_a?(Hash)
    rescue StandardError
      nil
    end
    private_class_method :defaults_source

    def normalize_partition_mode(value)
      return nil if value.nil?

      mode =
        case value
        when Symbol
          value.to_s
        when String
          value.strip.downcase
        else
          nil
        end

      return nil if mode.nil? || mode.empty?

      PARTITION_MODES.include?(mode) ? mode : nil
    rescue StandardError
      nil
    end
    private_class_method :normalize_partition_mode

    def coerce_non_negative_integer(value)
      return nil if value.nil?

      integer =
        case value
        when Integer
          value
        when Numeric
          value.finite? ? value.round : nil
        when String
          Integer(value, 10)
        else
          nil
        end
      return nil if integer.nil? || integer.negative?

      integer
    rescue ArgumentError
      nil
    end
    private_class_method :coerce_non_negative_integer

    def symbolize_keys(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), memo|
        memo[key.is_a?(String) ? key.to_sym : key] = value
      end
    end
    private_class_method :symbolize_keys

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
