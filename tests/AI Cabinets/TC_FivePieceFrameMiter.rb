# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/geometry/five_piece')
Sketchup.require('aicabinets/params/five_piece')
Sketchup.require('aicabinets/capabilities')

class TC_FivePieceFrameMiter < TestUp::TestCase
  VALID_PARAMS = AICabinets::Params::FivePiece.defaults.merge(
    door_thickness_mm: 19.0,
    groove_width_mm: 18.0,
    joint_type: 'miter'
  ).freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_build_creates_mitered_frame
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame Miter AC1')

    result = AICabinets::Geometry::FivePiece.build_frame!(
      target: definition,
      params: params,
      open_w_mm: 600.0,
      open_h_mm: 720.0
    )

    assert_equal(:miter, result[:joint_type])
    refute_nil(result[:miter_mode])

    groups = definition.entities.grep(Sketchup::Group)
    assert_equal(4, groups.length)

    outside_w_mm = 600.0 + (2.0 * params[:stile_width_mm])
    outside_h_mm = 720.0 + (2.0 * params[:rail_width_mm])
    bounds = AICabinetsTestHelper.bbox_local_of(definition)

    width_mm = AICabinetsTestHelper.mm_from_length(bounds.max.x - bounds.min.x)
    thickness_mm = AICabinetsTestHelper.mm_from_length(bounds.max.y - bounds.min.y)
    height_mm = AICabinetsTestHelper.mm_from_length(bounds.max.z - bounds.min.z)

    AICabinetsTestHelper.assert_within_tolerance(self, outside_w_mm, width_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, params[:door_thickness_mm], thickness_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, outside_h_mm, height_mm)

    groups.each do |group|
      assert_equal('AICabinets/Fronts', group.layer.name)
      assert(group.volume.positive?) if group.respond_to?(:volume)
    end
  end

  def test_miter_faces_have_45_degree_normal
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame Miter AC2')

    result = AICabinets::Geometry::FivePiece.build_frame!(
      target: definition,
      params: params,
      open_w_mm: 500.0,
      open_h_mm: 500.0
    )

    refute_empty(result[:stiles])
    faces = result[:stiles].first.entities.grep(Sketchup::Face)
    diagonal_face = faces.find { |face| (face.normal.x.abs - face.normal.z.abs).abs < 1e-6 && face.normal.y.abs < 0.1 }
    refute_nil(diagonal_face)
  end

  def test_undo_removes_frame
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame Miter AC3')
    model = Sketchup.active_model

    AICabinets::Geometry::FivePiece.build_frame!(
      target: definition,
      params: params,
      open_w_mm: 600.0,
      open_h_mm: 720.0
    )

    refute_empty(definition.entities.grep(Sketchup::Group))
    Sketchup.undo
    assert_empty(definition.entities.grep(Sketchup::Group))
  end

  def test_capability_fallback_sets_warning
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame Miter AC4')

    warnings = nil
    with_solid_booleans(false) do
      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 700.0
      )
      warnings = result[:warnings]
      assert_equal(:intersect, result[:miter_mode])
    end

    assert(warnings.any?)
  end

  def test_idempotent_regeneration
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame Miter AC5')

    2.times do
      AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 450.0,
        open_h_mm: 450.0
      )
    end

    groups = definition.entities.grep(Sketchup::Group)
    assert_equal(4, groups.length)
  end

  private

  def build_params(overrides = {})
    params = VALID_PARAMS.merge(overrides)
    AICabinets::Params::FivePiece.validate!(params: params)
  end

  def with_solid_booleans(value)
    capabilities = AICabinets::Capabilities
    singleton = class << capabilities; self; end
    original = capabilities.method(:solid_booleans?)
    singleton.send(:define_method, :solid_booleans?) { value }
    yield
  ensure
    singleton.send(:define_method, :solid_booleans?, original)
  end
end
