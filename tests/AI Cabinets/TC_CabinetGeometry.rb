# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/generator/carcass')

class TC_CabinetGeometry < TestUp::TestCase
  LENGTH_OVERRIDE_KEYS = %i[
    width
    depth
    height
    panel_thickness
    back_thickness
    top_thickness
    bottom_thickness
    toe_kick_height
    toe_kick_depth
    toe_kick_thickness
    top_inset
    bottom_inset
    back_inset
    top_stringer_width
  ].freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_back_panel_width_matches_interior_width
    _, params_mm, result = build_carcass

    back = single_entity(result.instances[:back])
    refute_nil(back, 'Expected to find back panel component')

    dims = dimensions_mm(back)
    panel_thickness_mm = params_mm[:panel_thickness_mm]
    width_mm = params_mm[:width_mm]
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
    _, params_mm, result = build_carcass

    top = single_entity(result.instances[:top_or_stretchers])
    refute_nil(top, 'Expected to find top panel component')

    dims = dimensions_mm(top)
    expected_depth = back_front_plane_mm(params_mm)

    assert_in_delta(expected_depth, dims[:depth], tolerance_mm,
                    'Top panel depth should stop at back front face')
    assert_in_delta(expected_depth, dims[:max_y], tolerance_mm,
                    'Top panel rear edge should align with back front face')
  end

  def test_bottom_panel_depth_stops_at_back_front_face
    _, params_mm, result = build_carcass

    bottom = single_entity(result.instances[:bottom])
    refute_nil(bottom, 'Expected to find bottom panel component')

    dims = dimensions_mm(bottom)
    expected_depth = back_front_plane_mm(params_mm)

    assert_in_delta(expected_depth, dims[:depth], tolerance_mm,
                    'Bottom panel depth should stop at back front face')
    assert_in_delta(expected_depth, dims[:max_y], tolerance_mm,
                    'Bottom panel rear edge should align with back front face')
  end

  def test_back_inset_reduces_top_and_bottom_depth
    _, params_zero_mm, result_zero = build_carcass(back_inset_mm: 0.0)

    top_zero = single_entity(result_zero.instances[:top_or_stretchers])
    bottom_zero = single_entity(result_zero.instances[:bottom])
    refute_nil(top_zero, 'Expected top panel with zero back inset')
    refute_nil(bottom_zero, 'Expected bottom panel with zero back inset')

    top_depth_zero = dimensions_mm(top_zero)[:depth]
    bottom_depth_zero = dimensions_mm(bottom_zero)[:depth]

    inset_mm = 6.0
    _, params_inset_mm, result_inset = build_carcass(back_inset_mm: inset_mm)

    top_inset = single_entity(result_inset.instances[:top_or_stretchers])
    bottom_inset = single_entity(result_inset.instances[:bottom])
    refute_nil(top_inset, 'Expected top panel with inset back')
    refute_nil(bottom_inset, 'Expected bottom panel with inset back')

    top_depth_inset = dimensions_mm(top_inset)[:depth]
    bottom_depth_inset = dimensions_mm(bottom_inset)[:depth]

    assert_in_delta(inset_mm, top_depth_zero - top_depth_inset, tolerance_mm,
                    'Top depth should reduce by back inset amount')
    assert_in_delta(inset_mm, bottom_depth_zero - bottom_depth_inset, tolerance_mm,
                    'Bottom depth should reduce by back inset amount')

    expected_plane_zero = back_front_plane_mm(params_zero_mm)
    expected_plane_inset = back_front_plane_mm(params_inset_mm)
    assert_in_delta(inset_mm, expected_plane_zero - expected_plane_inset, tolerance_mm,
                    'Back front plane should shift by inset amount')
  end

  def test_top_stringers_align_with_back_front_face
    overrides = {
      top_type: :stringers,
      top_stringer_width_mm: 120.0
    }
    _, params_mm, result = build_carcass(overrides)

    stringers = entities_from(result.instances[:top_or_stretchers])
    assert_equal(2, stringers.length, 'Expected front and back stringers')

    expected_plane = back_front_plane_mm(params_mm)
    stringer_width_mm = params_mm[:top_stringer_width_mm]
    rear_stringer = stringers.max_by { |entity| dimensions_mm(entity)[:max_y] }
    rear_dims = dimensions_mm(rear_stringer)
    front_plane = [expected_plane - stringer_width_mm, 0.0].max

    assert_in_delta(expected_plane, rear_dims[:max_y], tolerance_mm,
                    'Back stringer should terminate at back front face')
    assert_in_delta(front_plane, rear_dims[:min_y], tolerance_mm,
                    'Back stringer front should preserve requested width')

    front_stringer = stringers.min_by { |entity| dimensions_mm(entity)[:max_y] }
    front_dims = dimensions_mm(front_stringer)
    assert_in_delta(0.0, front_dims[:min_y], tolerance_mm,
                    'Front stringer should start at cabinet front')
    assert_in_delta(stringer_width_mm, front_dims[:max_y], tolerance_mm,
                    'Front stringer depth should equal requested width')
  end

  private

  def build_carcass(overrides = {})
    params_mm = base_params_mm.merge(normalize_overrides(overrides))
    definition, result = build_carcass_definition(params_mm)
    [definition, params_mm, result]
  end

  def base_params_mm
    {
      width_mm: 800.0,
      depth_mm: 600.0,
      height_mm: 720.0,
      panel_thickness_mm: 19.0,
      back_thickness_mm: 6.0,
      top_thickness_mm: 19.0,
      bottom_thickness_mm: 19.0,
      toe_kick_height_mm: 0.0,
      toe_kick_depth_mm: 0.0,
      toe_kick_thickness_mm: 19.0,
      top_inset_mm: 0.0,
      bottom_inset_mm: 0.0,
      back_inset_mm: 0.0,
      top_type: :panel,
      top_stringer_width_mm: 100.0
    }
  end

  def normalize_overrides(overrides)
    overrides.each_with_object({}) do |(key, value), acc|
      symbol_key = key.to_sym
      if symbol_key.to_s.end_with?('_mm')
        acc[symbol_key] = value.is_a?(Numeric) ? value.to_f : mm(value)
      elsif LENGTH_OVERRIDE_KEYS.include?(symbol_key)
        acc["#{symbol_key}_mm".to_sym] = mm(value)
      else
        acc[symbol_key] = value
      end
    end
  end

  def build_carcass_definition(params_mm)
    model = Sketchup.active_model
    name = next_definition_name
    definition = model.definitions.add(name)
    result = AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params_mm)
    [definition, result]
  end

  def next_definition_name
    sequence = self.class.instance_variable_get(:@definition_sequence) || 0
    sequence += 1
    self.class.instance_variable_set(:@definition_sequence, sequence)
    "Cabinet Geometry #{sequence}"
  end

  def single_entity(container)
    entities_from(container).first
  end

  def entities_from(container)
    Array(container).flatten.compact.select { |entity| entity&.valid? }
  end

  def back_front_plane_mm(params_mm)
    depth_mm = params_mm[:depth_mm]
    inset_mm = params_mm[:back_inset_mm]
    thickness_mm = params_mm[:back_thickness_mm]
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
