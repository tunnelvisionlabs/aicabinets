# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/ui/dialogs/fronts_dialog')
Sketchup.require('aicabinets/rules/five_piece')
load File.expand_path('../../aicabinets/ui/dialogs/fronts_dialog.rb', __dir__)

module AICabinets
  module UI
    module Dialogs
      module FrontsDialog
        class << self
          private

          def regenerate_front_for_tests(target, params)
            regenerate_front_impl(target, params)
          end
        end
      end
    end
  end
end

class TC_DrawerShortRules < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_clamps_requested_drawer_rails
    params = AICabinets::Params::FivePiece.defaults
    params[:drawer_rail_width_mm] = 28.0
    params[:min_drawer_rail_width_mm] = 38.0
    params[:min_panel_opening_mm] = 60.0

    decision = AICabinets::Rules::FivePiece.evaluate_drawer_front(
      open_outside_w_mm: 400.0,
      open_outside_h_mm: 180.0,
      params: params
    )

    assert_equal(:five_piece, decision.action)
    assert_equal(:clamped_rail, decision.reason)
    assert_in_delta(38.0, decision.effective_rail_mm, 1e-6)
    assert_includes(decision.messages.first, 'clamped')
  end

  def test_slabs_when_panel_opening_too_small
    params = AICabinets::Params::FivePiece.defaults
    params[:drawer_rail_width_mm] = 42.0
    params[:min_drawer_rail_width_mm] = 38.0
    params[:min_panel_opening_mm] = 100.0

    decision = AICabinets::Rules::FivePiece.evaluate_drawer_front(
      open_outside_w_mm: 320.0,
      open_outside_h_mm: 140.0,
      params: params
    )

    assert_equal(:slab, decision.action)
    assert_equal(:too_short_for_panel, decision.reason)
    assert_operator(decision.panel_h_mm, :<, params[:min_panel_opening_mm])
  end

  def test_regeneration_uses_effective_drawer_rails
    width_mm = 400.0
    height_mm = 200.0
    definition = build_front_definition('Drawer Front', width_mm: width_mm, height_mm: height_mm)

    params = AICabinets::Params::FivePiece.defaults
    params[:drawer_rail_width_mm] = 20.0
    params[:min_drawer_rail_width_mm] = 40.0
    params[:min_panel_opening_mm] = 60.0

    result = AICabinets::UI::Dialogs::FrontsDialog.send(:regenerate_front_for_tests, definition, params)

    open_w_mm, open_h_mm = AICabinets::Geometry::FivePiecePanel.opening_from_frame(definition: definition)
    assert_operator(open_h_mm, :>, 0.0)
    assert_in_delta(height_mm - (2.0 * params[:min_drawer_rail_width_mm]), open_h_mm, 1e-3)

    action = definition.get_attribute(AICabinets::Params::FivePiece::DICTIONARY_NAME,
                                      'five_piece:last_drawer_rules_action')
    reason = definition.get_attribute(AICabinets::Params::FivePiece::DICTIONARY_NAME,
                                      'five_piece:last_drawer_rules_reason')

    assert_equal('five_piece', action)
    assert_equal('clamped_rail', reason)
    assert_nil(result[:warnings].detect { |message| message.to_s.include?('slab') })
  end

  private

  def build_front_definition(name, width_mm:, height_mm:, thickness_mm: 19.0)
    definition = Sketchup.active_model.definitions.add(name)
    face = definition.entities.add_face(
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(width_mm.mm, 0, 0),
      Geom::Point3d.new(width_mm.mm, 0, height_mm.mm),
      Geom::Point3d.new(0, 0, height_mm.mm)
    )
    face.pushpull(thickness_mm.mm)
    definition
  end
end

