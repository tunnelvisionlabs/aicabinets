# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/geom/five_piece')
Sketchup.require('aicabinets/geometry/five_piece_panel')
Sketchup.require('aicabinets/params/five_piece')
Sketchup.require('aicabinets/capabilities')

class TC_FivePiecePanel < TestUp::TestCase
  VALID_PARAMS = AICabinets::Params::FivePiece.defaults.merge(
    door_thickness_mm: 19.0,
    groove_width_mm: 18.0,
    groove_depth_mm: 11.0
  ).freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_flat_panel_dimensions_and_thickness
    params = build_params
    definition = build_frame_definition('Five Piece Panel AC1', params:, open_w_mm: 600.0, open_h_mm: 720.0)

    result = AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 600.0,
      open_h_mm: 720.0,
      style: :flat
    )

    panel = result[:panel]
    refute_nil(panel)

    bbox = panel.bounds
    width_mm = AICabinetsTestHelper.mm_from_length(bbox.width)
    height_mm = AICabinetsTestHelper.mm_from_length(bbox.height)
    depth_mm = AICabinetsTestHelper.mm_from_length(bbox.depth)

    expected_w = 600.0 - (2.0 * params[:panel_clearance_per_side_mm])
    expected_h = 720.0 - (2.0 * params[:panel_clearance_per_side_mm])

    AICabinetsTestHelper.assert_within_tolerance(self, expected_w, width_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, expected_h, height_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, params[:panel_thickness_mm], depth_mm)

    refute_nil(panel.volume)
  end

  def test_raised_and_reverse_profiles_present
    params = build_params(panel_cove_radius_mm: 14.0)
    definition = build_frame_definition('Five Piece Panel AC2', params:, open_w_mm: 620.0, open_h_mm: 740.0)

    raised = AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 620.0,
      open_h_mm: 740.0,
      style: :raised
    )

    edges_front = edges_at_face_y(raised[:panel], front: true)
    edges_back = edges_at_face_y(raised[:panel], front: false)

    assert_operator(edges_front.length, :>, edges_back.length)
    refute_nil(raised[:panel].volume)

    reverse = AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 620.0,
      open_h_mm: 740.0,
      style: :reverse_raised
    )

    edges_front_after = edges_at_face_y(reverse[:panel], front: true)
    edges_back_after = edges_at_face_y(reverse[:panel], front: false)

    assert_operator(edges_back_after.length, :>, edges_front_after.length)
    refute_nil(reverse[:panel].volume)
  end

  def test_opening_inference_matches_frame
    params = build_params
    definition = build_frame_definition('Five Piece Panel AC3', params:, open_w_mm: 640.0, open_h_mm: 760.0)

    result = AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params
    )

    bbox = result[:panel].bounds
    width_mm = AICabinetsTestHelper.mm_from_length(bbox.width)
    height_mm = AICabinetsTestHelper.mm_from_length(bbox.height)

    expected_w = 640.0 - (2.0 * params[:panel_clearance_per_side_mm])
    expected_h = 760.0 - (2.0 * params[:panel_clearance_per_side_mm])

    AICabinetsTestHelper.assert_within_tolerance(self, expected_w, width_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, expected_h, height_mm)
  end

  def test_panel_too_thick_for_groove_raises
    params = build_params(panel_thickness_mm: 11.0)
    definition = build_frame_definition('Five Piece Panel AC4', params:, open_w_mm: 600.0, open_h_mm: 720.0)

    assert_raises(AICabinets::ValidationError) do
      AICabinets::Geometry::FivePiecePanel.build_panel!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )
    end
  end

  def test_panel_tag_and_material
    material_name = 'Panel Maple'
    params = build_params(panel_material_id: material_name)
    definition = build_frame_definition('Five Piece Panel AC5', params:, open_w_mm: 600.0, open_h_mm: 720.0)

    result = AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 600.0,
      open_h_mm: 720.0
    )

    panel = result[:panel]
    refute_nil(panel)

    assert_equal('AICabinets/Fronts', panel.layer.name)
    assert_equal(material_name, panel.material&.name)
  end

  def test_panel_build_is_single_undo
    params = build_params
    definition = build_frame_definition('Five Piece Panel AC6', params:, open_w_mm: 600.0, open_h_mm: 720.0)

    AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 600.0,
      open_h_mm: 720.0
    )

    refute_nil(panel_group(definition))

    Sketchup.undo

    assert_nil(panel_group(definition))
  end

  def test_panel_generation_is_idempotent
    params = build_params
    definition = build_frame_definition('Five Piece Panel AC7', params:, open_w_mm: 580.0, open_h_mm: 700.0)

    AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 580.0,
      open_h_mm: 700.0
    )

    AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 580.0,
      open_h_mm: 700.0
    )

    assert_equal(1, panel_groups(definition).length)
  end

  def test_panel_clearance_respected
    params = build_params(panel_clearance_per_side_mm: 4.0)
    definition = build_frame_definition('Five Piece Panel AC8', params:, open_w_mm: 620.0, open_h_mm: 720.0)

    result = AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 620.0,
      open_h_mm: 720.0
    )

    bbox = result[:panel].bounds
    min = bbox.min

    stile = params[:stile_width_mm]
    rail = params[:rail_width_mm]
    clearance = params[:panel_clearance_per_side_mm]

    min_x_mm = AICabinetsTestHelper.mm_from_length(min.x)
    min_z_mm = AICabinetsTestHelper.mm_from_length(min.z)

    expected_x = stile + clearance
    expected_z = rail + clearance

    tolerance = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    AICabinetsTestHelper.assert_within_tolerance(self, expected_x, min_x_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, expected_z, min_z_mm)
  end

  private

  def build_params(overrides = {})
    VALID_PARAMS.merge(overrides)
  end

  def build_frame_definition(name, params:, open_w_mm:, open_h_mm:)
    definition = Sketchup.active_model.definitions.add(name)

    with_solid_booleans(true) do
      AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: open_w_mm,
        open_h_mm: open_h_mm
      )
    end

    definition
  end

  def panel_groups(definition)
    definition.entities.grep(Sketchup::Group).select do |group|
      dictionary = group.attribute_dictionary(AICabinets::Geometry::FivePiece::PANEL_DICTIONARY)
      dictionary && dictionary[AICabinets::Geometry::FivePiece::PANEL_ROLE_KEY] ==
        AICabinets::Geometry::FivePiece::PANEL_ROLE_VALUE
    end
  end

  def panel_group(definition)
    panel_groups(definition).first
  end

  def edges_at_face_y(panel, front: true)
    return [] unless panel&.valid?

    bbox = panel.bounds
    target_y = front ? bbox.min.y : bbox.max.y
    tolerance = AICabinetsTestHelper::TOL

    panel.entities.grep(Sketchup::Edge).select do |edge|
      positions = edge.vertices.map(&:position)
      positions.all? { |point| (point.y - target_y).abs <= tolerance }
    end
  end

  def with_solid_booleans(value)
    original = AICabinets::Capabilities.method(:solid_booleans?)
    AICabinets::Capabilities.define_singleton_method(:solid_booleans?) { value }

    yield
  ensure
    AICabinets::Capabilities.define_singleton_method(:solid_booleans?, original)
  end
end
