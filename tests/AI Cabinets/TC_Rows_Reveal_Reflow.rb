# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/model_query'
require_relative '../support/rows_reveal_helpers'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/reflow')
Sketchup.require('aicabinets/rows/reveal')
Sketchup.require('aicabinets/test_harness')

class TC_Rows_Reveal_Reflow < TestUp::TestCase
  include RowsRevealTestHelpers

  REVEAL_MM = 3.0
  DELTA_MM = 50.0
  TOLERANCE_MM = 0.1

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_reveal_stays_uniform_after_reflow
    row_id, instances = build_row(widths_mm: [600.0, 500.0, 450.0])
    apply_row_reveal!(row_id: row_id, reveal_mm: REVEAL_MM)

    first, second, third = instances
    before_origin = cabinet_origin_mm(first)

    original_width = cabinet_width_mm(second)

    result = AICabinets::Rows::Reflow.apply_width_change!(
      instance: second,
      new_width_mm: original_width + DELTA_MM,
      scope: :instance_only
    )
    assert(result.ok?)

    after_origin = cabinet_origin_mm(first)
    AICabinetsTestHelper.assert_within_tolerance(self, before_origin, after_origin, TOLERANCE_MM)

    gap_left_middle = interior_gap_mm(first, second)
    gap_middle_right = interior_gap_mm(second, third)

    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_left_middle, TOLERANCE_MM)
    AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap_middle_right, TOLERANCE_MM)
  end
end
