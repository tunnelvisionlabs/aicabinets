# frozen_string_literal: true

require_relative 'test_helper'

require 'aicabinets/rules/five_piece'

class FivePieceRulesDrawerFrontTest < Minitest::Test
  def test_clamps_rail_width_and_reports_reason
    decision = AICabinets::Rules::FivePiece.evaluate_drawer_front(
      open_outside_w_mm: 400.0,
      open_outside_h_mm: 140.0,
      params: {
        stile_width_mm: 57.0,
        rail_width_mm: 44.0,
        drawer_rail_width_mm: 30.0,
        min_drawer_rail_width_mm: 38.0,
        min_panel_opening_mm: 50.0
      }
    )

    assert_equal(:five_piece, decision.action)
    assert_in_delta(38.0, decision.effective_rail_mm, 1e-6)
    assert_equal(:clamped_rail, decision.reason)
    refute_empty(decision.messages)
  end

  def test_switches_to_slab_when_panel_too_small
    decision = AICabinets::Rules::FivePiece.evaluate_drawer_front(
      open_outside_w_mm: 300.0,
      open_outside_h_mm: 120.0,
      params: {
        stile_width_mm: 57.0,
        rail_width_mm: 57.0,
        drawer_rail_width_mm: 57.0,
        min_drawer_rail_width_mm: 38.0,
        min_panel_opening_mm: 80.0
      }
    )

    assert_equal(:slab, decision.action)
    assert_equal(:too_short_for_panel, decision.reason)
    assert(decision.panel_h_mm < 80.0)
    refute_empty(decision.messages)
  end
end
