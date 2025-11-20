# frozen_string_literal: true

module AICabinets
  module ParamsSanitizer
    module_function

    FRONT_OPTIONS = %w[empty doors_left doors_right doors_double].freeze
    DEFAULT_DOOR_MODE = 'doors_double'
    DEFAULT_SHELF_COUNT = 0
    PARTITION_MODES = %w[none vertical horizontal].freeze
    DEFAULT_PARTITION_MODE = 'none'
    ORIENTATIONS = %w[vertical horizontal].freeze
    DEFAULT_ORIENTATION = 'vertical'
    BAY_MODES = %w[fronts_shelves subpartitions].freeze
    DEFAULT_BAY_MODE = 'fronts_shelves'

    DEFAULT_PARTITIONS = {
      mode: 'none',
      count: 0,
      orientation: DEFAULT_ORIENTATION,
      positions_mm: [],
      panel_thickness_mm: nil,
      bays: [].freeze
    }.freeze

    KNOWN_BAY_KEYS = %i[
      mode
      fronts_shelves_state
      shelf_count
      door_mode
      subpartitions_state
      subpartitions
    ].freeze

    def sanitize!(params_mm, global_defaults: nil)
      sanitized, = sanitize(params_mm, global_defaults: global_defaults)
      sanitized
    end

    def sanitize(params_mm, global_defaults: nil)
      return [params_mm, []] unless params_mm.is_a?(Hash)

      warnings = []
      defaults = defaults_source(global_defaults) || {}

      partition_mode = sanitize_partition_mode(params_mm, defaults)
      params_mm[:partition_mode] = partition_mode
      params_mm.delete('partition_mode')

      partitions = sanitize_partitions_container(params_mm, defaults, partition_mode, warnings)
      params_mm[:partitions] = partitions
      params_mm.delete('partitions')

      [params_mm, warnings]
    end

    def sanitize_partitions_container(params_mm, defaults, partition_mode, warnings)
      raw = params_mm[:partitions] || params_mm['partitions']
      defaults_partitions = default_partitions(defaults)
      sanitized = deep_dup(defaults_partitions)

      if raw.is_a?(Hash)
        symbolize_keys(raw).each do |key, value|
          sanitized[key] = value
        end
      end

      count = coerce_non_negative_integer(sanitized[:count])
      count = defaults_partitions[:count] if count.nil?
      count = 0 if partition_mode == 'none'
      count = 0 if count.nil? || count.negative?
      sanitized[:count] = count

      orientation = sanitize_partition_orientation(sanitized[:orientation], partition_mode, defaults_partitions[:orientation])
      sanitized[:orientation] = orientation

      if partition_mode == 'none'
        sanitized[:bays] = []
        return sanitized
      end

      bays = sanitize_bays_array(
        sanitized[:bays],
        sanitized[:count],
        defaults,
        orientation,
        warnings
      )
      sanitized[:bays] = bays
      sanitized[:count] = bays.length - 1

      sanitized
    end
    private_class_method :sanitize_partitions_container

    def sanitize_partition_orientation(raw_orientation, partition_mode, fallback)
      normalized = normalize_orientation(raw_orientation)

      case partition_mode
      when 'vertical'
        'vertical'
      when 'horizontal'
        'horizontal'
      else
        normalized || normalize_orientation(fallback) || DEFAULT_ORIENTATION
      end
    end
    private_class_method :sanitize_partition_orientation

    def sanitize_bays_array(raw_bays, count, defaults, parent_orientation, warnings)
      template = default_bay_for_orientation(defaults, parent_orientation)
      bays =
        if raw_bays.is_a?(Array)
          raw_bays.map do |bay|
            sanitize_bay(bay, template, defaults, parent_orientation, warnings, allow_subpartitions: true)
          end
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

    def sanitize_bay(bay, template, defaults, parent_orientation, warnings, allow_subpartitions: true)
      sanitized = deep_dup(template)

      unless bay.is_a?(Hash)
        finalize_bay_subpartitions!(sanitized, defaults, parent_orientation, warnings, allow_subpartitions)
        return sanitized
      end

      raw = symbolize_keys(bay)

      sanitized[:mode] = sanitize_bay_mode(raw[:mode], sanitized[:mode])

      sanitized[:fronts_shelves_state] =
        sanitize_fronts_shelves_state(raw, sanitized[:fronts_shelves_state])
      sanitized[:shelf_count] = sanitized[:fronts_shelves_state][:shelf_count]
      sanitized[:door_mode] = sanitized[:fronts_shelves_state][:door_mode]

      sanitized[:subpartitions_state] =
        sanitize_subpartitions_state(raw[:subpartitions_state], sanitized[:subpartitions_state])

      merge_unknown_keys!(sanitized, raw, KNOWN_BAY_KEYS)

      finalize_bay_subpartitions!(sanitized, defaults, parent_orientation, warnings, allow_subpartitions,
                                  raw[:subpartitions])

      sanitized
    end
    private_class_method :sanitize_bay

    def finalize_bay_subpartitions!(sanitized, defaults, parent_orientation, warnings, allow_subpartitions, raw_sub = nil)
      if allow_subpartitions
        sanitized[:subpartitions] =
          sanitize_subpartitions(
            raw_sub,
            sanitized[:subpartitions],
            sanitized[:subpartitions_state],
            defaults,
            parent_orientation,
            warnings
          )
        sanitized[:subpartitions_state][:count] = sanitized[:subpartitions][:count]
      else
        sanitized[:subpartitions_state] = { count: 0 } unless sanitized[:subpartitions_state].is_a?(Hash)
        sanitized[:subpartitions_state][:count] = 0
        sanitized.delete(:subpartitions)
      end
    end
    private_class_method :finalize_bay_subpartitions!

    def sanitize_subpartitions(raw_sub, template_sub, sub_state, defaults, parent_orientation, warnings)
      orientation = perpendicular_orientation(parent_orientation)
      sanitized = template_sub.is_a?(Hash) ? deep_dup(template_sub) : default_subpartitions_template(orientation)

      if raw_sub.is_a?(Hash)
        symbolize_keys(raw_sub).each do |key, value|
          sanitized[key] = value
        end
      end

      raw_orientation = normalize_orientation(sanitized[:orientation])
      sanitized[:orientation] = orientation
      if raw_orientation && raw_orientation != orientation
        message = "Sub-partitions orientation forced to #{orientation} to remain perpendicular to #{parent_orientation}."
        append_warning(warnings, message)
      end

      count = coerce_non_negative_integer(sanitized[:count])
      count ||= sub_state[:count] if sub_state.is_a?(Hash)
      count = 0 if count.nil? || count.negative?
      sanitized[:count] = count

      bays = sanitize_subpartition_bays(
        sanitized[:bays],
        sanitized[:count],
        defaults,
        orientation,
        warnings
      )
      sanitized[:bays] = bays
      sanitized[:count] = bays.length - 1

      sanitized
    end
    private_class_method :sanitize_subpartitions

    def sanitize_subpartition_bays(raw_bays, count, defaults, orientation, warnings)
      template = default_subpartition_bay(defaults, orientation)
      bays =
        if raw_bays.is_a?(Array)
          raw_bays.map do |bay|
            sanitize_bay(bay, template, defaults, orientation, warnings, allow_subpartitions: false)
          end
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
    private_class_method :sanitize_subpartition_bays

    def append_warning(warnings, message)
      warnings << message unless warnings.include?(message)
    end
    private_class_method :append_warning

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
        subpartitions_state: { count: 0 },
        subpartitions: default_subpartitions_template(perpendicular_orientation(DEFAULT_ORIENTATION))
      }
    end
    private_class_method :default_bay

    def default_bay_for_orientation(defaults, parent_orientation)
      template = deep_dup(default_bay(defaults))
      orientation = perpendicular_orientation(parent_orientation)
      template[:subpartitions][:orientation] = orientation
      template
    end
    private_class_method :default_bay_for_orientation

    def default_subpartition_bay(defaults, orientation)
      template = default_bay_for_orientation(defaults, orientation)
      template.delete(:subpartitions)
      template[:subpartitions_state] = { count: 0 }
      template
    end
    private_class_method :default_subpartition_bay

    def default_subpartitions_template(orientation)
      {
        count: 0,
        orientation: orientation,
        bays: []
      }
    end
    private_class_method :default_subpartitions_template

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
      state = bay[:fronts_shelves_state]

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

      sanitized = symbolize_keys(value)
      sanitized[:orientation] = normalize_orientation(sanitized[:orientation]) || DEFAULT_ORIENTATION
      sanitized[:count] = coerce_non_negative_integer(sanitized[:count]) || DEFAULT_PARTITIONS[:count]
      sanitized[:bays] = sanitized[:bays].is_a?(Array) ? sanitized[:bays] : []
      sanitized
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

    def normalize_orientation(value)
      return nil if value.nil?

      orientation =
        case value
        when Symbol
          value.to_s
        when String
          value.strip.downcase
        else
          nil
        end

      return nil if orientation.nil? || orientation.empty?

      ORIENTATIONS.include?(orientation) ? orientation : nil
    end
    private_class_method :normalize_orientation

    def perpendicular_orientation(value)
      orientation = normalize_orientation(value) || DEFAULT_ORIENTATION
      orientation == 'vertical' ? 'horizontal' : 'vertical'
    end
    private_class_method :perpendicular_orientation

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

    def merge_unknown_keys!(target, raw, known_keys)
      raw.each do |key, value|
        symbol = key.is_a?(String) ? key.to_sym : key
        next if known_keys.include?(symbol)

        target[symbol] = deep_dup(value)
      end
    end
    private_class_method :merge_unknown_keys!

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
