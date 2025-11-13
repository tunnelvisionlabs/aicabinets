# frozen_string_literal: true

# Consolidated Rows reflow and reveal scenarios. Tests rely on the shared
# RowsTestHarness and helpers under tests/support to keep geometry checks
# consistent across reflow and reveal validations.
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/model_query'
require_relative '../support/rows_reveal_helpers'
require_relative '../support/rows_test_harness'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/reflow')
Sketchup.require('aicabinets/rows/reveal')
Sketchup.require('aicabinets/test_harness')

class TC_Rows_ReflowAndReveal < TestUp::TestCase
  include RowsRevealTestHelpers

  REVEAL_MM = 3.0
  LEGACY_MM = RowsRevealTestHelpers::LEGACY_EDGE_REVEAL_MM
  REVEAL_TOLERANCE_MM = 0.1
  REFLOW_DELTA_TOLERANCE_MM = 0.01
  REFLOW_DELTA_MM = 50.0

  def setup
    RowsTestHarness.reset_model!
  end

  def teardown
    RowsTestHarness.reset_model!
  end

  # -- Reveal behaviors -----------------------------------------------------

  def test_reveal_applies_to_supported_overlay_types
    [:frameless_overlay, :face_frame_overlay].each do |overlay_type|
      row_id, instances = build_row(widths_mm: [600.0, 500.0, 500.0], overlay_type: overlay_type)
      apply_row_reveal!(row_id: row_id, reveal_mm: REVEAL_MM)

      first, second, third = instances
      gap_left_middle = interior_gap_mm(first, second)
      gap_middle_right = interior_gap_mm(second, third)

      AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_left_middle, REVEAL_TOLERANCE_MM)
      AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_middle_right, REVEAL_TOLERANCE_MM)

      left_end = left_end_gap_mm(first)
      right_end = right_end_gap_mm(third)

      AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, left_end, REVEAL_TOLERANCE_MM)
      AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, right_end, REVEAL_TOLERANCE_MM)

      RowsTestHarness.reset_model!
    end
  end

  def test_reveal_stays_uniform_after_reflow
    row_id, instances = build_row(widths_mm: [600.0, 500.0, 450.0])
    apply_row_reveal!(row_id: row_id, reveal_mm: REVEAL_MM)

    first, second, third = instances
    before_origin = cabinet_origin_mm(first)
    original_width = cabinet_width_mm(second)

    result = AICabinets::Rows::Reflow.apply_width_change!(
      instance: second,
      new_width_mm: original_width + REFLOW_DELTA_MM,
      scope: :instance_only
    )
    assert(result.ok?)

    after_origin = cabinet_origin_mm(first)
    AICabinetsTestHelper.assert_within_tolerance(self, before_origin, after_origin, REVEAL_TOLERANCE_MM)

    gap_left_middle = interior_gap_mm(first, second)
    gap_middle_right = interior_gap_mm(second, third)

    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_left_middle, REVEAL_TOLERANCE_MM)
    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_middle_right, REVEAL_TOLERANCE_MM)
  end

  def test_opt_out_causes_exposed_boundary
    row_id, instances = build_row(widths_mm: [600.0, 500.0, 450.0])
    first, second, third = instances

    set_use_row_reveal(third, false)

    apply_row_reveal!(row_id: row_id, reveal_mm: REVEAL_MM)

    gap_left_middle = interior_gap_mm(first, second)
    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_left_middle, REVEAL_TOLERANCE_MM)

    middle_right_trim = right_end_gap_mm(second)
    right_left_trim = left_end_gap_mm(third)

    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, middle_right_trim, REVEAL_TOLERANCE_MM)
    AICabinetsTestHelper.assert_within_tolerance(self, LEGACY_MM, right_left_trim, REVEAL_TOLERANCE_MM)
  end

  def test_uniform_interior_and_end_gaps
    row_id, _instances = build_row(widths_mm: [600.0, 450.0, 500.0])
    refute_nil(row_id)

    apply_row_reveal!(row_id: row_id, reveal_mm: REVEAL_MM)

    gaps = RowsTestHarness.measure_boundary_gaps_mm(row_id: row_id)
    refute_empty(gaps)

    gaps.each do |gap|
      AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap, REVEAL_TOLERANCE_MM)
    end
  end

  # -- Reflow behaviors -----------------------------------------------------

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

    assert_in_delta(before_origins[0], after_origins[0], REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[1], after_origins[1], REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[2] + 50.0, after_origins[2], REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(450.0, RowsTestHarness.instance_width_mm(second), REFLOW_DELTA_TOLERANCE_MM)
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

    assert_in_delta(before_origins[2] - 50.0, after_origins[2], REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(350.0, RowsTestHarness.instance_width_mm(second), REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[0], after_origins[0], REFLOW_DELTA_TOLERANCE_MM)
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
    assert_in_delta(0.0, after_origins.first, REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(460.0, RowsTestHarness.instance_width_mm(second), REFLOW_DELTA_TOLERANCE_MM)
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

    assert_in_delta(before_origins[1] + 30.0, after_origins[1], REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[2] + 30.0, after_origins[2], REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(before_origins[3] + 60.0, after_origins[3], REFLOW_DELTA_TOLERANCE_MM)

    assert_in_delta(630.0, RowsTestHarness.instance_width_mm(first), REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(630.0, RowsTestHarness.instance_width_mm(third), REFLOW_DELTA_TOLERANCE_MM)
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

    assert_in_delta(before_length, RowsTestHarness.total_length_mm(instances), REFLOW_DELTA_TOLERANCE_MM)
    assert_in_delta(160.0, RowsTestHarness.instance_width_mm(filler), REFLOW_DELTA_TOLERANCE_MM)
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

    assert_in_delta(before_width, RowsTestHarness.instance_width_mm(filler), REFLOW_DELTA_TOLERANCE_MM)
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
    assert_in_delta(before_origins[2] + 50.0, after_origins[2], REFLOW_DELTA_TOLERANCE_MM)

    Sketchup.undo
    undo_origins = RowsTestHarness.member_origins_mm(instances)
    assert_in_delta(before_origins[2], undo_origins[2], REFLOW_DELTA_TOLERANCE_MM)

    Sketchup.redo
    redo_origins = RowsTestHarness.member_origins_mm(instances)
    assert_in_delta(after_origins[2], redo_origins[2], REFLOW_DELTA_TOLERANCE_MM)
  end
end
