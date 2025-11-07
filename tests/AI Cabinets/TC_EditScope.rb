# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/ops/insert_base_cabinet')
Sketchup.require('aicabinets/ops/edit_base_cabinet')

# NOTE: These tests intentionally avoid calling make_unique directly. They
# verify the behavior through the edit entry point to match production flows.
class TC_EditScope < TestUp::TestCase
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

  WIDTH_DELTA_MM = 50.0

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_edit_scope_instance_only
    model = Sketchup.active_model
    definition, first_instance, second_instance = build_two_instances(BASE_PARAMS_MM)

    original_def_key = AICabinetsTestHelper.def_key_of(definition)
    original_params = AICabinetsTestHelper.params_mm_from_definition(definition)
    refute_empty(original_params, 'Expected base definition to expose params_json_mm attributes')

    original_bbox_min = AICabinetsTestHelper.bbox_local_of(definition).min.clone
    first_transform_before = first_instance.transformation.clone
    second_transform_before = second_instance.transformation.clone

    selection = model.selection
    selection.clear
    selection.add(first_instance)

    updated_params = BASE_PARAMS_MM.merge(width_mm: BASE_PARAMS_MM[:width_mm] + WIDTH_DELTA_MM)

    result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated_params,
      scope: 'instance'
    )
    assert(result[:ok], "Expected instance-only edit to succeed: #{result.inspect}")

    edited_definition = first_instance.definition
    sibling_definition = second_instance.definition

    refute_equal(definition, edited_definition,
                 'Instance-only edit should create a unique definition for the edited instance')
    assert_equal(definition, sibling_definition,
                 'Sibling instance should continue referencing the original definition')

    refute_equal(original_def_key, AICabinetsTestHelper.def_key_of(edited_definition),
                 'Edited definition should receive a new def_key')
    assert_equal(original_def_key, AICabinetsTestHelper.def_key_of(sibling_definition),
                 'Original definition def_key should remain unchanged for sibling instance')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    edited_params = AICabinetsTestHelper.params_mm_from_definition(edited_definition)
    sibling_params = AICabinetsTestHelper.params_mm_from_definition(sibling_definition)

    assert_in_delta(BASE_PARAMS_MM[:width_mm] + WIDTH_DELTA_MM,
                    edited_params[:width_mm],
                    tolerance_mm,
                    'Edited definition width should reflect updated params')
    assert_in_delta(BASE_PARAMS_MM[:width_mm],
                    sibling_params[:width_mm],
                    tolerance_mm,
                    'Sibling definition width should remain unchanged')

    assert(AICabinetsTestHelper.transforms_approx_equal?(first_instance.transformation, first_transform_before),
           'Edited instance transformation should remain unchanged')
    assert(AICabinetsTestHelper.transforms_approx_equal?(second_instance.transformation, second_transform_before),
           'Sibling instance transformation should remain unchanged')

    edited_bbox_min = AICabinetsTestHelper.bbox_local_of(edited_definition).min
    sibling_bbox_min = AICabinetsTestHelper.bbox_local_of(sibling_definition).min
    assert_flb_anchor_preserved(edited_bbox_min,
                                tolerance_mm,
                                'Edited definition should preserve carcass FLB anchor at origin')
    assert(sibling_bbox_min.distance(original_bbox_min) <= AICabinetsTestHelper::TOL,
           'Sibling definition should preserve original FLB origin')

    Sketchup.undo

    assert_equal(definition, first_instance.definition,
                 'Undo should restore original definition for edited instance')
    assert_equal(definition, second_instance.definition,
                 'Undo should keep sibling instance on original definition')
    assert_equal(original_def_key, AICabinetsTestHelper.def_key_of(first_instance.definition),
                 'Undo should restore original def_key for edited instance')
    assert(AICabinetsTestHelper.transforms_approx_equal?(first_instance.transformation, first_transform_before),
           'Undo should restore edited instance transform')
    assert(AICabinetsTestHelper.transforms_approx_equal?(second_instance.transformation, second_transform_before),
           'Undo should restore sibling instance transform')

    restored_params = AICabinetsTestHelper.params_mm_from_definition(definition)
    assert_in_delta(original_params[:width_mm],
                    restored_params[:width_mm],
                    tolerance_mm,
                    'Undo should restore original definition width')
  end

  def test_edit_scope_all_instances
    model = Sketchup.active_model
    definition, first_instance, second_instance = build_two_instances(BASE_PARAMS_MM)

    original_def_key = AICabinetsTestHelper.def_key_of(definition)
    original_params = AICabinetsTestHelper.params_mm_from_definition(definition)
    refute_empty(original_params, 'Expected base definition to expose params_json_mm attributes')

    original_bbox_min = AICabinetsTestHelper.bbox_local_of(definition).min.clone
    first_transform_before = first_instance.transformation.clone
    second_transform_before = second_instance.transformation.clone

    selection = model.selection
    selection.clear
    selection.add(first_instance)

    updated_params = BASE_PARAMS_MM.merge(width_mm: BASE_PARAMS_MM[:width_mm] + WIDTH_DELTA_MM)

    result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated_params,
      scope: 'all'
    )
    assert(result[:ok], "Expected all-instances edit to succeed: #{result.inspect}")

    shared_definition_after = first_instance.definition
    assert_equal(shared_definition_after, second_instance.definition,
                 'All-instances edit should keep both instances on shared definition')

    new_def_key = AICabinetsTestHelper.def_key_of(shared_definition_after)
    refute_equal(original_def_key, new_def_key,
                 'All-instances edit should update definition def_key to reflect new params')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    updated_definition_params = AICabinetsTestHelper.params_mm_from_definition(shared_definition_after)
    assert_in_delta(BASE_PARAMS_MM[:width_mm] + WIDTH_DELTA_MM,
                    updated_definition_params[:width_mm],
                    tolerance_mm,
                    'All-instances edit should update shared definition width')

    assert(AICabinetsTestHelper.transforms_approx_equal?(first_instance.transformation, first_transform_before),
           'All-instances edit should not move the first instance')
    assert(AICabinetsTestHelper.transforms_approx_equal?(second_instance.transformation, second_transform_before),
           'All-instances edit should not move the sibling instance')

    updated_bbox_min = AICabinetsTestHelper.bbox_local_of(shared_definition_after).min
    assert(updated_bbox_min.distance(original_bbox_min) <= AICabinetsTestHelper::TOL,
           'All-instances edit should preserve FLB origin for shared definition')

    Sketchup.undo

    assert_equal(definition, first_instance.definition,
                 'Undo should restore original definition object reference')
    assert_equal(definition, second_instance.definition,
                 'Undo should keep sibling on original definition after undo')
    assert_equal(original_def_key, AICabinetsTestHelper.def_key_of(definition),
                 'Undo should restore original def_key for shared definition')

    restored_params = AICabinetsTestHelper.params_mm_from_definition(definition)
    assert_in_delta(original_params[:width_mm],
                    restored_params[:width_mm],
                    tolerance_mm,
                    'Undo should restore original shared definition width')

    assert(AICabinetsTestHelper.transforms_approx_equal?(first_instance.transformation, first_transform_before),
           'Undo should restore first instance transform')
    assert(AICabinetsTestHelper.transforms_approx_equal?(second_instance.transformation, second_transform_before),
           'Undo should restore second instance transform')
  end

  private

  def assert_flb_anchor_preserved(point3d, tolerance_mm, context)
    x_mm = AICabinetsTestHelper.mm(point3d.x)
    y_mm = AICabinetsTestHelper.mm(point3d.y)
    z_mm = AICabinetsTestHelper.mm(point3d.z)

    assert_in_delta(0.0, x_mm, tolerance_mm,
                    "#{context}: expected minimum X to remain at 0 mm")
    assert_operator(y_mm, :<=, tolerance_mm,
                    "#{context}: expected minimum Y to sit on or in front of the carcass front plane")
    assert_in_delta(0.0, z_mm, tolerance_mm,
                    "#{context}: expected minimum Z to remain at 0 mm")
  end

  def build_two_instances(params_mm)
    model = Sketchup.active_model
    first_instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: params_mm
    )
    definition = first_instance.definition

    translation = Geom::Transformation.translation([
      (params_mm[:width_mm] + 300.0).mm,
      0,
      0
    ])
    second_instance = model.active_entities.add_instance(definition, translation)

    [definition, first_instance, second_instance]
  end
end
