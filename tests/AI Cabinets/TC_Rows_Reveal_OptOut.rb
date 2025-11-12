# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/model_query'
require_relative '../support/rows_reveal_helpers'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/reveal')
Sketchup.require('aicabinets/test_harness')

class TC_Rows_Reveal_OptOut < TestUp::TestCase
  include RowsRevealTestHelpers

  REVEAL_MM = 3.0
  LEGACY_MM = RowsRevealTestHelpers::LEGACY_EDGE_REVEAL_MM
  TOLERANCE_MM = 0.1

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_opt_out_causes_exposed_boundary
    row_id, instances = build_row(widths_mm: [600.0, 500.0, 450.0])
    first, second, third = instances

    set_use_row_reveal(third, false)

    apply_row_reveal!(row_id: row_id, reveal_mm: REVEAL_MM)

    gap_left_middle = interior_gap_mm(first, second)
    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_left_middle, TOLERANCE_MM)

    middle_right_trim = right_end_gap_mm(second)
    right_left_trim = left_end_gap_mm(third)

    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, middle_right_trim, TOLERANCE_MM)
    AICabinetsTestHelper.assert_within_tolerance(self, LEGACY_MM, right_left_trim, TOLERANCE_MM)
  end
end
