# frozen_string_literal: true

begin
  require 'testup/testcase'
rescue LoadError
  warn('SketchUp TestUp not available; skipping five-piece persistence tests.')
else
  require_relative 'suite_helper'

  Sketchup.require('aicabinets/geometry/five_piece')
  Sketchup.require('aicabinets/geometry/five_piece_panel')
  Sketchup.require('aicabinets/params/five_piece')

  class TC_Persistence_On_Definition < TestUp::TestCase
    def setup
      AICabinetsTestHelper.clean_model!
    end

    def teardown
      AICabinetsTestHelper.clean_model!
    end

    def test_params_round_trip_on_definition
      params = AICabinets::Params::FivePiece.defaults.merge(frame_material_id: 'maple', panel_material_id: 'maple_panel')
      definition = Sketchup.active_model.definitions.add('Five Piece Persistence')

      AICabinets::Params::FivePiece.write!(definition, params: params)
      stored = AICabinets::Params::FivePiece.read(definition)

      assert_equal(params[:stile_width_mm], stored[:stile_width_mm])
      assert_equal('five_piece', stored[:door_type])

      frame = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: stored,
        open_w_mm: 500.0,
        open_h_mm: 600.0
      )
      panel = AICabinets::Geometry::FivePiecePanel.build_panel!(
        target: definition,
        params: stored,
        open_w_mm: 500.0,
        open_h_mm: 600.0
      )

      door_dict = definition.attribute_dictionary(AICabinets::Params::FivePiece::DICTIONARY_NAME)
      refute_nil(door_dict)
      assert_equal(params[:stile_width_mm], door_dict[AICabinets::Params::FivePiece.send(:storage_key_for, :stile_width_mm)])

      (frame[:stiles] + frame[:rails]).each do |group|
        dictionary = group.attribute_dictionary(AICabinets::Geometry::FivePiece::GROUP_DICTIONARY)
        assert(dictionary)
        assert_includes(%w[stile rail], dictionary[AICabinets::Geometry::FivePiece::GROUP_ROLE_KEY].to_s)
        assert_equal('AICabinets/Fronts', group.layer.name)
      end

      panel_dictionary = panel[:panel].attribute_dictionary(AICabinets::Geometry::FivePiecePanel::PANEL_DICTIONARY)
      assert(panel_dictionary)
      assert_equal(AICabinets::Geometry::FivePiecePanel::PANEL_ROLE_VALUE, panel_dictionary[AICabinets::Geometry::FivePiecePanel::PANEL_ROLE_KEY])
      assert_equal('AICabinets/Fronts', panel[:panel].layer.name)
    end
  end
end
