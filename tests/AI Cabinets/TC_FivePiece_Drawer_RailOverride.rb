# frozen_string_literal: true

begin
  require 'testup/testcase'
rescue LoadError
  warn('SketchUp TestUp not available; skipping drawer rail override tests.')
else
  require_relative 'suite_helper'

  Sketchup.require('aicabinets/geometry/five_piece')
  Sketchup.require('aicabinets/params/five_piece')
  Sketchup.require('aicabinets/rules/five_piece')

  class TC_FivePiece_Drawer_RailOverride < TestUp::TestCase
    def setup
      AICabinetsTestHelper.clean_model!
    end

    def teardown
      AICabinetsTestHelper.clean_model!
    end

    def test_rail_width_clamped_for_short_drawer
      params = AICabinets::Params::FivePiece.defaults.merge(
        drawer_rail_width_mm: 20.0,
        min_drawer_rail_width_mm: 38.0,
        min_panel_opening_mm: 70.0
      )

      decision = AICabinets::Rules::FivePiece.evaluate_drawer_front(
        open_outside_w_mm: 450.0,
        open_outside_h_mm: 140.0,
        params: params
      )

      assert_equal(:five_piece, decision.action)
      assert_in_delta(38.0, decision.effective_rail_mm, 1e-6)
      assert_equal(:clamped_rail, decision.reason)
      assert_equal(1, decision.messages.uniq.length)

      definition = Sketchup.active_model.definitions.add('Five Piece Drawer Rail Override')
      geometry = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params.merge(rail_width_mm: decision.effective_rail_mm),
        open_w_mm: 450.0,
        open_h_mm: 140.0 + (2.0 * decision.effective_rail_mm)
      )

      assert_equal(4, geometry[:stiles].length + geometry[:rails].length)
    end
  end
end
