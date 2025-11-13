# frozen_string_literal: true

require 'json'

require_relative '../AI Cabinets/suite_helper'
require_relative 'model_query'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/reflow')
Sketchup.require('aicabinets/rows/reveal')
Sketchup.require('aicabinets/generator/fronts')
Sketchup.require('aicabinets/test_harness')

module RowsTestHarness
  DEFAULT_HEIGHT_MM = 720.0
  DEFAULT_DEPTH_MM = 600.0
  DEFAULT_OVERLAY = :frameless_overlay
  FRONT_MODE = 'doors_left'.freeze

  module_function

  def reset_model!
    model = Sketchup.active_model
    raise 'No active model available' unless model

    ensure_model_units_mm(model)
    AICabinetsTestHelper.clean_model!
    ensure_model_units_mm(model)
    model
  end

  def with_fresh_model
    model = reset_model!
    yield(model)
  ensure
    reset_model!
  end

  def build_cabinet!(width_mm:, origin_x_mm:, overlay_type: DEFAULT_OVERLAY,
                     height_mm: DEFAULT_HEIGHT_MM, depth_mm: DEFAULT_DEPTH_MM)
    model = Sketchup.active_model
    raise 'No active model available' unless model

    config = base_config(
      width_mm: width_mm,
      height_mm: height_mm,
      depth_mm: depth_mm,
      overlay_type: overlay_type
    )

    definition, instance = AICabinets::TestHarness.insert!(config: config)
    raise 'Failed to insert cabinet for tests.' unless instance&.valid?

    translation = Geom::Transformation.translation([origin_x_mm.to_f.mm, 0.0, 0.0])
    instance.transform!(translation)
    instance
  end

  def build_row(widths_mm:, overlay_type: DEFAULT_OVERLAY, origin_x_mm: 0.0)
    offset_mm = origin_x_mm.to_f
    instances = widths_mm.map do |width|
      instance = build_cabinet!(
        width_mm: width,
        origin_x_mm: offset_mm,
        overlay_type: overlay_type
      )
      offset_mm += width.to_f
      instance
    end

    row_id = create_row_from(instances)
    [row_id, instances]
  end

  def create_row_from(instances)
    model = Sketchup.active_model
    raise 'No active model available' unless model

    selection = model.selection
    selection.clear
    instances.each do |instance|
      next unless instance&.valid?

      selection.add(instance)
    end

    AICabinets::Rows.create_from_selection(model: model)
  ensure
    selection&.clear if selection.respond_to?(:clear)
  end

  def apply_reflow!(instance:, new_width_mm:, scope: :instance_only)
    AICabinets::Rows::Reflow.apply_width_change!(
      instance: instance,
      new_width_mm: new_width_mm,
      scope: scope
    )
  end

  def set_row_reveal!(row_id:, mm:)
    model = Sketchup.active_model
    raise 'No active model available' unless model

    AICabinets::Rows.update(
      model: model,
      row_id: row_id,
      row_reveal_mm: mm
    )
  end

  def apply_reveal!(row_id:, operation: true)
    model = Sketchup.active_model
    raise 'No active model available' unless model

    AICabinets::Rows::Reveal.apply!(
      row_id: row_id,
      model: model,
      operation: operation
    )
  end

  def measure_boundary_gaps_mm(row_id:)
    entries = ordered_row_entries(row_id)
    return [] if entries.empty?

    gaps = []
    entries.each_with_index do |entry, index|
      if index.zero?
        gaps << (entry[:door_min_x_mm] - entry[:origin_x_mm])
      end

      if index < entries.length - 1
        right = entries[index + 1]
        gaps << (right[:door_min_x_mm] - entry[:door_max_x_mm])
      else
        right_gap = entry[:origin_x_mm] + entry[:width_mm] - entry[:door_max_x_mm]
        gaps << right_gap
      end
    end

    gaps
  end

  def member_origins_mm(instances)
    Array(instances).map do |instance|
      next unless instance&.valid?

      AICabinetsTestHelper.mm(instance.transformation.origin.x)
    end.compact
  end

  def instance_width_mm(instance)
    params = AICabinetsTestHelper.params_mm_from_definition(instance)
    params[:width_mm].to_f
  end

  def cabinet_origin_mm(instance)
    AICabinetsTestHelper.mm(instance.transformation.origin.x)
  end

  def cabinet_width_mm(instance)
    instance_width_mm(instance)
  end

  def door_extents_world_mm(instance)
    entries = ModelQuery.fronts_by_bay(instance: instance).values.flatten
    raise 'Cabinet has no door fronts.' if entries.empty?

    base_transform = instance.transformation
    world_bbox = Geom::BoundingBox.new

    entries.each do |info|
      entity = info[:entity]
      next unless entity&.valid?

      bounds = world_bounds_for_front(entity, base_transform)
      next unless bounds

      8.times do |index|
        point = bounds.corner(index)
        next unless point

        world_bbox.add(point)
      end
    end

    raise 'Unable to resolve door fronts bounds.' if world_bbox.empty?

    min_x = world_bbox.min.x
    max_x = world_bbox.max.x

    [
      AICabinetsTestHelper.mm_from_length(min_x),
      AICabinetsTestHelper.mm_from_length(max_x)
    ]
  end

  def total_length_mm(instances)
    bounds = Array(instances).filter_map do |instance|
      instance.bounds if instance&.valid?
    end
    return 0.0 if bounds.empty?

    min_x = bounds.map { |bbox| AICabinetsTestHelper.mm(bbox.min.x) }.min
    max_x = bounds.map { |bbox| AICabinetsTestHelper.mm(bbox.max.x) }.max
    max_x - min_x
  end

  def count_operations
    model = Sketchup.active_model
    raise 'No active model available' unless model

    counter = OperationCounter.new
    counter.attach(model)
    yield
    counter.commits
  ensure
    counter&.detach(model)
  end

  def door_edges_local_mm(instance)
    origin = cabinet_origin_mm(instance)
    min_x, max_x = door_extents_world_mm(instance)
    [min_x - origin, max_x - origin]
  end

  def door_left_gap_mm(instance)
    min_local, = door_edges_local_mm(instance)
    min_local
  end

  def door_right_gap_mm(instance)
    _, max_local = door_edges_local_mm(instance)
    cabinet_width_mm(instance) - max_local
  end

  def ordered_row_entries(row_id)
    model = Sketchup.active_model
    raise 'No active model available' unless model

    state, = AICabinets::Rows.__send__(:prepare_state, model)
    row = state['rows'][row_id]
    return [] unless row

    members = AICabinets::Rows.__send__(
      :resolve_member_instances,
      model,
      row['member_pids']
    )

    members.filter_map do |instance|
      next unless instance&.valid?

      membership = AICabinets::Rows.for_instance(instance)
      next unless membership

      door_min_x_mm, door_max_x_mm = door_extents_world_mm(instance)
      {
        instance: instance,
        row_pos: membership[:row_pos].to_i,
        origin_x_mm: cabinet_origin_mm(instance),
        width_mm: cabinet_width_mm(instance),
        door_min_x_mm: door_min_x_mm,
        door_max_x_mm: door_max_x_mm
      }
    end.sort_by do |entry|
      [entry[:row_pos], entry[:origin_x_mm], entry[:instance].persistent_id.to_i]
    end
  end
  private_class_method :ordered_row_entries

  def base_config(width_mm:, height_mm:, depth_mm:, overlay_type:)
    defaults = deep_copy(AICabinets::Defaults.load_effective_mm)
    defaults[:width_mm] = width_mm
    defaults[:height_mm] = height_mm
    defaults[:depth_mm] = depth_mm
    defaults[:front] = FRONT_MODE
    defaults[:door_reveal_mm] = 2.0
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

  def deep_copy(object)
    Marshal.load(Marshal.dump(object))
  rescue StandardError
    object.dup
  end
  private_class_method :deep_copy

  def world_bounds_for_front(entity, parent_transform)
    return unless entity&.valid?

    transform =
      if entity.respond_to?(:transformation)
        parent_transform * entity.transformation
      else
        parent_transform
      end

    source_bounds =
      if entity.respond_to?(:definition) && entity.definition&.valid?
        entity.definition.bounds
      elsif entity.respond_to?(:entities)
        entity.entities.bounds
      else
        entity.bounds
      end

    return unless source_bounds

    bounds = Geom::BoundingBox.new
    8.times do |index|
      point = source_bounds.corner(index)
      next unless point

      bounds.add(point.transform(transform))
    end

    bounds
  end
  private_class_method :world_bounds_for_front

  def ensure_model_units_mm(model)
    options = model.options
    return unless options

    units = options['UnitsOptions']
    return unless units

    units['LengthUnit'] = 2
    units['LengthFormat'] = 0
    units['LengthPrecision'] = 0
    units['LengthFractionalPrecision'] = 3
  rescue StandardError
    nil
  end
  private_class_method :ensure_model_units_mm

  class OperationCounter < Sketchup::ModelObserver
    attr_reader :commits

    def initialize
      super()
      reset!
    end

    def attach(model)
      reset!
      @model = model
      model.add_observer(self)
    end

    def detach(model)
      model.remove_observer(self)
    ensure
      reset!
      @model = nil
    end

    def onTransactionCommit(_model)
      @commits += 1
    end

    def reset!
      @commits = 0
    end
  end
  private_constant :OperationCounter
end
