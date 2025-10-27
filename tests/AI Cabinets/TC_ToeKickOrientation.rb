# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/generator/carcass')

class TC_ToeKickOrientation < TestUp::TestCase
  BASE_PARAMS_MM = {
    width_mm: 800.0,
    depth_mm: 600.0,
    height_mm: 720.0,
    panel_thickness_mm: 19.0,
    toe_kick_height_mm: 0.0,
    toe_kick_depth_mm: 0.0,
    back_thickness_mm: 6.0,
    top_thickness_mm: 19.0,
    bottom_thickness_mm: 19.0
  }.freeze

  TOE_KICK_PARAMS_MM = BASE_PARAMS_MM.merge(
    toe_kick_height_mm: 100.0,
    toe_kick_depth_mm: 75.0
  ).freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_toe_kick_sides_front_left_right
    definition, result = build_carcass_definition(TOE_KICK_PARAMS_MM)

    sides = toe_kick_sides(result)
    assert_equal(2, sides.length, 'Expected exactly two toe-kick side panels')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    toe_depth_mm = TOE_KICK_PARAMS_MM[:toe_kick_depth_mm]
    panel_thickness_mm = TOE_KICK_PARAMS_MM[:panel_thickness_mm]
    width_mm = TOE_KICK_PARAMS_MM[:width_mm]

    sides.each do |side|
      bounds = side.bounds
      min_y_mm = AICabinetsTestHelper.mm_from_length(bounds.min.y)
      max_y_mm = AICabinetsTestHelper.mm_from_length(bounds.max.y)

      assert_in_delta(0.0, min_y_mm, tolerance_mm,
                      'Toe-kick side should start at the front (Y=0)')
      assert_in_delta(toe_depth_mm, max_y_mm, tolerance_mm,
                      'Toe-kick side depth should match toe-kick depth')
    end

    left = sides.min_by { |side| AICabinetsTestHelper.mm_from_length(side.bounds.min.x) }
    right = sides.max_by { |side| AICabinetsTestHelper.mm_from_length(side.bounds.min.x) }

    left_bounds = left.bounds
    assert_in_delta(0.0, AICabinetsTestHelper.mm_from_length(left_bounds.min.x), tolerance_mm,
                    'Left toe-kick side should align with the cabinet origin on X')
    assert_in_delta(panel_thickness_mm, AICabinetsTestHelper.mm_from_length(left_bounds.max.x), tolerance_mm,
                    'Left toe-kick side thickness should match panel thickness')

    right_bounds = right.bounds
    expected_right_min = width_mm - panel_thickness_mm
    assert_in_delta(expected_right_min, AICabinetsTestHelper.mm_from_length(right_bounds.min.x), tolerance_mm,
                    'Right toe-kick side should be positioned at the cabinet width minus thickness')
    assert_in_delta(width_mm, AICabinetsTestHelper.mm_from_length(right_bounds.max.x), tolerance_mm,
                    'Right toe-kick side should reach the cabinet width')
  end

  def test_toe_kick_side_dimensions
    _, result = build_carcass_definition(TOE_KICK_PARAMS_MM)

    sides = toe_kick_sides(result)
    refute_empty(sides, 'Expected toe-kick sides when toe-kick is enabled')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)

    sides.each do |side|
      bounds = AICabinetsTestHelper.bbox_local_of(side)
      size_x_mm = AICabinetsTestHelper.mm_from_length(bounds.max.x - bounds.min.x)
      size_y_mm = AICabinetsTestHelper.mm_from_length(bounds.max.y - bounds.min.y)
      size_z_mm = AICabinetsTestHelper.mm_from_length(bounds.max.z - bounds.min.z)

      assert_in_delta(TOE_KICK_PARAMS_MM[:panel_thickness_mm], size_x_mm, tolerance_mm,
                      'Toe-kick side thickness should match panel thickness')
      assert_in_delta(TOE_KICK_PARAMS_MM[:toe_kick_depth_mm], size_y_mm, tolerance_mm,
                      'Toe-kick side depth should match toe-kick depth')
      assert_in_delta(TOE_KICK_PARAMS_MM[:toe_kick_height_mm], size_z_mm, tolerance_mm,
                      'Toe-kick side height should match toe-kick height')

      dictionary = side.attribute_dictionary(AICabinetsTestHelper::DICTIONARY_NAME)
      assert_equal('toe_kick_side', dictionary&.fetch('part', nil),
                   'Toe-kick side should label its part attribute')
    end
  end

  def test_toe_kick_preserves_carcass_bounds
    base_definition, = build_carcass_definition(BASE_PARAMS_MM)
    toe_definition, = build_carcass_definition(TOE_KICK_PARAMS_MM)

    base_bbox = AICabinetsTestHelper.bbox_local_of(base_definition)
    toe_bbox = AICabinetsTestHelper.bbox_local_of(toe_definition)

    tolerance = AICabinetsTestHelper::TOL

    assert(base_bbox.min.distance(ORIGIN) <= tolerance,
           'Baseline carcass should anchor at origin')
    assert(toe_bbox.min.distance(ORIGIN) <= tolerance,
           'Toe-kick carcass should anchor at origin')

    assert_in_delta(0.0, base_bbox.min.distance(toe_bbox.min), tolerance,
                    'Toe-kick geometry should not shift the definition origin')
  end

  def test_toe_kick_sides_omitted_when_depth_zero
    params_mm = TOE_KICK_PARAMS_MM.merge(toe_kick_depth_mm: 0.0)
    _, result = build_carcass_definition(params_mm)

    assert_empty(toe_kick_sides(result),
                 'Toe-kick sides should not be created when depth is zero')
  end

  def test_toe_kick_sides_omitted_when_height_zero
    params_mm = TOE_KICK_PARAMS_MM.merge(toe_kick_height_mm: 0.0)
    _, result = build_carcass_definition(params_mm)

    assert_empty(toe_kick_sides(result),
                 'Toe-kick sides should not be created when height is zero')
  end

  private

  def build_carcass_definition(params_mm)
    model = Sketchup.active_model
    name = next_definition_name
    definition = model.definitions.add(name)
    result = AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params_mm)
    [definition, result]
  end

  def toe_kick_sides(result)
    Array(result.instances[:toe_kick_sides]).compact
  end

  def next_definition_name
    sequence = self.class.instance_variable_get(:@definition_sequence) || 0
    sequence += 1
    self.class.instance_variable_set(:@definition_sequence, sequence)
    "Toe Kick Orientation #{sequence}"
  end
end
