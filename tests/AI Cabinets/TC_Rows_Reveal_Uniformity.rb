# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/model_query'
require_relative '../support/rows_reveal_helpers'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/reflow')
Sketchup.require('aicabinets/rows/reveal')
Sketchup.require('aicabinets/test_harness')

class TC_Rows_Reveal_Uniformity < TestUp::TestCase
  include RowsRevealTestHelpers

  REVEAL_MM = 3.0
  TOLERANCE_MM = 0.1

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_uniform_interior_and_end_gaps
    model = Sketchup.active_model
    row_id, instances = build_row(widths_mm: [600.0, 450.0, 500.0])
    refute_nil(row_id)

    apply_row_reveal!(row_id: row_id, reveal_mm: REVEAL_MM)

    first, second, third = instances

    gap_left_middle = interior_gap_mm(first, second)
    gap_middle_right = interior_gap_mm(second, third)

    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_left_middle, TOLERANCE_MM)
    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_middle_right, TOLERANCE_MM)

    left_end_gap = left_end_gap_mm(first)
    right_end_gap = right_end_gap_mm(third)

    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, left_end_gap, TOLERANCE_MM)
    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, right_end_gap, TOLERANCE_MM)
  end
end
