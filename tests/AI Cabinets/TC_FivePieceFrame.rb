# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/geometry/five_piece')
Sketchup.require('aicabinets/params/five_piece')
Sketchup.require('aicabinets/capabilities')

class TC_FivePieceFrame < TestUp::TestCase
  VALID_PARAMS = AICabinets::Params::FivePiece.defaults.merge(
    door_thickness_mm: 19.0,
    groove_width_mm: 18.0
  ).freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_build_creates_coped_frame_with_defaults
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame AC1')

    with_solid_booleans(true) do
      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )

      assert_equal(:boolean_subtract, result[:coping_mode])
      assert_empty(result[:warnings])
    end

    groups = definition.entities.grep(Sketchup::Group)
    assert_equal(4, groups.length)

    bounds_min = AICabinetsTestHelper.bbox_local_of(definition).min
    mm_min_x = AICabinetsTestHelper.mm_from_length(bounds_min.x)
    mm_min_y = AICabinetsTestHelper.mm_from_length(bounds_min.y)
    mm_min_z = AICabinetsTestHelper.mm_from_length(bounds_min.z)

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)

    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, mm_min_x)
    assert_operator(mm_min_y, :<=, tolerance_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, mm_min_z)

    groups.each do |group|
      assert_equal('AICabinets/Fronts', group.layer.name)
      assert_instance_of(Sketchup::Material, group.material)
      assert_equal('Maple', group.material.name)
    end
  end

  def test_inside_edges_include_shaker_profile
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame AC2')
    profile_depth = AICabinets::Geometry::FivePiece::SHAKER_PROFILE_DEPTH_MM
    profile_run = AICabinets::Geometry::FivePiece::SHAKER_PROFILE_RUN_MM

    with_solid_booleans(true) do
      AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 620.0,
        open_h_mm: 740.0
      )
    end

    groups = definition.entities.grep(Sketchup::Group)
    refute_empty(groups)

    expected_edge_mm = Math.sqrt((profile_depth**2) + (profile_run**2))

    groups.each do |group|
      assert(shaker_profile_present?(group, expected_edge_mm), 'Expected Shaker diagonal edge to be present')
    end
  end

  def test_boolean_coping_trims_rails
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame AC3')
    open_w_mm = 640.0
    stile_width_mm = params[:stile_width_mm]

    result = nil
    with_solid_booleans(true) do
      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: open_w_mm,
        open_h_mm: 720.0
      )
    end

    assert_equal(:boolean_subtract, result[:coping_mode])

    expected_length = open_w_mm - (2.0 * stile_width_mm)
    result[:rails].each do |rail|
      length_mm = rail_length_mm(rail)
      AICabinetsTestHelper.assert_within_tolerance(self, expected_length, length_mm)
    end
  end

  def test_square_fallback_emits_warning
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame AC4')
    open_w_mm = 610.0
    stile_width_mm = params[:stile_width_mm]

    result = nil
    with_solid_booleans(false) do
      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: open_w_mm,
        open_h_mm: 720.0
      )
    end

    assert_equal(:square_fallback, result[:coping_mode])
    assert(result[:warnings].any? { |message| message.include?('solid boolean') })

    expected_length = open_w_mm - (2.0 * stile_width_mm)
    result[:rails].each do |rail|
      length_mm = rail_length_mm(rail)
      AICabinetsTestHelper.assert_within_tolerance(self, expected_length, length_mm)
    end
  end

  def test_build_is_single_undo_operation
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame AC5')
    model = Sketchup.active_model

    with_solid_booleans(true) do
      AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )
    end

    refute_empty(definition.entities.grep(Sketchup::Group))

    Sketchup.undo

    assert_empty(definition.entities.grep(Sketchup::Group))
  end

  def test_rail_width_defaults_to_stile_width
    params = build_params(rail_width_mm: nil)
    definition = Sketchup.active_model.definitions.add('Five Piece Frame AC6')
    stile_width_mm = params[:stile_width_mm]

    result = nil
    with_solid_booleans(true) do
      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 620.0,
        open_h_mm: 720.0
      )
    end

    result[:rails].each do |rail|
      height_mm = rail_height_mm(rail)
      AICabinetsTestHelper.assert_within_tolerance(self, stile_width_mm, height_mm)
    end
  end

  def test_frame_material_id_overrides_default
    material_name = 'Custom Maple'
    params = build_params(frame_material_id: material_name)
    definition = Sketchup.active_model.definitions.add('Five Piece Frame AC7')

    with_solid_booleans(true) do
      AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )
    end

    groups = definition.entities.grep(Sketchup::Group)
    refute_empty(groups)

    groups.each do |group|
      assert_equal(material_name, group.material&.name)
    end
  end

  def test_groups_are_manifold_solids
    params = build_params
    definition = Sketchup.active_model.definitions.add('Five Piece Frame AC8')

    result = nil
    with_solid_booleans(true) do
      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 640.0,
        open_h_mm: 740.0
      )
    end

    (result[:stiles] + result[:rails]).each do |group|
      assert(group.valid?)
      if group.respond_to?(:volume)
        assert_operator(group.volume, :>, 0.0)
      end
    end
  end

  private

  def build_params(overrides = {})
    params = VALID_PARAMS.merge(overrides)
    AICabinets::Params::FivePiece.validate!(params: params)
  end

  def shaker_profile_present?(group, expected_length_mm)
    edges = group.entities.grep(Sketchup::Edge)
    edges.any? do |edge|
      length_mm = AICabinetsTestHelper.mm_from_length(edge.length)
      (length_mm - expected_length_mm).abs <= 0.5
    end
  end

  def rail_length_mm(group)
    bounds = group.bounds
    AICabinetsTestHelper.mm_from_length(bounds.max.x - bounds.min.x)
  end

  def rail_height_mm(group)
    bounds = group.bounds
    AICabinetsTestHelper.mm_from_length(bounds.max.z - bounds.min.z)
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
