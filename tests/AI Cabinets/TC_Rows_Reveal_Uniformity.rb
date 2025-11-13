# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/model_query'
require_relative '../support/rows_reveal_helpers'
require_relative '../support/rows_test_harness'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/reflow')
Sketchup.require('aicabinets/rows/reveal')
Sketchup.require('aicabinets/test_harness')

class TC_Rows_Reveal_Uniformity < TestUp::TestCase
  include RowsRevealTestHelpers

  REVEAL_MM = 3.0
  TOLERANCE_MM = 0.1

  def setup
    RowsTestHarness.reset_model!
  end

  def teardown
    RowsTestHarness.reset_model!
  end

  def test_uniform_interior_and_end_gaps
    _model = Sketchup.active_model
    row_id, _instances = build_row(widths_mm: [600.0, 450.0, 500.0])
    refute_nil(row_id)

    apply_row_reveal!(row_id: row_id, reveal_mm: REVEAL_MM)

    gaps = RowsTestHarness.measure_boundary_gaps_mm(row_id: row_id)
    refute_empty(gaps)

    gaps.each do |gap|
      AICabinetsTestHelper.assert_within_tolerance(self, REVEAL_MM, gap, TOLERANCE_MM)
    end
  end
end
