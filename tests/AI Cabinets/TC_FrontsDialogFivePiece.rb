# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/ui/dialogs/fronts_dialog')
Sketchup.require('aicabinets/params/five_piece')
Sketchup.require('aicabinets/geometry/five_piece_panel')
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

class TC_FrontsDialogFivePiece < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_defaults_include_panel_fields
    defaults = AICabinets::Params::FivePiece.defaults

    assert_equal('flat', defaults[:panel_style])
    assert_in_delta(12.0, defaults[:panel_cove_radius_mm], 1e-6)
    assert_in_delta(19.0, defaults[:door_thickness_mm], 1e-6)
    assert_in_delta(38.0, defaults[:min_drawer_rail_width_mm], 1e-6)
    assert_in_delta(60.0, defaults[:min_panel_opening_mm], 1e-6)
  end

  def test_regenerate_front_builds_groups
    model = Sketchup.active_model
    definition = model.definitions.add('Front Test')
    definition.entities.add_face(
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(500.mm, 0, 0),
      Geom::Point3d.new(500.mm, 0, 700.mm),
      Geom::Point3d.new(0, 0, 700.mm)
    ).pushpull(19.mm)

    params = AICabinets::Params::FivePiece.defaults
    params[:panel_style] = 'flat'

    AICabinets::UI::Dialogs::FrontsDialog.send(:regenerate_front_for_tests, definition, params)

    groups = definition.entities.grep(Sketchup::Group)
    refute_empty(groups, 'Expected regenerated front to create frame groups')
  end

  def test_regenerate_front_uses_finished_dimensions_for_openings
    finished_width_mm = 460.0
    finished_height_mm = 710.0
    definition = build_front_definition('Front Overlay', width_mm: finished_width_mm, height_mm: finished_height_mm)

    params = AICabinets::Params::FivePiece.defaults

    AICabinets::UI::Dialogs::FrontsDialog.send(:regenerate_front_for_tests, definition, params)

    open_w_mm, open_h_mm = AICabinets::Geometry::FivePiecePanel.opening_from_frame(definition: definition)

    stile_width = params[:stile_width_mm]
    rail_width = params[:rail_width_mm]
    expected_open_w = finished_width_mm - (2.0 * stile_width)
    expected_open_h = finished_height_mm - (2.0 * rail_width)

    assert_operator(open_w_mm, :>, 0.0)
    assert_operator(open_h_mm, :>, 0.0)
    assert_in_delta(expected_open_w, open_w_mm, 1e-3)
    assert_in_delta(expected_open_h, open_h_mm, 1e-3)
  end

  def test_regenerate_front_handles_narrow_finished_front
    params = AICabinets::Params::FivePiece.defaults
    stile_width = params[:stile_width_mm]
    min_opening_mm = 1.0
    finished_width_mm = (stile_width * 2.0) + min_opening_mm + 0.5
    finished_height_mm = (stile_width * 2.0) + min_opening_mm + 0.5

    definition = build_front_definition('Front Tight Fit', width_mm: finished_width_mm, height_mm: finished_height_mm)

    AICabinets::UI::Dialogs::FrontsDialog.send(:regenerate_front_for_tests, definition, params)

    groups = definition.entities.grep(Sketchup::Group)
    refute_empty(groups, 'Expected groups even when opening is near the minimum threshold')
  end

  def test_regenerate_front_clamps_excessive_frame_members
    finished_width_mm = 520.0
    finished_height_mm = 760.0
    definition = build_front_definition('Front Clamp', width_mm: finished_width_mm, height_mm: finished_height_mm)

    params = AICabinets::Params::FivePiece.defaults
    params[:stile_width_mm] = 200.0
    params[:rail_width_mm] = 180.0

    AICabinets::UI::Dialogs::FrontsDialog.send(:regenerate_front_for_tests, definition, params)

    groups = definition.entities.grep(Sketchup::Group)
    refute_empty(groups)

    max_stile = (finished_width_mm - 1.0) / 2.0
    max_rail = (finished_height_mm - 1.0) / 2.0

    assert_operator(params[:stile_width_mm], :<=, max_stile)
    assert_operator(params[:rail_width_mm], :<=, max_rail)
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
