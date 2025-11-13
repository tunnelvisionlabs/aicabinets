# frozen_string_literal: true

require_relative 'rows_test_harness'

module RowsRevealTestHelpers
  DEFAULT_ROW_REVEAL_MM = 3.0
  LEGACY_EDGE_REVEAL_MM = 2.0

  module_function

  def build_row(widths_mm:, overlay_type: :frameless_overlay)
    RowsTestHarness.build_row(widths_mm: widths_mm, overlay_type: overlay_type)
  end

  def apply_row_reveal!(row_id:, reveal_mm: DEFAULT_ROW_REVEAL_MM)
    RowsTestHarness.set_row_reveal!(row_id: row_id, mm: reveal_mm)
    RowsTestHarness.apply_reveal!(row_id: row_id)
  end

  def interior_gap_mm(left_instance, right_instance)
    left_edges = RowsTestHarness.door_extents_world_mm(left_instance)
    right_edges = RowsTestHarness.door_extents_world_mm(right_instance)
    right_edges.first - left_edges.last
  end

  def left_end_gap_mm(instance)
    RowsTestHarness.door_left_gap_mm(instance)
  end

  def right_end_gap_mm(instance)
    RowsTestHarness.door_right_gap_mm(instance)
  end

  def cabinet_origin_mm(instance)
    RowsTestHarness.cabinet_origin_mm(instance)
  end

  def cabinet_width_mm(instance)
    RowsTestHarness.cabinet_width_mm(instance)
  end

  def set_use_row_reveal(instance, value)
    dictionary = instance.attribute_dictionary(AICabinets::Rows::Reveal::REVEAL_DICTIONARY, true)
    dictionary[AICabinets::Rows::Reveal::USE_ROW_REVEAL_KEY] = !!value
  end
end
