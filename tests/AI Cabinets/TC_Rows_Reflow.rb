# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/rows_test_harness'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/reflow')

class TC_Rows_Reflow_InstanceOnly < TestUp::TestCase
  DELTA_TOLERANCE_MM = 0.01

  def setup
    RowsTestHarness.reset_model!
  end

  def teardown
    RowsTestHarness.reset_model!
  end

  def test_instance_only_shift_right_neighbors
    _row_id, instances = RowsTestHarness.build_row(widths_mm: [600.0, 400.0, 800.0])
    _first, second, _third = instances

    before_origins = RowsTestHarness.member_origins_mm(instances)

    result = RowsTestHarness.apply_reflow!(
      instance: second,
      new_width_mm: 450.0,
      scope: :instance_only
    )

    assert(result.ok?)

    after_origins = RowsTestHarness.member_origins_mm(instances)

    assert_in_delta(before_origins[0], after_origins[0], DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[1], after_origins[1], DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[2] + 50.0, after_origins[2], DELTA_TOLERANCE_MM)
    assert_in_delta(450.0, RowsTestHarness.instance_width_mm(second), DELTA_TOLERANCE_MM)
  end

  def test_shrinking_moves_neighbors_left
    _row_id, instances = RowsTestHarness.build_row(widths_mm: [600.0, 400.0, 800.0])
    _, second, _third = instances

    before_origins = RowsTestHarness.member_origins_mm(instances)

    result = RowsTestHarness.apply_reflow!(
      instance: second,
      new_width_mm: 350.0,
      scope: :instance_only
    )

    assert(result.ok?)

    after_origins = RowsTestHarness.member_origins_mm(instances)

    assert_in_delta(before_origins[2] - 50.0, after_origins[2], DELTA_TOLERANCE_MM)
    assert_in_delta(350.0, RowsTestHarness.instance_width_mm(second), DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[0], after_origins[0], DELTA_TOLERANCE_MM)
  end

  def test_missing_neighbor_is_skipped_safely
    _row_id, instances = RowsTestHarness.build_row(widths_mm: [600.0, 400.0, 800.0])
    _, second, third = instances

    third.erase!
    refute(third.valid?)

    result = RowsTestHarness.apply_reflow!(
      instance: second,
      new_width_mm: 460.0,
      scope: :instance_only
    )

    assert(result.ok?)
    after_origins = RowsTestHarness.member_origins_mm([instances[0], second])
    assert_in_delta(0.0, after_origins.first, DELTA_TOLERANCE_MM)
    assert_in_delta(460.0, RowsTestHarness.instance_width_mm(second), DELTA_TOLERANCE_MM)
  end
end

class TC_Rows_Reflow_AllInstances < TestUp::TestCase
  DELTA_TOLERANCE_MM = 0.01

  def setup
    RowsTestHarness.reset_model!
  end

  def teardown
    RowsTestHarness.reset_model!
  end

  def test_all_instances_delta_accumulates
    _row_id, instances = RowsTestHarness.build_row(widths_mm: [600.0, 400.0, 600.0, 700.0])
    first, second, third, _fourth = instances

    assert_equal(first.definition, third.definition)

    before_origins = RowsTestHarness.member_origins_mm(instances)

    result = RowsTestHarness.apply_reflow!(
      instance: first,
      new_width_mm: 630.0,
      scope: :all_instances
    )

    assert(result.ok?)

    after_origins = RowsTestHarness.member_origins_mm(instances)

    assert_in_delta(before_origins[1] + 30.0, after_origins[1], DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[2] + 30.0, after_origins[2], DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[3] + 60.0, after_origins[3], DELTA_TOLERANCE_MM)

    assert_in_delta(630.0, RowsTestHarness.instance_width_mm(first), DELTA_TOLERANCE_MM)
    assert_in_delta(630.0, RowsTestHarness.instance_width_mm(third), DELTA_TOLERANCE_MM)
  end
end

class TC_Rows_Reflow_LockLength < TestUp::TestCase
  DELTA_TOLERANCE_MM = 0.01

  def setup
    RowsTestHarness.reset_model!
  end

  def teardown
    RowsTestHarness.reset_model!
  end

  def test_lock_length_adjusts_filler
    model = Sketchup.active_model
    row_id, instances = RowsTestHarness.build_row(widths_mm: [600.0, 400.0, 200.0])
    _, middle, filler = instances

    AICabinets::Rows.update(model: model, row_id: row_id, lock_total_length: true)

    before_length = RowsTestHarness.total_length_mm(instances)

    result = RowsTestHarness.apply_reflow!(
      instance: middle,
      new_width_mm: 440.0,
      scope: :instance_only
    )

    assert(result.ok?)

    assert_in_delta(before_length, RowsTestHarness.total_length_mm(instances), DELTA_TOLERANCE_MM)
    assert_in_delta(160.0, RowsTestHarness.instance_width_mm(filler), DELTA_TOLERANCE_MM)
  end

  def test_lock_length_failure_raises
    model = Sketchup.active_model
    row_id, instances = RowsTestHarness.build_row(widths_mm: [600.0, 400.0, 100.0])
    _, middle, filler = instances

    AICabinets::Rows.update(model: model, row_id: row_id, lock_total_length: true)

    before_width = RowsTestHarness.instance_width_mm(filler)

    assert_raises(AICabinets::Rows::RowError) do
      RowsTestHarness.apply_reflow!(
        instance: middle,
        new_width_mm: 520.0,
        scope: :instance_only
      )
    end

    assert_in_delta(before_width, RowsTestHarness.instance_width_mm(filler), DELTA_TOLERANCE_MM)
  end
end

class TC_Rows_Reflow_UndoRedo < TestUp::TestCase
  DELTA_TOLERANCE_MM = 0.01

  def setup
    RowsTestHarness.reset_model!
  end

  def teardown
    RowsTestHarness.reset_model!
  end

  def test_reflow_is_single_operation_with_undo_redo
    _row_id, instances = RowsTestHarness.build_row(widths_mm: [600.0, 400.0, 800.0])
    _, middle, third = instances

    before_origins = RowsTestHarness.member_origins_mm(instances)

    operation_count = RowsTestHarness.count_operations do
      RowsTestHarness.apply_reflow!(
        instance: middle,
        new_width_mm: 450.0,
        scope: :instance_only
      )
    end

    assert_includes([0, 1], operation_count)

    after_origins = RowsTestHarness.member_origins_mm(instances)
    assert_in_delta(before_origins[2] + 50.0, after_origins[2], DELTA_TOLERANCE_MM)

    Sketchup.undo
    undo_origins = RowsTestHarness.member_origins_mm(instances)
    assert_in_delta(before_origins[2], undo_origins[2], DELTA_TOLERANCE_MM)

    Sketchup.redo
    redo_origins = RowsTestHarness.member_origins_mm(instances)
    assert_in_delta(after_origins[2], redo_origins[2], DELTA_TOLERANCE_MM)
  end
end
