# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/ui/dialogs/fronts_dialog')
Sketchup.require('aicabinets/params/five_piece')

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

    AICabinets::UI::Dialogs::FrontsDialog.send(:regenerate_front, definition, params)

    groups = definition.entities.grep(Sketchup::Group)
    refute_empty(groups, 'Expected regenerated front to create frame groups')
  end
end
