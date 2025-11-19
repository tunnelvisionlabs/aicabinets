# frozen_string_literal: true

begin
  require 'testup/testcase'
rescue LoadError
  warn('SketchUp TestUp not available; skipping five-piece panel style tests.')
else
  require_relative 'suite_helper'

  Sketchup.require('aicabinets/geometry/five_piece_panel')
  Sketchup.require('aicabinets/params/five_piece')
  Sketchup.require('aicabinets/testing')

  class TC_FivePiece_Panel_Styles < TestUp::TestCase
    def setup
      AICabinetsTestHelper.clean_model!
    end

    def teardown
      AICabinetsTestHelper.clean_model!
    end

    def test_flat_panel_fit_dimensions
      definition = Sketchup.active_model.definitions.add('Five Piece Panel Flat')
      params = AICabinets::Params::FivePiece.defaults.merge(panel_style: 'flat')

      result = AICabinets::Geometry::FivePiecePanel.build_panel!(
        target: definition,
        params: params,
        style: :flat,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )

      panel = result[:panel]
      bounds = panel.bounds

      fit_w = 600.0 - (2.0 * params[:panel_clearance_per_side_mm])
      fit_h = 720.0 - (2.0 * params[:panel_clearance_per_side_mm])

      assert_in_delta(fit_w, bounds.width.to_mm, AICabinets::Testing.tolerance)
      assert_in_delta(fit_h, bounds.height.to_mm, AICabinets::Testing.tolerance)
      assert_in_delta(params[:panel_thickness_mm], bounds.depth.to_mm, AICabinets::Testing.tolerance)
      assert(panel.volume.positive?) if panel.respond_to?(:volume)
    end

    def test_reverse_raised_flips_orientation
      definition = Sketchup.active_model.definitions.add('Five Piece Panel Reverse Raised')
      params = AICabinets::Params::FivePiece.defaults.merge(panel_style: 'reverse_raised', panel_thickness_mm: 18.0)

      result = AICabinets::Geometry::FivePiecePanel.build_panel!(
        target: definition,
        params: params,
        style: :reverse_raised,
        open_w_mm: 500.0,
        open_h_mm: 500.0
      )

      panel = result[:panel]
      yaxis = panel.transformation.yaxis
      assert(yaxis.y.negative?, 'Reverse raised panel should flip Y axis')
      assert(panel.volume.positive?) if panel.respond_to?(:volume)
    end
  end
end
