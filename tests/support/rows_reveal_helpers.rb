# frozen_string_literal: true

require 'json'

module RowsRevealTestHelpers
  DEFAULT_ROW_REVEAL_MM = 3.0
  LEGACY_EDGE_REVEAL_MM = 2.0
  FRONT_MODE = 'doors_left'.freeze

  module_function

  def build_row(widths_mm:, overlay_type: :frameless_overlay)
    model = Sketchup.active_model
    raise 'No active model available' unless model

    instances = []
    offset_mm = 0.0
    widths_mm.each do |width|
      config = base_config(width_mm: width, overlay_type: overlay_type)
      _definition, instance = AICabinets::TestHarness.insert!(config: config)
      translation = Geom::Transformation.translation([offset_mm.mm, 0, 0])
      instance.transform!(translation)
      instances << instance
      offset_mm += width.to_f
    end

    selection = model.selection
    selection.clear
    instances.each { |instance| selection.add(instance) }

    row_id = AICabinets::Rows.create_from_selection(model: model)
    [row_id, instances]
  end

  def apply_row_reveal!(row_id:, reveal_mm: DEFAULT_ROW_REVEAL_MM)
    model = Sketchup.active_model
    AICabinets::Rows.update(model: model, row_id: row_id, row_reveal_mm: reveal_mm)
  end

  def interior_gap_mm(left_instance, right_instance)
    left_edges = door_edges_world(left_instance)
    right_edges = door_edges_world(right_instance)
    right_edges.first - left_edges.last
  end

  def left_end_gap_mm(instance)
    left_local, = door_edges_local(instance)
    left_local
  end

  def right_end_gap_mm(instance)
    width = cabinet_width_mm(instance)
    _, right_local = door_edges_local(instance)
    width - right_local
  end

  def cabinet_origin_mm(instance)
    AICabinetsTestHelper.mm(instance.transformation.origin.x)
  end

  def cabinet_width_mm(instance)
    params = AICabinetsTestHelper.params_mm_from_definition(instance)
    params[:width_mm].to_f
  end

  def door_edges_world(instance)
    origin = cabinet_origin_mm(instance)
    left_local, right_local = door_edges_local(instance)
    [origin + left_local, origin + right_local]
  end

  def set_use_row_reveal(instance, value)
    dictionary = instance.attribute_dictionary(AICabinets::Rows::Reveal::REVEAL_DICTIONARY, true)
    dictionary[AICabinets::Rows::Reveal::USE_ROW_REVEAL_KEY] = !!value
  end

  def base_config(width_mm:, overlay_type:)
    defaults = deep_copy(AICabinets::Defaults.load_effective_mm)
    defaults[:width_mm] = width_mm
    defaults[:front] = FRONT_MODE
    defaults[:door_reveal_mm] = LEGACY_EDGE_REVEAL_MM
    defaults[:door_gap_mm] = AICabinets::Generator::Fronts::REVEAL_CENTER_MM

    defaults[:fronts_shelves_state] = deep_copy(defaults[:fronts_shelves_state]) || {}
    defaults[:fronts_shelves_state][:door_mode] = FRONT_MODE
    defaults[:fronts_shelves_state][:shelf_count] ||= 0

    defaults[:partition_mode] = overlay_type == :face_frame_overlay ? 'horizontal' : 'none'

    partitions = defaults[:partitions] = deep_copy(defaults[:partitions]) || {}
    partitions[:mode] = defaults[:partition_mode]
    partitions[:orientation] = overlay_type == :face_frame_overlay ? 'horizontal' : 'vertical'
    partitions[:count] = 0
    partitions[:positions_mm] = Array(partitions[:positions_mm])
    partitions[:bays] = Array(partitions[:bays]).map { |bay| deep_copy(bay) }
    partitions[:bays] = [{}] if partitions[:bays].empty?

    partitions[:bays].map! do |bay|
      bay = bay.is_a?(Hash) ? bay : {}
      bay[:mode] ||= 'fronts_shelves'
      bay[:door_mode] = FRONT_MODE
      state = bay[:fronts_shelves_state]
      state = state.is_a?(Hash) ? deep_copy(state) : {}
      state[:door_mode] = FRONT_MODE
      state[:shelf_count] ||= 0
      bay[:fronts_shelves_state] = state
      bay
    end

    defaults
  end
  private_class_method :base_config

  def door_edges_local(instance)
    fronts_by_bay = ModelQuery.fronts_by_bay(instance: instance)
    entries = fronts_by_bay.values.flatten
    raise 'Cabinet has no door fronts.' if entries.empty?

    min_x = entries.map { |info| info[:bounds].min.x }.min
    max_x = entries.map { |info| info[:bounds].max.x }.max

    [AICabinetsTestHelper.mm(min_x), AICabinetsTestHelper.mm(max_x)]
  end
  private_class_method :door_edges_local

  def deep_copy(object)
    Marshal.load(Marshal.dump(object))
  rescue StandardError
    object.dup
  end
  private_class_method :deep_copy
end
