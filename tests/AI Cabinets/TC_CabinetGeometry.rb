# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/generator/legacy/cabinet')

class TC_CabinetGeometry < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_back_panel_width_matches_interior_width
    group, config, cabinet = build_cabinet_group
    instances = component_instances_of(group)

    back = find_back_panel(instances, mm(config[:back_thickness]))
    refute_nil(back, 'Expected to find back panel component')

    dims = dimensions_mm(back)
    panel_thickness_mm = mm(config[:panel_thickness])
    width_mm = mm(cabinet[:width])
    expected_width = width_mm - (2 * panel_thickness_mm)

    assert_in_delta(expected_width, dims[:width], tolerance_mm,
                    'Back panel width should match interior width')
    assert_in_delta(panel_thickness_mm, dims[:min_x], tolerance_mm,
                    'Back panel should align with left side interior face')
    expected_max_x = width_mm - panel_thickness_mm
    assert_in_delta(expected_max_x, dims[:max_x], tolerance_mm,
                    'Back panel should align with right side interior face')
  end

  def test_top_panel_depth_stops_at_back_front_face
    group, config, _cabinet = build_cabinet_group
    instances = component_instances_of(group)

    top = find_top_panel(
      instances,
      mm(config[:panel_thickness]),
      mm(config[:height]),
      mm(config[:top_inset])
    )
    refute_nil(top, 'Expected to find top panel component')

    dims = dimensions_mm(top)
    expected_depth = back_front_plane_mm(config)

    assert_in_delta(expected_depth, dims[:depth], tolerance_mm,
                    'Top panel depth should stop at back front face')
    assert_in_delta(expected_depth, dims[:max_y], tolerance_mm,
                    'Top panel rear edge should align with back front face')
  end

  def test_bottom_panel_depth_stops_at_back_front_face
    group, config, _cabinet = build_cabinet_group
    instances = component_instances_of(group)

    bottom = find_bottom_panel(
      instances,
      mm(config[:panel_thickness]),
      mm(config[:bottom_inset])
    )
    refute_nil(bottom, 'Expected to find bottom panel component')

    dims = dimensions_mm(bottom)
    expected_depth = back_front_plane_mm(config)

    assert_in_delta(expected_depth, dims[:depth], tolerance_mm,
                    'Bottom panel depth should stop at back front face')
    assert_in_delta(expected_depth, dims[:max_y], tolerance_mm,
                    'Bottom panel rear edge should align with back front face')
  end

  def test_back_inset_reduces_top_and_bottom_depth
    group_zero, config_zero, _cabinet_zero = build_cabinet_group({ back_inset: 0.mm })
    instances_zero = component_instances_of(group_zero)

    top_zero = find_top_panel(
      instances_zero,
      mm(config_zero[:panel_thickness]),
      mm(config_zero[:height]),
      mm(config_zero[:top_inset])
    )
    bottom_zero = find_bottom_panel(
      instances_zero,
      mm(config_zero[:panel_thickness]),
      mm(config_zero[:bottom_inset])
    )
    top_depth_zero = dimensions_mm(top_zero)[:depth]
    bottom_depth_zero = dimensions_mm(bottom_zero)[:depth]

    AICabinetsTestHelper.clean_model!

    inset_mm = 6.0
    group_inset, config_inset, _cabinet_inset = build_cabinet_group({ back_inset: inset_mm.mm })
    instances_inset = component_instances_of(group_inset)

    top_inset = find_top_panel(
      instances_inset,
      mm(config_inset[:panel_thickness]),
      mm(config_inset[:height]),
      mm(config_inset[:top_inset])
    )
    bottom_inset = find_bottom_panel(
      instances_inset,
      mm(config_inset[:panel_thickness]),
      mm(config_inset[:bottom_inset])
    )
    top_depth_inset = dimensions_mm(top_inset)[:depth]
    bottom_depth_inset = dimensions_mm(bottom_inset)[:depth]

    assert_in_delta(inset_mm, top_depth_zero - top_depth_inset, tolerance_mm,
                    'Top depth should reduce by back inset amount')
    assert_in_delta(inset_mm, bottom_depth_zero - bottom_depth_inset, tolerance_mm,
                    'Bottom depth should reduce by back inset amount')
  end

  def test_top_stringers_align_with_back_front_face
    config_overrides = {
      top_type: :stringers,
      top_stringer_width: 120.mm
    }
    group, config, _cabinet = build_cabinet_group(config_overrides)
    instances = component_instances_of(group)

    stringers = find_top_stringers(
      instances,
      mm(config[:panel_thickness]),
      mm(config[:height]),
      mm(config[:top_inset])
    )

    assert_equal(2, stringers.length, 'Expected front and back stringers')

    rear_stringer = stringers.max_by { |instance| dimensions_mm(instance)[:max_y] }
    rear_dims = dimensions_mm(rear_stringer)
    expected_plane = back_front_plane_mm(config)
    stringer_width_mm = mm(config[:top_stringer_width])
    front_plane = [expected_plane - stringer_width_mm, 0.0].max

    assert_in_delta(expected_plane, rear_dims[:max_y], tolerance_mm,
                    'Back stringer should terminate at back front face')
    assert_in_delta(front_plane, rear_dims[:min_y], tolerance_mm,
                    'Back stringer front should preserve requested width')

    front_stringer = stringers.min_by { |instance| dimensions_mm(instance)[:max_y] }
    front_dims = dimensions_mm(front_stringer)
    assert_in_delta(0.0, front_dims[:min_y], tolerance_mm,
                    'Front stringer should start at cabinet front')
    assert_in_delta(stringer_width_mm, front_dims[:max_y], tolerance_mm,
                    'Front stringer depth should equal requested width')
  end

  private

  def build_cabinet_group(config_overrides = {}, cabinet_overrides = {})
    config = base_config.merge(config_overrides)
    cabinet = base_cabinet_config.merge(cabinet_overrides)
    config[:cabinets] = [cabinet]

    model = Sketchup.active_model
    before_ids = model.entities.grep(Sketchup::Group).map(&:entityID)
    AICabinets.create_frameless_cabinet(config)
    group = model.entities.grep(Sketchup::Group).find { |entity| !before_ids.include?(entity.entityID) }
    assert(group, 'Expected cabinet group to be created')

    [group, config, cabinet]
  end

  def base_config
    {
      height: 720.mm,
      depth: 600.mm,
      panel_thickness: 19.mm,
      back_thickness: 6.mm,
      top_inset: 0.mm,
      bottom_inset: 0.mm,
      back_inset: 0.mm
    }
  end

  def base_cabinet_config
    {
      width: 800.mm,
      shelf_count: 0,
      doors: nil,
      drawers: [],
      partitions: [],
      hole_columns: []
    }
  end

  def component_instances_of(group)
    group.entities.select do |entity|
      next unless entity&.valid?

      entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
    end
  end

  def find_back_panel(instances, back_thickness_mm)
    instances.find do |instance|
      (dimensions_mm(instance)[:depth] - back_thickness_mm).abs <= tolerance_mm
    end
  end

  def find_top_panel(instances, panel_thickness_mm, height_mm, top_inset_mm)
    instances.find do |instance|
      dims = dimensions_mm(instance)
      thickness_matches = (dims[:height] - panel_thickness_mm).abs <= tolerance_mm
      top_plane_matches = (dims[:max_z] - (height_mm - top_inset_mm)).abs <= tolerance_mm
      thickness_matches && top_plane_matches
    end
  end

  def find_bottom_panel(instances, panel_thickness_mm, bottom_inset_mm)
    instances.find do |instance|
      dims = dimensions_mm(instance)
      thickness_matches = (dims[:height] - panel_thickness_mm).abs <= tolerance_mm
      bottom_plane_matches = (dims[:min_z] - bottom_inset_mm).abs <= tolerance_mm
      thickness_matches && bottom_plane_matches
    end
  end

  def find_top_stringers(instances, panel_thickness_mm, height_mm, top_inset_mm)
    instances.select do |instance|
      dims = dimensions_mm(instance)
      thickness_matches = (dims[:height] - panel_thickness_mm).abs <= tolerance_mm
      top_plane_matches = (dims[:max_z] - (height_mm - top_inset_mm)).abs <= tolerance_mm
      thickness_matches && top_plane_matches
    end
  end

  def back_front_plane_mm(config)
    depth_mm = mm(config[:depth])
    inset_mm = mm(config[:back_inset])
    thickness_mm = mm(config[:back_thickness])
    [depth_mm - inset_mm - thickness_mm, 0.0].max
  end

  def dimensions_mm(entity)
    bounds = entity.bounds
    {
      width: mm(bounds.max.x - bounds.min.x),
      depth: mm(bounds.max.y - bounds.min.y),
      height: mm(bounds.max.z - bounds.min.z),
      min_x: mm(bounds.min.x),
      max_x: mm(bounds.max.x),
      min_y: mm(bounds.min.y),
      max_y: mm(bounds.max.y),
      min_z: mm(bounds.min.z),
      max_z: mm(bounds.max.z)
    }
  end

  def mm(value)
    AICabinetsTestHelper.mm(value)
  end

  def tolerance_mm
    @tolerance_mm ||= AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
  end
end
