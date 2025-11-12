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

      min_leaf_width_mm = fetch_min_leaf_width_mm(params)
      metadata = { leaf_width_mm: nil, min_leaf_width_mm: min_leaf_width_mm }

      return failure(metadata) unless params && !index.nil?
      return failure(metadata) if index.negative?

      ranges = partition_bay_ranges_mm(params)
      bay_range = ranges[index]
      return failure(metadata) unless bay_range

      bay_width_mm = bay_range[1].to_f - bay_range[0].to_f
      return failure(metadata) if bay_width_mm <= FRONT_MIN_DIMENSION_MM

      partitions = fetch_partitions(params)
      total_bays = ranges.length
      panel_thickness_mm = coerce_positive_numeric(params[:panel_thickness_mm]) || 0.0
      orientation = partition_orientation(partitions)
      interior_width_mm = coerce_positive_numeric(params[:width_mm]) || 0.0
      interior_width_mm = [interior_width_mm - (panel_thickness_mm * 2.0), 0.0].max
      partition_thickness_mm = compute_partition_thickness_mm(partitions, panel_thickness_mm, interior_width_mm)
      interior_half_thickness_mm = [partition_thickness_mm / 2.0, 0.0].max

      overlay_left_mm = bay_edge_overlay_mm(
        bay_index: index,
        total_bays: total_bays,
        side: :left,
        orientation: orientation,
        panel_thickness_mm: panel_thickness_mm,
        interior_half_thickness_mm: interior_half_thickness_mm
      )
      overlay_right_mm = bay_edge_overlay_mm(
        bay_index: index,
        total_bays: total_bays,
        side: :right,
        orientation: orientation,
        panel_thickness_mm: panel_thickness_mm,
        interior_half_thickness_mm: interior_half_thickness_mm
      )
      overlay_total_mm = overlay_left_mm + overlay_right_mm

      front_presence = bay_front_presence(params)
      edge_reveal_mm = fetch_edge_reveal_mm(params)
      center_gap_mm = fetch_center_gap_mm(params)
      left_reveal_mm = bay_edge_reveal_mm(
        front_presence: front_presence,
        bay_index: index,
        total_bays: total_bays,
        side: :left,
        orientation: orientation,
        edge_reveal_mm: edge_reveal_mm,
        center_gap_mm: center_gap_mm
      )
      right_reveal_mm = bay_edge_reveal_mm(
        front_presence: front_presence,
        bay_index: index,
        total_bays: total_bays,
        side: :right,
        orientation: orientation,
        edge_reveal_mm: edge_reveal_mm,
        center_gap_mm: center_gap_mm
      )
      reveal_total_mm = left_reveal_mm + right_reveal_mm

      usable_width_mm = bay_width_mm + overlay_total_mm - reveal_total_mm - center_gap_mm
      if usable_width_mm <= FRONT_MIN_DIMENSION_MM
        metadata[:leaf_width_mm] = 0.0
        return failure(metadata)
      end

      leaf_width_mm = usable_width_mm / 2.0
      if leaf_width_mm <= FRONT_MIN_DIMENSION_MM
        metadata[:leaf_width_mm] = leaf_width_mm
        return failure(metadata)
      end

      metadata[:leaf_width_mm] = leaf_width_mm

      allowed = AICabinets::Generator::Fronts.double_allowed?(
        bay_interior_width_mm: bay_width_mm,
        overlay_mm: overlay_total_mm,
        reveal_mm: reveal_total_mm,
        door_gap_mm: center_gap_mm,
        min_leaf_width_mm: min_leaf_width_mm,
        leaf_width_mm: leaf_width_mm
      )

      allowed ? [true, nil, metadata] : failure(metadata)
    rescue StandardError => error
      warn("AI Cabinets: double door validity check failed: #{error.message}")
      failure(metadata)
    end

    def failure(metadata = nil)
      [false, DOUBLE_DISABLED_REASON, metadata]
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

      mode = normalize_partition_mode(partitions)
      orientation = partition_orientation(partitions)

      if orientation == :horizontal
        bay_count = horizontal_bay_count(params, partitions, mode)
        bay_count = 1 if bay_count <= 0
        return Array.new(bay_count) { [left, right] }
      end

      thickness = compute_partition_thickness_mm(partitions, panel_thickness_mm, interior_width)

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

    def horizontal_bay_count(params, partitions, mode)
      specs = fetch_bays_array(params)
      count = specs.length
      return count if count.positive?

      case mode
      when :even
        partition_count = coerce_non_negative_integer(fetch_hash_value(partitions, :count)) || 0
        partition_count + 1
      when :positions
        positions = Array(fetch_hash_value(partitions, :positions_mm))
        numeric = positions.map { |value| coerce_float(value) }.compact
        numeric.empty? ? 1 : numeric.length + 1
      else
        1
      end
    end
    private_class_method :horizontal_bay_count

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

    def fetch_partitions(params)
      return {} unless params.is_a?(Hash)

      container = params[:partitions] || params['partitions']
      container.is_a?(Hash) ? container : {}
    end
    private_class_method :fetch_partitions

    def partition_orientation(partitions)
      raw = fetch_hash_value(partitions, :orientation)
      text = raw.to_s.strip.downcase
      text == 'horizontal' ? :horizontal : :vertical
    end
    private_class_method :partition_orientation

    def bay_edge_overlay_mm(bay_index:, total_bays:, side:, orientation:, panel_thickness_mm:, interior_half_thickness_mm:)
      return panel_thickness_mm.to_f if orientation == :horizontal

      case side
      when :left
        return panel_thickness_mm.to_f if bay_index.zero?
        interior_half_thickness_mm.to_f
      when :right
        return panel_thickness_mm.to_f if bay_index == total_bays - 1
        interior_half_thickness_mm.to_f
      else
        interior_half_thickness_mm.to_f
      end
    end
    private_class_method :bay_edge_overlay_mm

    def bay_edge_reveal_mm(front_presence:, bay_index:, total_bays:, side:, orientation:, edge_reveal_mm:, center_gap_mm:)
      return edge_reveal_mm.to_f if total_bays <= 1
      return edge_reveal_mm.to_f if orientation == :horizontal

      case side
      when :left
        return edge_reveal_mm.to_f if bay_index.zero?

        neighbor_index = bay_index - 1
        present = front_present?(front_presence, bay_index) && front_present?(front_presence, neighbor_index)
        return edge_reveal_mm.to_f unless present
      when :right
        return edge_reveal_mm.to_f if bay_index == total_bays - 1

        neighbor_index = bay_index + 1
        present = front_present?(front_presence, bay_index) && front_present?(front_presence, neighbor_index)
        return edge_reveal_mm.to_f unless present
      else
        return edge_reveal_mm.to_f
      end

      center_gap_mm.to_f / 2.0
    end
    private_class_method :bay_edge_reveal_mm

    def bay_front_presence(params)
      bays = fetch_bays_array(params)
      bays.map { |bay| bay_front_present?(bay) }
    end
    private_class_method :bay_front_presence

    def fetch_bays_array(params)
      partitions = fetch_partitions(params)
      bays = fetch_hash_value(partitions, :bays)
      bays.is_a?(Array) ? bays : []
    end
    private_class_method :fetch_bays_array

    def bay_front_present?(bay)
      return false unless bay.is_a?(Hash)

      mode_value = fetch_hash_value(bay, :mode)
      normalized_mode = mode_value.to_s.strip.downcase
      active_mode = normalized_mode.empty? || normalized_mode == 'fronts_shelves'
      return false unless active_mode

      fronts_state = fetch_hash_value(bay, :fronts_shelves_state)
      door_value =
        if fronts_state.is_a?(Hash)
          fetch_hash_value(fronts_state, :door_mode)
        else
          nil
        end
      door_value ||= fetch_hash_value(bay, :door_mode)
      text = door_value.to_s.strip.downcase
      !text.empty? && text != 'none' && text != 'doors_none'
    end
    private_class_method :bay_front_present?

    def front_present?(front_presence, index)
      return false unless front_presence.is_a?(Array)
      value = front_presence[index]
      !!value
    end
    private_class_method :front_present?

    def fetch_min_leaf_width_mm(params)
      if params.is_a?(Hash)
        constraints = params[:constraints] || params['constraints']
        if constraints.is_a?(Hash)
          value = constraints[:min_door_leaf_width_mm] || constraints['min_door_leaf_width_mm']
          numeric = coerce_positive_numeric(value)
          return numeric if numeric
        end
      end

      defaults = AICabinets::Defaults.load_effective_mm
      constraints = defaults[:constraints] || defaults['constraints'] || {}
      value = constraints[:min_door_leaf_width_mm] || constraints['min_door_leaf_width_mm']
      numeric = coerce_positive_numeric(value)
      return numeric if numeric

      AICabinets::Generator::Fronts.min_double_leaf_width_mm
    rescue StandardError
      AICabinets::Generator::Fronts.min_double_leaf_width_mm
    end
    private_class_method :fetch_min_leaf_width_mm

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
