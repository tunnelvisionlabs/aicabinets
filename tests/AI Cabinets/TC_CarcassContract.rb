# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/generator/carcass')

class TC_CarcassContract < TestUp::TestCase
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

  def test_carcass_dimensions_and_anchor
    definition, = build_carcass_definition(BASE_PARAMS_MM)

    bbox = AICabinetsTestHelper.bbox_local_of(definition)
    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)

    min_point = bbox.min
    max_point = bbox.max

    width_mm = AICabinetsTestHelper.mm_from_length(max_point.x - min_point.x)
    depth_mm = AICabinetsTestHelper.mm_from_length(max_point.y - min_point.y)
    height_mm = AICabinetsTestHelper.mm_from_length(max_point.z - min_point.z)

    assert_in_delta(
      BASE_PARAMS_MM[:width_mm],
      width_mm,
      tolerance_mm,
      'Bounding box width should match requested width'
    )
    assert_in_delta(
      BASE_PARAMS_MM[:depth_mm],
      depth_mm,
      tolerance_mm,
      'Bounding box depth should match requested depth'
    )
    assert_in_delta(
      BASE_PARAMS_MM[:height_mm],
      height_mm,
      tolerance_mm,
      'Bounding box height should match requested height'
    )

    assert(min_point.distance(ORIGIN) <= AICabinetsTestHelper::TOL,
           'Carcass should anchor at FLB origin')

    assert(AICabinetsTestHelper.mm_from_length(max_point.x) > 0,
           'Positive X axis should represent cabinet width')
    assert(AICabinetsTestHelper.mm_from_length(max_point.y) > 0,
           'Positive Y axis should represent cabinet depth')
    assert(AICabinetsTestHelper.mm_from_length(max_point.z) > 0,
           'Positive Z axis should represent cabinet height')
  end

  def test_carcass_provides_part_containers
    definition, result = build_carcass_definition(BASE_PARAMS_MM)

    expected_containers = %i[
      left_side
      right_side
      bottom
      top_or_stretchers
      back
    ]

    expected_containers.each do |key|
      container = result.instances[key]
      assert(container, "Expected container for #{key}")
      refute_empty(Array(container), "Expected #{key} container to include geometry")
    end

    top_level_faces = definition.entities.grep(Sketchup::Face)
    top_level_edges = definition.entities.grep(Sketchup::Edge)
    assert_empty(top_level_faces, 'Top-level entities should not contain raw faces')
    assert_empty(top_level_edges, 'Top-level entities should not contain raw edges')
  end

  def test_raw_geometry_uses_default_tag
    definition, = build_carcass_definition(BASE_PARAMS_MM)

    raw_geometry = AICabinetsTestHelper.collect_raw_geometry(definition.entities)
    refute_empty(raw_geometry, 'Expected carcass to contain raw geometry for inspection')

    raw_geometry.each do |entity|
      assert(AICabinetsTestHelper.default_tag?(entity),
             "Expected raw geometry to use default tag, found #{entity.layer&.name}")
    end
  end

  def test_toe_kick_does_not_shift_origin
    base_definition, = build_carcass_definition(BASE_PARAMS_MM)
    toe_definition, = build_carcass_definition(TOE_KICK_PARAMS_MM)

    base_min = AICabinetsTestHelper.bbox_local_of(base_definition).min
    toe_min = AICabinetsTestHelper.bbox_local_of(toe_definition).min

    assert(base_min.distance(ORIGIN) <= AICabinetsTestHelper::TOL,
           'Baseline carcass should anchor at origin')
    assert(toe_min.distance(ORIGIN) <= AICabinetsTestHelper::TOL,
           'Toe-kick carcass should anchor at origin')

    delta = base_min.distance(toe_min)
    assert(delta <= AICabinetsTestHelper::TOL,
           'Toe-kick settings should not shift the FLB origin')
  end

  private

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
    "Carcass Contract #{sequence}"
  end
end
