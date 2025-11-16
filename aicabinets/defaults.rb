# frozen_string_literal: true

require 'json'
require 'fileutils'

require 'aicabinets/params_sanitizer'
require 'aicabinets/face_frame'

module AICabinets
  module Defaults
    module_function

    DATA_DIR = File.expand_path('data', __dir__)
    USER_DIR = File.expand_path('user', __dir__)
    DEFAULTS_PATH = File.join(DATA_DIR, 'defaults.json')
    OVERRIDES_PATH = File.join(USER_DIR, 'overrides.json')
    OVERRIDES_TEMP_PATH = "#{OVERRIDES_PATH}.tmp"
    DEFAULT_VERSION = 1
    NORMALIZATION_PRECISION = 3 # store mm values with 0.001 mm precision

    FRONT_OPTIONS = %w[empty doors_left doors_right doors_double].freeze
    PARTITION_LAYOUT_MODES = %w[none even positions].freeze
    PARTITION_MODE_OPTIONS = %w[none vertical horizontal].freeze
    ORIENTATION_OPTIONS = %w[vertical horizontal].freeze
    BAY_MODES = %w[fronts_shelves subpartitions].freeze
    MAX_PARTITION_COUNT = 20

    DEFAULT_PARTITION_ORIENTATION = 'vertical'
    DEFAULT_SUBPARTITION_ORIENTATION = 'horizontal'

    BAY_FALLBACK = {
      mode: 'fronts_shelves',
      shelf_count: 0,
      door_mode: 'doors_double',
      fronts_shelves_state: {
        shelf_count: 0,
        door_mode: 'doors_double'
      }.freeze,
      subpartitions_state: {
        count: 0
      }.freeze,
      subpartitions: {
        count: 0,
        orientation: DEFAULT_SUBPARTITION_ORIENTATION,
        bays: [].freeze
      }.freeze
    }.freeze

    PARTITIONS_FALLBACK = {
      mode: 'none',
      count: 0,
      orientation: DEFAULT_PARTITION_ORIENTATION,
      positions_mm: [].freeze,
      panel_thickness_mm: nil,
      bays: [BAY_FALLBACK].freeze
    }.freeze

    FALLBACK_FACE_FRAME = AICabinets::FaceFrame.defaults_mm.freeze

    FALLBACK_MM = {
      width_mm: 600.0,
      depth_mm: 600.0,
      height_mm: 720.0,
      panel_thickness_mm: 18.0,
      toe_kick_height_mm: 100.0,
      toe_kick_depth_mm: 50.0,
      toe_kick_thickness_mm: 18.0,
      front: 'doors_double',
      partition_mode: 'none',
      shelves: 2,
      partitions: PARTITIONS_FALLBACK,
      face_frame: FALLBACK_FACE_FRAME
    }.freeze

    FALLBACK_CONSTRAINTS = {
      min_door_leaf_width_mm: 140.0
    }.freeze

    RECOGNIZED_ROOT_KEYS = %w[version cabinet_base constraints face_frame].freeze
    RECOGNIZED_KEYS = FALLBACK_MM.keys.map(&:to_s).freeze
    RECOGNIZED_PARTITION_KEYS = PARTITIONS_FALLBACK.keys.map(&:to_s).freeze
    CONSTRAINT_KEYS = FALLBACK_CONSTRAINTS.keys.map(&:to_s).freeze

    def load_mm
      raw = read_defaults_file(DEFAULTS_PATH)
      sanitized = sanitize_defaults(raw)
      canonical = canonicalize(sanitized)
      ParamsSanitizer.sanitize!(canonical, global_defaults: canonical)
    rescue StandardError => error
      warn("AI Cabinets: defaults load failed (#{error.message}); using built-in fallbacks.")
      fallback = deep_dup(FALLBACK_MM)
      ParamsSanitizer.sanitize!(fallback, global_defaults: fallback)
    end

    def load_effective_mm
      defaults = load_mm
      overrides = read_overrides_mm

      return defaults if overrides.empty?

      result = merge_defaults(defaults, overrides)
      ParamsSanitizer.sanitize!(result, global_defaults: result)
    rescue StandardError => error
      warn("AI Cabinets: effective defaults load failed (#{error.message}); using shipped defaults.")
      defaults
    end

    def save_overrides_mm(params_mm)
      payload = build_overrides_payload(params_mm)
      return false if payload.empty?

      ensure_user_dir!

      json = JSON.pretty_generate(payload)

      File.open(OVERRIDES_TEMP_PATH, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        file.write(json)
        file.flush
        file.fsync if file.respond_to?(:fsync)
      end

      FileUtils.rm_f(OVERRIDES_PATH)
      File.rename(OVERRIDES_TEMP_PATH, OVERRIDES_PATH)

      true
    rescue StandardError => error
      warn("AI Cabinets: overrides save failed (#{error.message}).")
      FileUtils.rm_f(OVERRIDES_TEMP_PATH)
      false
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

    def read_overrides_mm
      return {} unless File.file?(OVERRIDES_PATH)

      content = File.read(OVERRIDES_PATH, mode: 'r:BOM|UTF-8')
      raw = JSON.parse(content)
      sanitize_overrides(raw)
    rescue JSON::ParserError => error
      warn("AI Cabinets: overrides JSON parse error (#{error.message}); ignoring overrides.")
      {}
    rescue StandardError => error
      warn("AI Cabinets: overrides file read error (#{error.message}); ignoring overrides.")
      {}
    end
    private_class_method :read_overrides_mm

    def sanitize_overrides(raw)
      container = overrides_container(raw)
      return {} unless container

      sanitized = sanitize_overrides_body(container)

      constraints = sanitize_overrides_constraints(raw)
      sanitized[:constraints] = constraints unless constraints.empty?

      sanitized
    end
    private_class_method :sanitize_overrides

    def overrides_container(raw)
      unless raw.is_a?(Hash)
        warn('AI Cabinets: overrides root must be an object; ignoring overrides.')
        return nil
      end

      cabinet_base = raw.key?('cabinet_base') ? raw['cabinet_base'] : raw[:cabinet_base]

      if cabinet_base
        unless cabinet_base.is_a?(Hash)
          warn('AI Cabinets: overrides cabinet_base must be an object; ignoring overrides.')
          return nil
        end

        warn_unknown_keys_once(raw, ['cabinet_base', 'constraints'], 'overrides root')
        cabinet_base
      else
        warn_unknown_keys_once(raw, RECOGNIZED_KEYS + ['constraints'], 'overrides root')
        raw
      end
    end
    private_class_method :overrides_container

    def sanitize_overrides_body(raw)
      warn_unknown_keys_once(raw, RECOGNIZED_KEYS, 'overrides')

      sanitized = {}

      RECOGNIZED_KEYS.each do |key|
        next unless raw.key?(key) || raw.key?(key.to_sym)

        value = raw[key] || raw[key.to_sym]

        case key
        when 'partition_mode'
          mode = sanitize_override_enum('overrides.partition_mode', value, PARTITION_MODE_OPTIONS)
          sanitized[:partition_mode] = mode if mode
        when 'partitions'
          partitions = sanitize_overrides_partitions(value)
          sanitized[:partitions] = partitions if partitions && !partitions.empty?
        when 'face_frame'
          face_frame = sanitize_overrides_face_frame(value)
          sanitized[:face_frame] = face_frame if face_frame
        when 'front'
          front = sanitize_override_front(value)
          sanitized[:front] = front if front
        when 'shelves'
          shelves = sanitize_override_integer('overrides.shelves', value, min: 0, max: MAX_PARTITION_COUNT)
          sanitized[:shelves] = shelves if shelves
        else
          numeric = sanitize_override_numeric("overrides.#{key}", value)
          sanitized[key.to_sym] = numeric unless numeric.nil?
        end
      end

      sanitized
    end
    private_class_method :sanitize_overrides_body

    def sanitize_overrides_constraints(raw)
      return {} unless raw.is_a?(Hash)

      source = raw['constraints'] || raw[:constraints]
      return {} unless source.is_a?(Hash)

      warn_unknown_keys_once(source, CONSTRAINT_KEYS, 'overrides.constraints')

      FALLBACK_CONSTRAINTS.each_with_object({}) do |(key, fallback), result|
        string_key = key.to_s
        next unless source.key?(string_key) || source.key?(key)

        value = source[string_key] || source[key]
        result[key] = sanitize_numeric_field("overrides.constraints.#{string_key}", value, fallback)
      end
    end
    private_class_method :sanitize_overrides_constraints

    def sanitize_overrides_partitions(raw)
      unless raw.is_a?(Hash)
        warn('AI Cabinets: overrides.partitions must be an object; ignoring override.')
        return nil
      end

      warn_unknown_keys_once(raw, RECOGNIZED_PARTITION_KEYS, 'overrides.partitions')

      sanitized = {}

      RECOGNIZED_PARTITION_KEYS.each do |key|
        next unless raw.key?(key) || raw.key?(key.to_sym)

        value = raw[key] || raw[key.to_sym]

        case key
        when 'mode'
          mode = sanitize_override_enum('overrides.partitions.mode', value, PARTITION_LAYOUT_MODES)
          sanitized[:mode] = mode if mode
        when 'count'
          count = sanitize_override_integer('overrides.partitions.count', value, min: 0, max: MAX_PARTITION_COUNT)
          sanitized[:count] = count if count
        when 'orientation'
          orientation = sanitize_override_enum('overrides.partitions.orientation', value, ORIENTATION_OPTIONS)
          sanitized[:orientation] = orientation if orientation
        when 'positions_mm'
          positions = sanitize_override_positions(value)
          sanitized[:positions_mm] = positions if positions
        when 'panel_thickness_mm'
          if value.nil?
            sanitized[:panel_thickness_mm] = nil
          else
            numeric = sanitize_override_numeric('overrides.partitions.panel_thickness_mm', value)
            sanitized[:panel_thickness_mm] = numeric unless numeric.nil?
          end
        when 'bays'
          bays = sanitize_override_bays(value)
          sanitized[:bays] = bays if bays
        end
      end

      sanitized
    end
    private_class_method :sanitize_overrides_partitions

    def sanitize_overrides_face_frame(raw)
      unless raw.is_a?(Hash)
        warn('AI Cabinets: overrides.face_frame must be an object; ignoring override.')
        return nil
      end

      normalized, errors = AICabinets::FaceFrame.normalize(raw, defaults: FALLBACK_FACE_FRAME)
      errors.each { |message| warn("AI Cabinets: #{message}; ignoring face_frame override.") }

      return nil if errors.any?

      normalized
    end
    private_class_method :sanitize_overrides_face_frame

    def sanitize_override_bays(raw)
      unless raw.is_a?(Array)
        warn('AI Cabinets: overrides.partitions.bays must be an array; ignoring override.')
        return nil
      end

      raw.each_with_index.map do |element, index|
        unless element.is_a?(Hash)
          warn("AI Cabinets: overrides.partitions.bays[#{index}] must be an object; ignoring override.")
          return nil
        end

        entry = deep_dup(BAY_FALLBACK)
        entry[:fronts_shelves_state] = deep_dup(entry[:fronts_shelves_state])
        entry[:subpartitions_state] = deep_dup(entry[:subpartitions_state])
        entry[:subpartitions] = deep_dup(entry[:subpartitions])

        mode_value = element['mode'] || element[:mode]
        sanitized_mode = sanitize_override_bay_mode(
          "overrides.partitions.bays[#{index}].mode",
          mode_value
        )
        entry[:mode] = sanitized_mode if sanitized_mode

        nested_fronts = element['fronts_shelves_state'] || element[:fronts_shelves_state]
        if nested_fronts.is_a?(Hash)
          nested_shelf = sanitize_override_integer(
            "overrides.partitions.bays[#{index}].fronts_shelves_state.shelf_count",
            nested_fronts['shelf_count'] || nested_fronts[:shelf_count],
            min: 0,
            max: MAX_PARTITION_COUNT
          )
          entry[:fronts_shelves_state][:shelf_count] = nested_shelf unless nested_shelf.nil?

          if nested_fronts.key?('door_mode') || nested_fronts.key?(:door_mode)
            nested_door = sanitize_override_door(
              "overrides.partitions.bays[#{index}].fronts_shelves_state.door_mode",
              nested_fronts['door_mode'] || nested_fronts[:door_mode]
            )
            entry[:fronts_shelves_state][:door_mode] = nested_door
          end
        end

        shelf = sanitize_override_integer(
          "overrides.partitions.bays[#{index}].shelf_count",
          element['shelf_count'] || element[:shelf_count],
          min: 0,
          max: MAX_PARTITION_COUNT
        )
        entry[:fronts_shelves_state][:shelf_count] = shelf unless shelf.nil?
        entry[:shelf_count] = entry[:fronts_shelves_state][:shelf_count]

        if element.key?('door_mode') || element.key?(:door_mode)
          door = sanitize_override_door(
            "overrides.partitions.bays[#{index}].door_mode",
            element['door_mode'] || element[:door_mode]
          )
          entry[:fronts_shelves_state][:door_mode] = door
          entry[:door_mode] = door
        else
          entry[:door_mode] = entry[:fronts_shelves_state][:door_mode]
        end

        sub_state = element['subpartitions_state'] || element[:subpartitions_state]
        if sub_state.is_a?(Hash)
          sub_count = sanitize_override_integer(
            "overrides.partitions.bays[#{index}].subpartitions_state.count",
            sub_state['count'] || sub_state[:count],
            min: 0,
            max: MAX_PARTITION_COUNT
          )
          entry[:subpartitions_state][:count] = sub_count unless sub_count.nil?
        end

        sub_container = element['subpartitions'] || element[:subpartitions]
        if sub_container.is_a?(Hash)
          sub_count = sanitize_override_integer(
            "overrides.partitions.bays[#{index}].subpartitions.count",
            sub_container['count'] || sub_container[:count],
            min: 0,
            max: MAX_PARTITION_COUNT
          )
          entry[:subpartitions][:count] = sub_count unless sub_count.nil?

          orientation = sanitize_override_enum(
            "overrides.partitions.bays[#{index}].subpartitions.orientation",
            sub_container['orientation'] || sub_container[:orientation],
            ORIENTATION_OPTIONS
          )
          entry[:subpartitions][:orientation] = orientation if orientation

          bays_value = sub_container['bays'] || sub_container[:bays]
          entry[:subpartitions][:bays] =
            if bays_value.is_a?(Array)
              bays_value.each_with_index.map do |sub_element, sub_index|
                unless sub_element.is_a?(Hash)
                  warn("AI Cabinets: overrides.partitions.bays[#{index}].subpartitions.bays[#{sub_index}] must be an object; ignoring entry.")
                  next
                end

                deep_dup(sub_element)
              end.compact
            else
              []
            end
        end

        entry
      end
    end
    private_class_method :sanitize_override_bays

    def sanitize_override_positions(value)
      unless value.is_a?(Array)
        warn('AI Cabinets: overrides.partitions.positions_mm must be an array; ignoring override.')
        return nil
      end

      result = []
      value.each_with_index do |element, index|
        numeric = sanitize_override_numeric("overrides.partitions.positions_mm[#{index}]", element)
        return nil unless numeric

        if numeric.negative?
          warn("AI Cabinets: overrides.partitions.positions_mm[#{index}] cannot be negative; ignoring override.")
          return nil
        end

        result << numeric
      end

      return nil if result.empty?

      result
    end
    private_class_method :sanitize_override_positions

    def sanitize_override_bay_mode(label, value)
      return nil unless value.respond_to?(:to_s)

      text = value.to_s.strip.downcase
      return nil if text.empty?

      if BAY_MODES.include?(text)
        text
      else
        warn("AI Cabinets: #{label} must be one of #{BAY_MODES.join(', ')}; ignoring override.")
        nil
      end
    end
    private_class_method :sanitize_override_bay_mode

    def sanitize_override_door(label, value)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty? || text.casecmp('none').zero?

      sanitize_override_enum(label, text, FRONT_OPTIONS)
    end
    private_class_method :sanitize_override_door

    def sanitize_override_numeric(label, value)
      numeric = parse_numeric(value)
      unless numeric
        warn("AI Cabinets: #{label} must be a non-negative number; ignoring override.")
        return nil
      end

      if numeric.negative?
        warn("AI Cabinets: #{label} cannot be negative; ignoring override.")
        return nil
      end

      numeric
    end
    private_class_method :sanitize_override_numeric

    def sanitize_override_enum(label, value, allowed)
      if value.is_a?(String)
        normalized = value.strip
        return normalized if allowed.include?(normalized)
      end

      warn("AI Cabinets: #{label} must be one of #{allowed.join(', ')}; ignoring override.")
      nil
    end
    private_class_method :sanitize_override_enum

    def sanitize_override_front(value)
      sanitize_override_enum('overrides.front', value, FRONT_OPTIONS)
    end
    private_class_method :sanitize_override_front

    def sanitize_override_integer(label, value, min:, max: nil)
      numeric = parse_numeric(value)
      unless numeric
        warn("AI Cabinets: #{label} must be a non-negative integer; ignoring override.")
        return nil
      end

      integer = numeric.round
      if integer < min || (max && integer > max)
        warn("AI Cabinets: #{label} out of range; ignoring override.")
        return nil
      end

      integer
    end
    private_class_method :sanitize_override_integer

    def warn_unknown_keys_once(raw, known_keys, label)
      unknown = raw.each_key.reject { |key| known_keys.include?(key.to_s) }
      warn("AI Cabinets: ignoring unknown #{label} key(s): #{unknown.join(', ')}.") if unknown.any?
    end
    private_class_method :warn_unknown_keys_once

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

      result = sanitize_cabinet_base(base_raw)

      face_frame_raw = raw['face_frame'] || raw[:face_frame]
      face_frame, face_errors = AICabinets::FaceFrame.normalize(face_frame_raw, defaults: FALLBACK_FACE_FRAME)
      face_errors.each do |message|
        warn("AI Cabinets: defaults #{message}; using built-in face_frame fallback value.")
      end
      validation_errors = AICabinets::FaceFrame.validate(face_frame)
      validation_errors.each do |message|
        warn("AI Cabinets: defaults #{message}; using built-in face_frame fallback value.")
      end
      face_frame = FALLBACK_FACE_FRAME if validation_errors.any?
      result[:face_frame] = face_frame

      constraints_source = raw['constraints'] || raw[:constraints]
      result[:constraints] = sanitize_constraints(constraints_source)

      result
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
          when :partition_mode
            sanitize_enum_field(label, raw[key.to_s], PARTITION_MODE_OPTIONS, fallback)
          when :shelves
            sanitize_integer_field(label, raw[key.to_s], fallback, min: 0, max: 20)
          when :partitions
            sanitize_partitions(raw[key.to_s])
          when :face_frame
            face_frame_raw = raw[key.to_s] || raw[key]
            face_frame, = AICabinets::FaceFrame.normalize(face_frame_raw, defaults: FALLBACK_FACE_FRAME)
            face_frame
          else
            sanitize_numeric_field(label, raw[key.to_s], fallback)
          end
      end
    end
    private_class_method :sanitize_cabinet_base

    def sanitize_constraints(raw)
      unless raw.is_a?(Hash)
        return deep_dup(FALLBACK_CONSTRAINTS)
      end

      warn_unknown_keys(raw, CONSTRAINT_KEYS, 'defaults.constraints')

      FALLBACK_CONSTRAINTS.each_with_object({}) do |(key, fallback), result|
        label = "constraints.#{key}"
        result[key] = sanitize_numeric_field(label, raw[key.to_s], fallback)
      end
    end
    private_class_method :sanitize_constraints

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
        PARTITION_LAYOUT_MODES,
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

      sanitized[:orientation] = sanitize_enum_field(
        'cabinet_base.partitions.orientation',
        raw['orientation'],
        ORIENTATION_OPTIONS,
        PARTITIONS_FALLBACK[:orientation]
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

      sanitized[:bays] = sanitize_partitions_bays(raw['bays'])

      canonicalize_partitions(sanitized)
    end
    private_class_method :sanitize_partitions

    def sanitize_partitions_bays(raw)
      return [] unless raw.is_a?(Array)

      raw.each_with_index.map do |element, index|
        unless element.is_a?(Hash)
          warn("AI Cabinets: defaults cabinet_base.partitions.bays[#{index}] must be an object; ignoring bays.")
          return []
        end

        entry = deep_dup(BAY_FALLBACK)
        entry[:fronts_shelves_state] = deep_dup(entry[:fronts_shelves_state])
        entry[:subpartitions_state] = deep_dup(entry[:subpartitions_state])

        entry[:mode] = sanitize_defaults_bay_mode(element['mode'], entry[:mode], index)

        nested_fronts = element['fronts_shelves_state']
        if nested_fronts.is_a?(Hash)
          nested_shelf = sanitize_integer_field(
            "cabinet_base.partitions.bays[#{index}].fronts_shelves_state.shelf_count",
            nested_fronts['shelf_count'],
            entry[:fronts_shelves_state][:shelf_count],
            min: 0,
            max: MAX_PARTITION_COUNT
          )
          entry[:fronts_shelves_state][:shelf_count] = nested_shelf

          if nested_fronts.key?('door_mode')
            entry[:fronts_shelves_state][:door_mode] = sanitize_defaults_door_mode(
              "cabinet_base.partitions.bays[#{index}].fronts_shelves_state.door_mode",
              nested_fronts['door_mode'],
              entry[:fronts_shelves_state][:door_mode]
            )
          end
        end

        shelf_value = sanitize_integer_field(
          "cabinet_base.partitions.bays[#{index}].shelf_count",
          element['shelf_count'],
          entry[:fronts_shelves_state][:shelf_count],
          min: 0,
          max: MAX_PARTITION_COUNT
        )
        entry[:fronts_shelves_state][:shelf_count] = shelf_value
        entry[:shelf_count] = shelf_value

        if element.key?('door_mode')
          door_value = sanitize_defaults_door_mode(
            "cabinet_base.partitions.bays[#{index}].door_mode",
            element['door_mode'],
            entry[:fronts_shelves_state][:door_mode]
          )
          entry[:fronts_shelves_state][:door_mode] = door_value
          entry[:door_mode] = door_value
        else
          entry[:door_mode] = entry[:fronts_shelves_state][:door_mode]
        end

        sub_state = element['subpartitions_state']
        if sub_state.is_a?(Hash)
          sub_count = sanitize_integer_field(
            "cabinet_base.partitions.bays[#{index}].subpartitions_state.count",
            sub_state['count'],
            entry[:subpartitions_state][:count],
            min: 0,
            max: MAX_PARTITION_COUNT
          )
          entry[:subpartitions_state][:count] = sub_count
        end

        sub_container = element['subpartitions']
        if sub_container.is_a?(Hash)
          entry[:subpartitions][:count] = sanitize_integer_field(
            "cabinet_base.partitions.bays[#{index}].subpartitions.count",
            sub_container['count'],
            entry[:subpartitions][:count],
            min: 0,
            max: MAX_PARTITION_COUNT
          )

          entry[:subpartitions][:orientation] = sanitize_enum_field(
            "cabinet_base.partitions.bays[#{index}].subpartitions.orientation",
            sub_container['orientation'],
            ORIENTATION_OPTIONS,
            entry[:subpartitions][:orientation]
          )

          bays_value = sub_container['bays']
          entry[:subpartitions][:bays] =
            if bays_value.is_a?(Array)
              bays_value.each_with_index.map do |sub_element, sub_index|
                unless sub_element.is_a?(Hash)
                  warn("AI Cabinets: defaults cabinet_base.partitions.bays[#{index}].subpartitions.bays[#{sub_index}] must be an object; ignoring entry.")
                  next
                end

                deep_dup(sub_element)
              end.compact
            else
              []
            end
        end

        entry
      end
    rescue StandardError
      []
    end
    private_class_method :sanitize_partitions_bays

    def sanitize_defaults_bay_mode(value, fallback, index)
      return fallback unless value.respond_to?(:to_s)

      text = value.to_s.strip.downcase
      return fallback if text.empty?

      if BAY_MODES.include?(text)
        text
      else
        warn(
          "AI Cabinets: defaults cabinet_base.partitions.bays[#{index}].mode must be one of #{BAY_MODES.join(', ')}; " \
          "using #{fallback}."
        )
        fallback
      end
    end
    private_class_method :sanitize_defaults_bay_mode

    def sanitize_defaults_door_mode(label, value, fallback)
      return fallback if value.nil?

      text = value.to_s.strip
      return nil if text.empty? || text.casecmp('none').zero?

      sanitize_enum_field(label, text, FRONT_OPTIONS, fallback)
    end
    private_class_method :sanitize_defaults_door_mode

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

    def merge_defaults(defaults, overrides)
      result = deep_dup(defaults)

      overrides.each do |key, value|
        if key == :constraints || key == 'constraints'
          result[:constraints] = merge_constraints(result[:constraints], value)
          next
        end

        next unless FALLBACK_MM.key?(key)

        result[key] =
          if key == :partitions
            merge_partitions(result[key], value)
          elsif key == :face_frame
            AICabinets::FaceFrame.merge(result[key], value)
          else
            value
          end
      end

      result
    end
    private_class_method :merge_defaults

    def merge_partitions(defaults, overrides)
      base = defaults.is_a?(Hash) ? deep_dup(defaults) : deep_dup(PARTITIONS_FALLBACK)
      return base unless overrides.is_a?(Hash)

      overrides.each do |key, value|
        next unless RECOGNIZED_PARTITION_KEYS.include?(key.to_s)

        base[key] =
          if key == :positions_mm && value.is_a?(Array)
            value.map { |element| element.to_f }
          elsif key == :bays && value.is_a?(Array)
            value.map { |element| deep_dup(element) }
          else
            value
          end
      end

      base
    end
    private_class_method :merge_partitions

    def merge_constraints(defaults, overrides)
      base = defaults.is_a?(Hash) ? deep_dup(defaults) : deep_dup(FALLBACK_CONSTRAINTS)
      return base unless overrides.is_a?(Hash)

      overrides.each do |key, value|
        symbol = key.to_sym
        next unless FALLBACK_CONSTRAINTS.key?(symbol)

        label = "overrides.constraints.#{symbol}"
        base[symbol] = sanitize_numeric_field(label, value, base.fetch(symbol, FALLBACK_CONSTRAINTS[symbol]))
      end

      base
    end
    private_class_method :merge_constraints

    def build_overrides_payload(params_mm)
      return {} unless params_mm.is_a?(Hash)

      payload = {}
      FALLBACK_MM.each_key do |key|
        value = params_mm[key]
        value = params_mm[key.to_s] if value.nil? && params_mm.key?(key.to_s)

        payload[key.to_s] =
          case key
          when :partitions
            build_overrides_partitions(value)
          when :face_frame
            AICabinets::FaceFrame.build_overrides_payload(value)
          when :front, :partition_mode
            value.to_s
          when :shelves
            value.to_i
          else
            normalize_length_mm(value)
          end
      end

      result = { 'cabinet_base' => payload }

      constraints_payload = build_constraints_payload(params_mm[:constraints] || params_mm['constraints'])
      result['constraints'] = constraints_payload unless constraints_payload.empty?

      result
    end
    private_class_method :build_overrides_payload

    def build_overrides_partitions(value)
      raw = value.is_a?(Hash) ? value : {}

      PARTITIONS_FALLBACK.each_with_object({}) do |(key, _), result|
        result[key.to_s] =
          case key
          when :mode
            raw[key].to_s
          when :count
            raw[key].to_i
          when :positions_mm
            array = raw[key].is_a?(Array) ? raw[key] : []
            array.map { |element| normalize_length_mm(element) }.compact
          when :panel_thickness_mm
            element = raw[key]
            element.nil? ? nil : normalize_length_mm(element)
          when :bays
            build_overrides_bays(raw[key])
          end
      end
    end
    private_class_method :build_overrides_partitions

    def build_constraints_payload(value)
      raw = value.is_a?(Hash) ? value : {}

      FALLBACK_CONSTRAINTS.each_with_object({}) do |(key, _), result|
        candidate = raw[key] || raw[key.to_s]
        next if candidate.nil?

        result[key.to_s] = normalize_length_mm(candidate)
      end
    end
    private_class_method :build_constraints_payload

    def build_overrides_bays(value)
      array = value.is_a?(Array) ? value : []
      array.map do |bay|
        next {} unless bay.is_a?(Hash)

        result = {}
        shelf = bay[:shelf_count] || bay['shelf_count']
        begin
          result['shelf_count'] = Integer(shelf)
        rescue ArgumentError, TypeError
          # omit invalid shelf count to allow sanitizer to supply defaults
        end

        door = bay[:door_mode] || bay['door_mode']
        result['door_mode'] = door.to_s if door

        mode = bay[:mode] || bay['mode']
        result['mode'] = mode.to_s if mode

        fronts = bay[:fronts_shelves_state] || bay['fronts_shelves_state']
        if fronts.is_a?(Hash)
          fronts_result = {}

          begin
            fronts_result['shelf_count'] = Integer(fronts[:shelf_count] || fronts['shelf_count'])
          rescue ArgumentError, TypeError
            # ignore malformed shelf count; sanitizer will supply defaults
          end

          door_value = fronts[:door_mode] || fronts['door_mode']
          fronts_result['door_mode'] = door_value.to_s if door_value

          result['fronts_shelves_state'] = fronts_result unless fronts_result.empty?
        end

        sub = bay[:subpartitions_state] || bay['subpartitions_state']
        if sub.is_a?(Hash)
          sub_result = {}

          begin
            sub_result['count'] = Integer(sub[:count] || sub['count'])
          rescue ArgumentError, TypeError
            # ignore malformed subpartition count; sanitizer will supply defaults
          end

          result['subpartitions_state'] = sub_result unless sub_result.empty?
        end

        sub_container = bay[:subpartitions] || bay['subpartitions']
        if sub_container.is_a?(Hash)
          nested = {}

          begin
            nested['count'] = Integer(sub_container[:count] || sub_container['count'])
          rescue ArgumentError, TypeError
            # ignore malformed count; sanitizer will supply defaults
          end

          orientation = sub_container[:orientation] || sub_container['orientation']
          nested['orientation'] = orientation.to_s if orientation

          bays_value = sub_container[:bays] || sub_container['bays']
          if bays_value.is_a?(Array) && !bays_value.empty?
            nested['bays'] = bays_value.map do |entry|
              entry.is_a?(Hash) ? deep_dup(entry) : entry
            end
          end

          result['subpartitions'] = nested unless nested.empty?
        end

        result
      end
    end
    private_class_method :build_overrides_bays

    def normalize_length_mm(value)
      return nil if value.nil?

      value.to_f.round(NORMALIZATION_PRECISION)
    end
    private_class_method :normalize_length_mm

    def ensure_user_dir!
      FileUtils.mkdir_p(USER_DIR)
    end
    private_class_method :ensure_user_dir!

    def canonicalize(sanitized)
      result = {}
      FALLBACK_MM.each_key do |key|
        value = sanitized[key]
        value = FALLBACK_MM[key] if value.nil? && key != :partitions
        result[key] =
          if key == :partitions
            canonicalize_partitions(value)
          elsif key == :partition_mode
            normalized =
              if value.is_a?(String)
                candidate = value.strip.downcase
                PARTITION_MODE_OPTIONS.include?(candidate) ? candidate : nil
              elsif value.is_a?(Symbol)
                candidate = value.to_s
                PARTITION_MODE_OPTIONS.include?(candidate) ? candidate : nil
              end
            normalized || FALLBACK_MM[:partition_mode]
          else
            deep_dup(value)
          end
      end
      constraints_value = sanitized[:constraints] || sanitized['constraints']
      result[:constraints] = canonicalize_constraints(constraints_value)
      result
    end
    private_class_method :canonicalize

    def canonicalize_constraints(value)
      raw = value.is_a?(Hash) ? value : {}

      FALLBACK_CONSTRAINTS.each_with_object({}) do |(key, fallback), result|
        current = raw[key] || raw[key.to_s]
        numeric =
          case current
          when Numeric
            current.to_f
          when String
            Float(current, exception: false)
          else
            nil
          end

        numeric = fallback if numeric.nil? || numeric <= 0.0
        result[key] = normalize_length_mm(numeric)
      end
    end
    private_class_method :canonicalize_constraints

    def canonicalize_partitions(value)
      raw = value.is_a?(Hash) ? value : {}
      result = {}

      PARTITIONS_FALLBACK.each_key do |key|
        current = raw.fetch(key, PARTITIONS_FALLBACK[key])
        result[key] =
          case key
          when :positions_mm
            current.is_a?(Array) ? current.map { |entry| entry.to_f } : PARTITIONS_FALLBACK[:positions_mm].dup
          when :bays
            if current.is_a?(Array)
              current.map { |entry| canonicalize_bay(entry) }
            else
              PARTITIONS_FALLBACK[:bays].map { |entry| canonicalize_bay(entry) }
            end
          when :orientation
            normalize_orientation_value(current, DEFAULT_PARTITION_ORIENTATION)
          else
            deep_dup(current)
          end
      end

      result[:positions_mm] = result[:positions_mm].map { |entry| entry.to_f }
      result[:mode] = PARTITIONS_FALLBACK[:mode] unless PARTITION_LAYOUT_MODES.include?(result[:mode])
      result[:orientation] = DEFAULT_PARTITION_ORIENTATION unless ORIENTATION_OPTIONS.include?(result[:orientation])
      result
    end
    private_class_method :canonicalize_partitions

    def canonicalize_bay(value)
      bay = value.is_a?(Hash) ? value : {}
      fronts = bay[:fronts_shelves_state] || bay['fronts_shelves_state'] || {}
      sub = bay[:subpartitions_state] || bay['subpartitions_state'] || {}
      sub_container = bay[:subpartitions] || bay['subpartitions'] || {}

      {
        mode: bay[:mode] || bay['mode'],
        shelf_count: bay[:shelf_count] || bay['shelf_count'],
        door_mode: bay[:door_mode] || bay['door_mode'],
        fronts_shelves_state: {
          shelf_count: fronts[:shelf_count] || fronts['shelf_count'],
          door_mode: fronts[:door_mode] || fronts['door_mode']
        },
        subpartitions_state: {
          count: sub[:count] || sub['count']
        },
        subpartitions: canonicalize_subpartitions(sub_container)
      }
    end
    private_class_method :canonicalize_bay

    def canonicalize_subpartitions(value)
      raw = value.is_a?(Hash) ? value : {}

      count_value = raw[:count] || raw['count']
      count = count_value.is_a?(Numeric) ? count_value.to_i : count_value

      orientation = normalize_orientation_value(raw[:orientation] || raw['orientation'], DEFAULT_SUBPARTITION_ORIENTATION)

      bays_source = raw[:bays] || raw['bays']
      bays =
        if bays_source.is_a?(Array)
          bays_source.map { |entry| canonicalize_nested_bay(entry) }
        else
          []
        end

      {
        count: count,
        orientation: orientation,
        bays: bays
      }
    end
    private_class_method :canonicalize_subpartitions

    def canonicalize_nested_bay(value)
      bay = canonicalize_bay(value)
      bay.delete(:subpartitions)
      bay
    end
    private_class_method :canonicalize_nested_bay

    def normalize_orientation_value(value, fallback)
      text =
        case value
        when String
          value.strip.downcase
        when Symbol
          value.to_s.downcase
        end

      return fallback unless text && !text.empty?

      ORIENTATION_OPTIONS.include?(text) ? text : fallback
    end
    private_class_method :normalize_orientation_value

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
