# frozen_string_literal: true

require 'json'
require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/reflow')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

module RowsReflowTestHelpers
  BASE_PARAMS_MM = {
    width_mm: 762.0,
    depth_mm: 609.6,
    height_mm: 914.4,
    panel_thickness_mm: 18.0,
    toe_kick_height_mm: 101.6,
    toe_kick_depth_mm: 76.2,
    bay_count: 1,
    partitions_enabled: false,
    fronts_enabled: false
  }.freeze

  module_function

  def build_row(model, widths_mm)
    instances = []
    offset_mm = 0.0

    widths_mm.each do |width|
      params = BASE_PARAMS_MM.merge(width_mm: width)
      point = Geom::Point3d.new(offset_mm.mm, 0, 0)
      instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
        model: model,
        point3d: point,
        params_mm: params
      )
      instances << instance
      offset_mm += width
    end

    selection = model.selection
    selection.clear
    instances.each { |instance| selection.add(instance) }

    row_id = AICabinets::Rows.create_from_selection(model: model)
    [row_id, instances]
  end

  def instance_width_mm(instance)
    dictionary = instance.definition.attribute_dictionary(AICabinets::Ops::InsertBaseCabinet::DICTIONARY_NAME)
    json = dictionary[AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY]
    params = JSON.parse(json)
    params['width_mm'].to_f
  end

  def origins_mm(instances)
    instances.map do |instance|
      origin = instance.transformation.origin
      AICabinetsTestHelper.mm(origin.x)
    end
  end

  def total_length_mm(instances)
    bounds = instances.map(&:bounds)
    min_x = bounds.map { |bbox| bbox.min.x }.min
    max_x = bounds.map { |bbox| bbox.max.x }.max
    AICabinetsTestHelper.mm(max_x - min_x)
  end

  def contiguous_row_positions?(instances)
    instances.each_with_index.all? do |instance, index|
      membership = AICabinets::Rows.for_instance(instance)
      membership && membership[:row_pos] == index + 1
    end
  end
end

class TC_Rows_Reflow_InstanceOnly < TestUp::TestCase
  include RowsReflowTestHelpers

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_instance_only_shift_right_neighbors
    model = Sketchup.active_model
    row_id, instances = build_row(model, [600.0, 400.0, 800.0])
    refute_nil(row_id)

    first, second, third = instances
    before_origins = origins_mm(instances)

    result = AICabinets::Rows::Reflow.apply_width_change!(
      instance: second,
      new_width_mm: 450.0,
      scope: :instance_only
    )

    assert(result.ok?)

    after_origins = origins_mm(instances)
    assert_in_delta(before_origins[0], after_origins[0], 1e-3)
    assert_in_delta(before_origins[2] + 50.0, after_origins[2], 1e-3)

    assert_in_delta(450.0, instance_width_mm(second), 1e-3)
    assert(contiguous_row_positions?(instances))
  end
end

class TC_Rows_Reflow_AllInstances < TestUp::TestCase
  include RowsReflowTestHelpers

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_all_instances_delta_accumulates
    model = Sketchup.active_model
    row_id, instances = build_row(model, [600.0, 400.0, 600.0, 700.0])
    refute_nil(row_id)

    first, second, third, fourth = instances
    assert_equal(first.definition, third.definition, 'Expected first and third to share a definition')

    before_origins = origins_mm(instances)

    result = AICabinets::Rows::Reflow.apply_width_change!(
      instance: first,
      new_width_mm: 630.0,
      scope: :all_instances
    )
    assert(result.ok?)

    after_origins = origins_mm(instances)
    assert_in_delta(before_origins[1] + 30.0, after_origins[1], 1e-3)
    assert_in_delta(before_origins[3] + 60.0, after_origins[3], 1e-3)
  end
end

class TC_Rows_Reflow_Shrink < TestUp::TestCase
  include RowsReflowTestHelpers

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_shrinking_moves_neighbors_left
    model = Sketchup.active_model
    row_id, instances = build_row(model, [600.0, 400.0, 800.0])
    refute_nil(row_id)

    _, second, third = instances
    before_origins = origins_mm(instances)

    result = AICabinets::Rows::Reflow.apply_width_change!(
      instance: second,
      new_width_mm: 350.0,
      scope: :instance_only
    )
    assert(result.ok?)

    after_origins = origins_mm(instances)
    assert_in_delta(before_origins[2] - 50.0, after_origins[2], 1e-3)
  end
end

class TC_Rows_Reflow_LockLength < TestUp::TestCase
  include RowsReflowTestHelpers

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_lock_length_adjusts_filler
    model = Sketchup.active_model
    row_id, instances = build_row(model, [600.0, 400.0, 200.0])
    refute_nil(row_id)

    AICabinets::Rows.update(model: model, row_id: row_id, lock_total_length: true)

    _, middle, filler = instances
    before_length = total_length_mm(instances)

    result = AICabinets::Rows::Reflow.apply_width_change!(
      instance: middle,
      new_width_mm: 440.0,
      scope: :instance_only
    )
    assert(result.ok?)

    assert_in_delta(160.0, instance_width_mm(filler), 1e-3)
    after_length = total_length_mm(instances)
    assert_in_delta(before_length, after_length, 1e-3)
  end
end

class TC_Rows_Reflow_LockLengthFailure < TestUp::TestCase
  include RowsReflowTestHelpers

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_lock_length_failure
    model = Sketchup.active_model
    row_id, instances = build_row(model, [600.0, 400.0, 100.0])
    refute_nil(row_id)

    AICabinets::Rows.update(model: model, row_id: row_id, lock_total_length: true)

    _, middle, filler = instances
    before_width = instance_width_mm(filler)

    assert_raises(AICabinets::Rows::RowError) do
      AICabinets::Rows::Reflow.apply_width_change!(
        instance: middle,
        new_width_mm: 520.0,
        scope: :instance_only
      )
    end

    assert_in_delta(before_width, instance_width_mm(filler), 1e-3)
  end
end

class TC_Rows_Reflow_UndoRedo < TestUp::TestCase
  include RowsReflowTestHelpers

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_reflow_is_single_undo
    model = Sketchup.active_model
    _row_id, instances = build_row(model, [600.0, 400.0, 800.0])

    _, middle, third = instances
    before_origins = origins_mm(instances)

    result = AICabinets::Rows::Reflow.apply_width_change!(
      instance: middle,
      new_width_mm: 450.0,
      scope: :instance_only
    )
    assert(result.ok?)

    after_origins = origins_mm(instances)
    assert_in_delta(before_origins[2] + 50.0, after_origins[2], 1e-3)

    Sketchup.send_action('editUndo:')
    undo_origins = origins_mm(instances)
    assert_in_delta(before_origins[0], undo_origins[0], 1e-3)
    assert_in_delta(before_origins[2], undo_origins[2], 1e-3)

    Sketchup.send_action('editRedo:')
    redo_origins = origins_mm(instances)
    assert_in_delta(after_origins[2], redo_origins[2], 1e-3)
  end
end

