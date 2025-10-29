# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/generator/carcass')

class TC_ToeKickGeometry < TestUp::TestCase
  BASE_PARAMS_MM = {
    width_mm: 800.0,
    depth_mm: 600.0,
    height_mm: 720.0,
    panel_thickness_mm: 19.0,
    toe_kick_height_mm: 100.0,
    toe_kick_depth_mm: 75.0,
    toe_kick_thickness_mm: 19.0,
    back_thickness_mm: 6.0,
    top_thickness_mm: 19.0,
    bottom_thickness_mm: 19.0,
    front: :doors_double,
    door_reveal_mm: 2.0,
    top_reveal_mm: 2.0,
    bottom_reveal_mm: 3.0,
    door_gap_mm: 3.0
  }.freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_door_bottom_respects_toe_kick_and_bottom_reveal
    params_mm = BASE_PARAMS_MM
    _, result = build_carcass_definition(params_mm)

    doors = door_fronts(result)
    refute_empty(doors, 'Expected door fronts to be created')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    expected_bottom_mm = params_mm[:toe_kick_height_mm] + params_mm[:bottom_reveal_mm]
    expected_height_mm = params_mm[:height_mm] - params_mm[:toe_kick_height_mm] -
                         params_mm[:top_reveal_mm] - params_mm[:bottom_reveal_mm]

    doors.each do |door|
      bounds = door.bounds
      bottom_mm = AICabinetsTestHelper.mm_from_length(bounds.min.z)
      top_mm = AICabinetsTestHelper.mm_from_length(bounds.max.z)
      height_mm = top_mm - bottom_mm

      assert_in_delta(expected_bottom_mm, bottom_mm, tolerance_mm,
                      'Door bottom should clear the toe kick by the bottom reveal')
      assert_in_delta(expected_height_mm, height_mm, tolerance_mm,
                      'Door height should respect reveals above the toe kick')
    end
  end

  def test_double_door_gap_preserved_with_toe_kick
    params_mm = BASE_PARAMS_MM
    _, result = build_carcass_definition(params_mm)

    doors = door_fronts(result)
    assert_equal(2, doors.length, 'Expected a pair of doors for double layout')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    expected_gap_mm = params_mm[:door_gap_mm]

    sorted = doors.sort_by { |door| AICabinetsTestHelper.mm_from_length(door.bounds.min.x) }
    left = sorted.first
    right = sorted.last

    gap_length = right.bounds.min.x - left.bounds.max.x
    gap_mm = AICabinetsTestHelper.mm_from_length(gap_length)

    assert_in_delta(expected_gap_mm, gap_mm, tolerance_mm,
                    'Gap between doors should be preserved when toe kick is present')
  end

  def test_bottom_panel_front_edge_flush_with_carcass_front
    params_mm = BASE_PARAMS_MM
    _, result = build_carcass_definition(params_mm)

    bottom = result.instances[:bottom]
    refute_nil(bottom, 'Expected bottom panel to exist')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    min_y_mm = AICabinetsTestHelper.mm_from_length(bottom.bounds.min.y)
    max_y_mm = AICabinetsTestHelper.mm_from_length(bottom.bounds.max.y)

    assert_in_delta(0.0, min_y_mm, tolerance_mm,
                    'Bottom panel front edge should align with carcass front plane')
    assert_in_delta(params_mm[:depth_mm], max_y_mm, tolerance_mm,
                    'Bottom panel should extend to the cabinet back')
  end

  def test_door_bottom_unchanged_when_toe_kick_disabled
    params_mm = BASE_PARAMS_MM.merge(
      toe_kick_height_mm: 0.0,
      toe_kick_depth_mm: 0.0
    )
    _, result = build_carcass_definition(params_mm)

    doors = door_fronts(result)
    refute_empty(doors, 'Expected doors when toe kick is disabled')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    expected_bottom_mm = params_mm[:bottom_reveal_mm]

    doors.each do |door|
      bottom_mm = AICabinetsTestHelper.mm_from_length(door.bounds.min.z)
      assert_in_delta(expected_bottom_mm, bottom_mm, tolerance_mm,
                      'Door bottom should default to the reveal when toe kick is disabled')
    end
  end

  def test_door_bottom_unchanged_when_toe_kick_depth_zero
    params_mm = BASE_PARAMS_MM.merge(
      toe_kick_depth_mm: 0.0
    )
    _, result = build_carcass_definition(params_mm)

    doors = door_fronts(result)
    refute_empty(doors, 'Expected doors when toe kick depth is zero')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    expected_bottom_mm = params_mm[:bottom_reveal_mm]

    doors.each do |door|
      bottom_mm = AICabinetsTestHelper.mm_from_length(door.bounds.min.z)
      assert_in_delta(expected_bottom_mm, bottom_mm, tolerance_mm,
                      'Door bottom should default to the reveal when toe kick depth is zero')
    end
  end

  def test_bottom_panel_alignment_when_toe_kick_height_zero
    params_mm = BASE_PARAMS_MM.merge(
      toe_kick_height_mm: 0.0,
      toe_kick_depth_mm: 75.0
    )
    _, result = build_carcass_definition(params_mm)

    bottom = result.instances[:bottom]
    refute_nil(bottom, 'Expected bottom panel to exist when toe kick height is zero')
    assert_nil(result.instances[:toe_kick_front],
               'Toe kick front should not exist when toe kick height is zero')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    min_y_mm = AICabinetsTestHelper.mm_from_length(bottom.bounds.min.y)
    max_y_mm = AICabinetsTestHelper.mm_from_length(bottom.bounds.max.y)

    assert_in_delta(0.0, min_y_mm, tolerance_mm,
                    'Bottom panel front edge should remain flush without a toe kick height')
    assert_in_delta(params_mm[:depth_mm], max_y_mm, tolerance_mm,
                    'Bottom panel should span the full cabinet depth when toe kick is disabled by height')
  end

  def test_partitioned_cabinet_doors_respect_toe_kick
    params_mm = BASE_PARAMS_MM.merge(
      partitions: {
        mode: 'even',
        count: 1
      }
    )
    _, result = build_carcass_definition(params_mm)

    doors = door_fronts(result)
    refute_empty(doors, 'Expected doors with partitions present')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    expected_bottom_mm = params_mm[:toe_kick_height_mm] + params_mm[:bottom_reveal_mm]

    doors.each do |door|
      bottom_mm = AICabinetsTestHelper.mm_from_length(door.bounds.min.z)
      assert_in_delta(expected_bottom_mm, bottom_mm, tolerance_mm,
                      'Door bottom should respect toe kick even when partitions exist')
    end
  end

  def test_stringer_top_preserves_toe_kick_door_clearance
    params_mm = BASE_PARAMS_MM.merge(
      top_type: :stringers
    )
    _, result = build_carcass_definition(params_mm)

    top_or_stretchers = result.instances[:top_or_stretchers]
    refute_nil(top_or_stretchers, 'Expected top or stretcher geometry to exist')

    doors = door_fronts(result)
    refute_empty(doors, 'Expected doors with stringer top configuration')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    expected_bottom_mm = params_mm[:toe_kick_height_mm] + params_mm[:bottom_reveal_mm]

    doors.each do |door|
      bottom_mm = AICabinetsTestHelper.mm_from_length(door.bounds.min.z)
      assert_in_delta(expected_bottom_mm, bottom_mm, tolerance_mm,
                      'Door bottom should clear the toe kick when using stringer tops')
    end
  end

  private

  def build_carcass_definition(params_mm)
    model = Sketchup.active_model
    name = next_definition_name
    definition = model.definitions.add(name)
    result = AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params_mm)
    [definition, result]
  end

  def door_fronts(result)
    Array(result.instances[:fronts]).flatten.compact
  end

  def next_definition_name
    sequence = self.class.instance_variable_get(:@definition_sequence) || 0
    sequence += 1
    self.class.instance_variable_set(:@definition_sequence, sequence)
    "Toe Kick Geometry #{sequence}"
  end
end
