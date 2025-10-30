# frozen_string_literal: true

require 'aicabinets/defaults'
require 'aicabinets/params_sanitizer'
require 'aicabinets/generator/fronts'
require 'aicabinets/generator/shelves'

module AICabinets
  # Door mode validation helpers shared with the HtmlDialog bridge.
  module DoorModeRules
    module_function

    DOUBLE_DISABLED_REASON = :door_mode_double_disabled_hint
    FRONT_MIN_DIMENSION_MM = AICabinets::Generator::Fronts::MIN_DIMENSION_MM
    MIN_BAY_WIDTH_MM = AICabinets::Generator::Shelves::MIN_BAY_WIDTH_MM
    EPSILON_MM = 1.0e-3

    # Determines whether the requested bay can support double doors.
    # Returns `[allowed, reason]` where `reason` is a localization key or string
    # explaining why double doors are unavailable.
    #
    # @param params_mm [Hash] cabinet definition stored in millimeters
    # @param bay_index [Integer] bay index into `partitions.bays`
    # @return [Array(Boolean, Symbol, String)]
    def double_door_validity(params_mm:, bay_index:)
      params = sanitize_params(params_mm)
      index = coerce_index(bay_index)
      return failure unless params && !index.nil?
      return failure if index.negative?

      ranges = partition_bay_ranges_mm(params)
      bay_range = ranges[index]
      return failure unless bay_range

      bay_width_mm = bay_range[1].to_f - bay_range[0].to_f
      return failure if bay_width_mm <= FRONT_MIN_DIMENSION_MM

      edge_reveal_mm = fetch_edge_reveal_mm(params)
      center_gap_mm = fetch_center_gap_mm(params)

      clear_width_mm = bay_width_mm - (edge_reveal_mm * 2.0)
      return failure if clear_width_mm <= FRONT_MIN_DIMENSION_MM

      usable_width_mm = clear_width_mm - center_gap_mm
      return failure if usable_width_mm <= FRONT_MIN_DIMENSION_MM

      leaf_width_mm = usable_width_mm / 2.0
      return failure if leaf_width_mm <= FRONT_MIN_DIMENSION_MM

      [true, nil]
    rescue StandardError => error
      warn("AI Cabinets: double door validity check failed: #{error.message}")
      failure
    end

    def failure
      [false, DOUBLE_DISABLED_REASON]
    end
    private_class_method :failure

    def sanitize_params(params_mm)
      return nil unless params_mm.is_a?(Hash)

      copy = deep_copy(params_mm)
      defaults = AICabinets::Defaults.load_effective_mm
      AICabinets::ParamsSanitizer.sanitize!(copy, global_defaults: defaults)
      copy
    rescue StandardError
      nil
    end
    private_class_method :sanitize_params

    def coerce_index(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :coerce_index

    def partition_bay_ranges_mm(params)
      partitions = params[:partitions] || {}

      panel_thickness_mm = coerce_positive_numeric(params[:panel_thickness_mm]) || 0.0
      width_mm = coerce_positive_numeric(params[:width_mm]) || 0.0
      left = panel_thickness_mm
      right = width_mm - panel_thickness_mm
      return [] unless right > left

      interior_width = right - left
      return [] if interior_width < MIN_BAY_WIDTH_MM

      thickness = compute_partition_thickness_mm(partitions, panel_thickness_mm, interior_width)
      mode = normalize_partition_mode(partitions)

      case mode
      when :even
        compute_even_ranges(left, right, interior_width, thickness, partitions)
      when :positions
        compute_position_ranges(left, right, thickness, partitions)
      else
        [[left, right]]
      end
    end
    private_class_method :partition_bay_ranges_mm

    def fetch_edge_reveal_mm(params)
      value = coerce_non_negative_numeric(params[:door_reveal_mm])
      value ||= coerce_non_negative_numeric(params[:door_reveal])
      value ||= AICabinets::Generator::Fronts::REVEAL_EDGE_MM
      value
    end
    private_class_method :fetch_edge_reveal_mm

    def fetch_center_gap_mm(params)
      value = coerce_non_negative_numeric(params[:door_gap_mm])
      value ||= coerce_non_negative_numeric(params[:door_gap])
      value ||= AICabinets::Generator::Fronts::REVEAL_CENTER_MM
      value
    end
    private_class_method :fetch_center_gap_mm

    def coerce_non_negative_numeric(value)
      numeric = coerce_float(value)
      return nil if numeric.nil? || numeric.negative?

      numeric
    end
    private_class_method :coerce_non_negative_numeric

    def coerce_positive_numeric(value)
      numeric = coerce_float(value)
      return nil if numeric.nil? || numeric <= 0.0

      numeric
    end
    private_class_method :coerce_positive_numeric

    def coerce_non_negative_integer(value)
      case value
      when Integer
        return value if value >= 0
      when Numeric
        integer = value.round
        return integer if integer >= 0
      when String
        integer = Integer(value, 10)
        return integer if integer >= 0
      end
      nil
    rescue ArgumentError
      nil
    end
    private_class_method :coerce_non_negative_integer

    def normalize_partition_mode(partitions)
      raw = fetch_hash_value(partitions, :mode)
      text = raw.to_s.strip.downcase
      case text
      when 'even'
        :even
      when 'positions'
        :positions
      else
        :none
      end
    end
    private_class_method :normalize_partition_mode

    def compute_partition_thickness_mm(partitions, panel_thickness_mm, interior_width)
      override = coerce_positive_numeric(fetch_hash_value(partitions, :panel_thickness_mm))
      override = nil if override && override >= interior_width - EPSILON_MM

      value = override || panel_thickness_mm
      value.positive? ? value : panel_thickness_mm
    end
    private_class_method :compute_partition_thickness_mm

    def compute_even_ranges(left, right, interior_width, thickness, partitions)
      count = coerce_non_negative_integer(fetch_hash_value(partitions, :count)) || 0
      return [[left, right]] if count <= 0

      available_width = interior_width - (count * thickness)
      minimum_required = MIN_BAY_WIDTH_MM * (count + 1)
      return [] if available_width < minimum_required

      bay_width = available_width / (count + 1)
      return [] if bay_width < MIN_BAY_WIDTH_MM

      ranges = []
      current_left = left
      count.times do
        current_right = current_left + bay_width
        ranges << [current_left, current_right]
        current_left = current_right + thickness
        break if right - current_left < MIN_BAY_WIDTH_MM - EPSILON_MM
      end

      if right - current_left >= MIN_BAY_WIDTH_MM - EPSILON_MM
        ranges << [current_left, right]
      end

      ranges
    end
    private_class_method :compute_even_ranges

    def compute_position_ranges(left, right, thickness, partitions)
      raw_positions = Array(fetch_hash_value(partitions, :positions_mm))
      sorted = raw_positions.map { |value| coerce_float(value) }.compact.sort
      return [[left, right]] if sorted.empty?

      ranges = []
      current_left = left
      sorted.each do |raw_face|
        break if right - current_left < MIN_BAY_WIDTH_MM - EPSILON_MM

        clamped = clamp(raw_face, left, right - thickness)
        next if (clamped - current_left) < MIN_BAY_WIDTH_MM - EPSILON_MM

        ranges << [current_left, clamped]
        current_left = clamped + thickness
      end

      if right - current_left >= MIN_BAY_WIDTH_MM - EPSILON_MM
        ranges << [current_left, right]
      end

      ranges
    end
    private_class_method :compute_position_ranges

    def fetch_hash_value(hash, key)
      return nil unless hash.respond_to?(:[])

      hash[key] || hash[key.to_s]
    end
    private_class_method :fetch_hash_value

    def clamp(value, min_value, max_value)
      return min_value if value.nil?

      [[value, max_value].min, min_value].max
    end
    private_class_method :clamp

    def coerce_float(value)
      case value
      when Numeric
        value.to_f
      when String
        text = value.strip
        return nil if text.empty?

        Float(text)
      else
        nil
      end
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :coerce_float

    def deep_copy(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, element), memo|
          memo[key] = deep_copy(element)
        end
      when Array
        value.map { |element| deep_copy(element) }
      else
        value
      end
    end
    private_class_method :deep_copy
  end
end
