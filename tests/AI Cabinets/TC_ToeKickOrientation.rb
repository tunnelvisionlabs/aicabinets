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
    toe_kick_thickness_mm: 19.0,
    back_thickness_mm: 6.0,
    top_thickness_mm: 19.0,
    bottom_thickness_mm: 19.0
  }.freeze

  TOE_KICK_PARAMS_MM = BASE_PARAMS_MM.merge(
    toe_kick_height_mm: 100.0,
    toe_kick_depth_mm: 75.0,
    toe_kick_thickness_mm: 19.0
  ).freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_side_panels_include_front_toe_kick_notch
    _, result = build_carcass_definition(TOE_KICK_PARAMS_MM)

    sides = side_panels(result)
    assert_equal(2, sides.length, 'Expected two side panels to be created')
    refute(result.instances.key?(:toe_kick_sides), 'Toe-kick sides should not be reported as separate parts')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    toe_depth_mm = TOE_KICK_PARAMS_MM[:toe_kick_depth_mm]
    toe_height_mm = TOE_KICK_PARAMS_MM[:toe_kick_height_mm]
    depth_mm = TOE_KICK_PARAMS_MM[:depth_mm]
    toe_thickness_mm = [TOE_KICK_PARAMS_MM[:toe_kick_thickness_mm], toe_depth_mm].min

    expected_bottom = [toe_depth_mm + toe_thickness_mm, depth_mm]

    sides.each do |side|
      bottom_values = y_values_at_z(side, 0.0, tolerance_mm)
      assert_values_close(expected_bottom, bottom_values, tolerance_mm,
                          'Remaining bottom should begin at the notch step and extend to the back')

      step_values = y_values_at_z(side, toe_height_mm, tolerance_mm)
      assert_operator(step_values.length, :>=, 2,
                      'Toe-kick step should expose the front corner and notch depth')
      assert_in_delta(0.0, step_values[0], tolerance_mm,
                      'Toe-kick step should start at the front (Y=0)')
      expected_step_depth = toe_depth_mm + toe_thickness_mm
      assert_in_delta(expected_step_depth, step_values[1], tolerance_mm,
                      'Toe-kick step should extend to the configured depth plus front board thickness from the front')
    end
  end

  def test_side_panels_left_and_right_positions
    _, result = build_carcass_definition(TOE_KICK_PARAMS_MM)

    sides = side_panels(result)
    assert_equal(2, sides.length, 'Expected two side panels to be created')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    panel_thickness_mm = TOE_KICK_PARAMS_MM[:panel_thickness_mm]
    width_mm = TOE_KICK_PARAMS_MM[:width_mm]

    left = sides.min_by { |side| AICabinetsTestHelper.mm_from_length(side.bounds.min.x) }
    right = sides.max_by { |side| AICabinetsTestHelper.mm_from_length(side.bounds.min.x) }

    left_bounds = left.bounds
    assert_in_delta(0.0, AICabinetsTestHelper.mm_from_length(left_bounds.min.x), tolerance_mm,
                    'Left side should sit at the origin on X')
    assert_in_delta(panel_thickness_mm, AICabinetsTestHelper.mm_from_length(left_bounds.max.x), tolerance_mm,
                    'Left side thickness should match panel thickness')

    right_bounds = right.bounds
    expected_right_min = width_mm - panel_thickness_mm
    assert_in_delta(expected_right_min, AICabinetsTestHelper.mm_from_length(right_bounds.min.x), tolerance_mm,
                    'Right side should offset by the cabinet width minus thickness')
    assert_in_delta(width_mm, AICabinetsTestHelper.mm_from_length(right_bounds.max.x), tolerance_mm,
                    'Right side should reach the cabinet width')
  end

  def test_toe_kick_notch_dimensions
    _, result = build_carcass_definition(TOE_KICK_PARAMS_MM)

    sides = side_panels(result)
    refute_empty(sides, 'Expected side panels to exist')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    toe_depth_mm = TOE_KICK_PARAMS_MM[:toe_kick_depth_mm]
    toe_height_mm = TOE_KICK_PARAMS_MM[:toe_kick_height_mm]
    toe_thickness_mm = [TOE_KICK_PARAMS_MM[:toe_kick_thickness_mm], toe_depth_mm].min
    expected_step_depth = toe_depth_mm + toe_thickness_mm

    sides.each do |side|
      step_values = y_values_at_z(side, toe_height_mm, tolerance_mm)
      assert_operator(step_values.length, :>=, 2,
                      'Toe-kick step should include the front edge and notch depth')

      front_position = step_values[0]
      notch_position = step_values[1]

      assert_in_delta(0.0, front_position, tolerance_mm,
                      'Toe-kick front edge should align with the cabinet front (Y=0)')
      assert_in_delta(expected_step_depth, notch_position, tolerance_mm,
                      'Toe-kick step should align with the configured depth plus front board thickness from the front')

      notch_depth = notch_position - front_position
      assert_in_delta(expected_step_depth, notch_depth, tolerance_mm,
                      'Toe-kick notch depth should include the front board thickness')
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

  def test_side_panels_have_no_toe_kick_when_depth_zero
    params_mm = TOE_KICK_PARAMS_MM.merge(toe_kick_depth_mm: 0.0)
    _, result = build_carcass_definition(params_mm)

    sides = side_panels(result)
    refute_empty(sides, 'Side panels should still be created')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    depth_mm = params_mm[:depth_mm]

    sides.each do |side|
      bottom_values = y_values_at_z(side, 0.0, tolerance_mm)
      assert_values_close([0.0, depth_mm], bottom_values, tolerance_mm,
                          'No toe-kick notch should be present when depth is zero')
    end
  end

  def test_side_panels_have_no_toe_kick_when_height_zero
    params_mm = TOE_KICK_PARAMS_MM.merge(toe_kick_height_mm: 0.0)
    _, result = build_carcass_definition(params_mm)

    sides = side_panels(result)
    refute_empty(sides, 'Side panels should still be created')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    depth_mm = params_mm[:depth_mm]

    sides.each do |side|
      bottom_values = y_values_at_z(side, 0.0, tolerance_mm)
      assert_values_close([0.0, depth_mm], bottom_values, tolerance_mm,
                          'No toe-kick notch should be present when height is zero')
    end
  end

  def test_toe_kick_front_board_dimensions_and_tagging
    params_mm = TOE_KICK_PARAMS_MM.merge(toe_kick_thickness_mm: 16.0)
    _, result = build_carcass_definition(params_mm)

    front = result.instances[:toe_kick_front]
    refute_nil(front, 'Expected toe-kick front board to be created')
    assert_kind_of(Sketchup::ComponentInstance, front)

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    bbox = front.bounds

    min_x = AICabinetsTestHelper.mm_from_length(bbox.min.x)
    max_x = AICabinetsTestHelper.mm_from_length(bbox.max.x)
    assert_in_delta(0.0, min_x, tolerance_mm,
                    'Front board should start at the exterior left edge of the cabinet')
    assert_in_delta(params_mm[:width_mm], max_x, tolerance_mm,
                    'Front board should end at the exterior right edge of the cabinet')

    min_y = AICabinetsTestHelper.mm_from_length(bbox.min.y)
    max_y = AICabinetsTestHelper.mm_from_length(bbox.max.y)
    toe_depth_mm = params_mm[:toe_kick_depth_mm]
    effective_thickness_mm = [params_mm[:toe_kick_thickness_mm], toe_depth_mm].min
    expected_front_face_mm = toe_depth_mm
    expected_rear_face_mm = toe_depth_mm + effective_thickness_mm
    assert_in_delta(expected_front_face_mm, min_y, tolerance_mm,
                    'Front board visible face should align with the toe-kick plane behind the carcass front')
    assert_in_delta(expected_rear_face_mm, max_y, tolerance_mm,
                    'Front board interior face should return into the cabinet by the board thickness')

    min_z = AICabinetsTestHelper.mm_from_length(bbox.min.z)
    max_z = AICabinetsTestHelper.mm_from_length(bbox.max.z)
    assert_in_delta(0.0, min_z, tolerance_mm,
                    'Front board bottom should align with cabinet bottom reference plane')
    assert_in_delta(params_mm[:toe_kick_height_mm], max_z, tolerance_mm,
                    'Front board height should match the toe kick height')

    assert_equal('ToeKick/Front', front.name)
    assert_equal('ToeKick/Front', front.definition.name)
    assert_equal('AICabinets/ToeKick', front.layer&.name)
  end

  def test_toe_kick_front_board_skipped_when_thickness_non_positive
    params_mm = TOE_KICK_PARAMS_MM.merge(toe_kick_thickness_mm: 0.0)
    _, result = build_carcass_definition(params_mm)

    assert_nil(result.instances[:toe_kick_front],
               'Front board should not be created when thickness is zero')
  end

  private

  def build_carcass_definition(params_mm)
    model = Sketchup.active_model
    name = next_definition_name
    definition = model.definitions.add(name)
    result = AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params_mm)
    [definition, result]
  end

  def side_panels(result)
    [result.instances[:left_side], result.instances[:right_side]].compact
  end

  def y_values_at_z(group, target_z_mm, tolerance_mm)
    yz_vertices(group)
      .select { |(_, z_mm)| (z_mm - target_z_mm).abs <= tolerance_mm }
      .map(&:first)
      .sort
  end

  def yz_vertices(group)
    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    faces = group.respond_to?(:entities) ? group.entities.grep(Sketchup::Face) : []
    points = faces.flat_map { |face| face.vertices.map { |vertex| vertex.position } }

    points.each_with_object([]) do |point, unique|
      y_mm = AICabinetsTestHelper.mm(point.y)
      z_mm = AICabinetsTestHelper.mm(point.z)
      next if unique.any? { |(y, z)| (y - y_mm).abs <= tolerance_mm && (z - z_mm).abs <= tolerance_mm }

      unique << [y_mm, z_mm]
    end
  end

  def assert_values_close(expected, actual, tolerance_mm, message)
    assert_equal(expected.length, actual.length, message)
    expected.zip(actual).each do |expected_value, actual_value|
      assert_in_delta(expected_value, actual_value, tolerance_mm, message)
    end
  end

  def next_definition_name
    sequence = self.class.instance_variable_get(:@definition_sequence) || 0
    sequence += 1
    self.class.instance_variable_set(:@definition_sequence, sequence)
    "Toe Kick Orientation #{sequence}"
  end
end
