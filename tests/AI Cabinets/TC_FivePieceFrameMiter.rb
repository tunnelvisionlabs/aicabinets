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
    joint_type: 'miter',
    inside_profile_id: 'shaker_inside'
  ).freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_build_with_booleans_creates_solid_miters
    params = build_params
    definition = Sketchup.active_model.definitions.add('Miter Frame AC1')

    result = nil
    with_solid_booleans(true) do
      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )
    end

    assert_equal(:miter, result[:joint_type])
    assert_equal(:boolean, result[:miter_mode])
    assert_empty(result[:warnings])

    groups = definition.entities.grep(Sketchup::Group)
    assert_equal(4, groups.length)

    groups.each do |group|
      assert(group.valid?)
      assert_operator(group.volume, :>, 0.0) if group.respond_to?(:volume)
      assert_miter_faces(group)
    end
  end

  def test_inside_profile_continuity
    params = build_params
    definition = Sketchup.active_model.definitions.add('Miter Frame AC2')

    open_w_mm = 620.0
    open_h_mm = 740.0

    with_solid_booleans(true) do
      AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: open_w_mm,
        open_h_mm: open_h_mm
      )
    end

    stiles, rails = partition_members(definition)
    refute_empty(stiles)
    refute_empty(rails)

    stile_width_mm = params[:stile_width_mm]
    rail_width_mm = params[:rail_width_mm] || stile_width_mm
    outside_w_mm = open_w_mm + (2.0 * stile_width_mm)
    outside_h_mm = open_h_mm + (2.0 * rail_width_mm)

    tolerance_mm = 0.25
    inside_corners = collect_inside_corner_pairs(
      stiles + rails,
      stile_width_mm: stile_width_mm,
      rail_width_mm: rail_width_mm,
      outside_width_mm: outside_w_mm,
      outside_height_mm: outside_h_mm,
      tolerance_mm: tolerance_mm
    )

    assert_equal(4, inside_corners.length)
    inside_corners.each_value do |vertices|
      assert(vertices.length >= 2, 'Expected each inside corner to have at least two members')
      first = vertices.first[:point]
      vertices.drop(1).each do |entry|
        delta = first.distance(entry[:point])
        mm_delta = delta.to_f * 25.4
        assert(mm_delta <= tolerance_mm, "Expected miter seam gap <= #{tolerance_mm}mm, got #{mm_delta}")
      end
    end
  end

  def test_dimensions_match_opening_inputs
    params = build_params
    definition = Sketchup.active_model.definitions.add('Miter Frame AC3')

    open_w_mm = 610.0
    open_h_mm = 730.0

    with_solid_booleans(true) do
      AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: open_w_mm,
        open_h_mm: open_h_mm
      )
    end

    stiles, rails = partition_members(definition)
    stile_width_mm = params[:stile_width_mm]
    rail_width_mm = params[:rail_width_mm]
    rail_width_mm = stile_width_mm if rail_width_mm.nil?

    outside_w_mm = open_w_mm + (2.0 * stile_width_mm)
    outside_h_mm = open_h_mm + (2.0 * rail_width_mm)

    stiles.each do |stile|
      bounds = stile.bounds
      height_mm = length_to_mm(bounds.max.z - bounds.min.z)
      AICabinetsTestHelper.assert_within_tolerance(self, outside_h_mm, height_mm, 0.5)
    end

    rails.each do |rail|
      bounds = rail.bounds
      length_mm = length_to_mm(bounds.max.x - bounds.min.x)
      AICabinetsTestHelper.assert_within_tolerance(self, outside_w_mm, length_mm, 0.5)
    end

    frame_bounds = AICabinetsTestHelper.bbox_local_of(definition)
    width_mm = length_to_mm(frame_bounds.max.x - frame_bounds.min.x)
    height_mm = length_to_mm(frame_bounds.max.z - frame_bounds.min.z)
    AICabinetsTestHelper.assert_within_tolerance(self, outside_w_mm, width_mm, 0.5)
    AICabinetsTestHelper.assert_within_tolerance(self, outside_h_mm, height_mm, 0.5)
  end

  def test_operation_is_atomic
    params = build_params
    definition = Sketchup.active_model.definitions.add('Miter Frame AC4')
    with_solid_booleans(true) do
      AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 640.0,
        open_h_mm: 740.0
      )
    end

    refute_empty(definition.entities.grep(Sketchup::Group))

    Sketchup.undo

    assert_empty(definition.entities.grep(Sketchup::Group))
  end

  def test_tagging_and_material_assignment
    params = build_params(frame_material_id: 'Quarter Sawn Oak')
    definition = Sketchup.active_model.definitions.add('Miter Frame AC5')

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
      assert_equal('AICabinets/Fronts', group.layer.name)
      assert_equal('Quarter Sawn Oak', group.material&.name)
    end
  end

  def test_intersection_fallback
    params = build_params
    definition = Sketchup.active_model.definitions.add('Miter Frame AC6')

    result = nil
    with_solid_booleans(false) do
      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )
    end

    assert_equal(:miter, result[:joint_type])
    assert_equal(:intersect, result[:miter_mode])
    assert(result[:warnings].any? { |message| message.include?('intersection') })

    groups = definition.entities.grep(Sketchup::Group)
    groups.each do |group|
      assert_operator(group.volume, :>, 0.0) if group.respond_to?(:volume)
    end
  end

  def test_idempotent_regeneration
    params = build_params
    definition = Sketchup.active_model.definitions.add('Miter Frame AC7')

    with_solid_booleans(true) do
      2.times do
        AICabinets::Geometry::FivePiece.build_frame!(
          target: definition,
          params: params,
          open_w_mm: 600.0,
          open_h_mm: 720.0
        )
      end
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

  def partition_members(definition)
    groups = definition.entities.grep(Sketchup::Group)
    stiles = groups.select do |group|
      dictionary = group.attribute_dictionary(AICabinets::Geometry::FivePiece::GROUP_DICTIONARY)
      dictionary && dictionary[AICabinets::Geometry::FivePiece::GROUP_ROLE_KEY] == AICabinets::Geometry::FivePiece::GROUP_ROLE_STILE
    end
    rails = groups - stiles
    [stiles, rails]
  end

  def collect_inside_corner_pairs(groups, stile_width_mm:, rail_width_mm:, outside_width_mm:, outside_height_mm:, tolerance_mm:)
    tolerance = tolerance_mm
    inside_x = [stile_width_mm, outside_width_mm - stile_width_mm]
    inside_z = [rail_width_mm, outside_height_mm - rail_width_mm]

    corners = Hash.new { |hash, key| hash[key] = [] }

    groups.each do |group|
      vertices = group.entities.grep(Sketchup::Edge).flat_map { |edge| [edge.start, edge.end] }
      vertices.uniq.each do |vertex|
        point = vertex.position
        x_mm = length_to_mm(point.x)
        z_mm = length_to_mm(point.z)

        x_target = inside_x.find { |target| (x_mm - target).abs <= tolerance }
        next unless x_target

        z_target = inside_z.find { |target| (z_mm - target).abs <= tolerance }
        next unless z_target

        key = [x_target, z_target]
        corners[key] << { point: point, group: group }
      end
    end

    corners
  end

  def assert_miter_faces(group)
    miter_faces = group.entities.grep(Sketchup::Face).select do |face|
      normal = face.normal
      next false unless normal

      normal_y = normal.y.abs
      next false unless normal_y < 1e-3

      x_abs = normal.x.abs
      z_abs = normal.z.abs
      (x_abs - z_abs).abs <= 1e-3 && x_abs > 0.0 && z_abs > 0.0
    end

    refute_empty(miter_faces, 'Expected at least one 45° miter face')
  end

  def length_to_mm(length)
    return length if length.is_a?(Numeric)

    length.to_f * 25.4
  end
end
