# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/ops/edit_base_cabinet')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

class TC_FaceFrameScope < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_apply_all_instances_updates_shared_definition
    model = Sketchup.active_model
    params = default_params
    first = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: params
    )
    second = duplicate_instance(model, first)

    select_instance(model, first)

    updated = deep_copy(params)
    updated[:face_frame][:stile_left_mm] = 50.0

    result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated,
      scope: 'all'
    )

    assert_equal(true, result[:ok])
    assert_equal(AICabinetsTestHelper.def_key_of(first), AICabinetsTestHelper.def_key_of(second))
    parsed = params_from_definition(first.definition)
    assert_in_delta(50.0, parsed[:face_frame][:stile_left_mm], 0.01)
  end

  def test_apply_instance_makes_unique_definition
    model = Sketchup.active_model
    params = default_params
    first = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: params
    )
    second = duplicate_instance(model, first)

    select_instance(model, first)
    updated = deep_copy(params)
    updated[:face_frame][:overlay_mm] = 16.0
    result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated,
      scope: 'instance'
    )

    assert_equal(true, result[:ok])
    refute_equal(AICabinetsTestHelper.def_key_of(first), AICabinetsTestHelper.def_key_of(second))
    parsed = params_from_definition(first.definition)
    parsed_other = params_from_definition(second.definition)
    assert_in_delta(16.0, parsed[:face_frame][:overlay_mm], 0.01)
    assert_in_delta(params[:face_frame][:overlay_mm], parsed_other[:face_frame][:overlay_mm], 0.01)
  end

  private

  def default_params
    deep_copy(AICabinets::Defaults.load_effective_mm)
  end

  def duplicate_instance(model, instance)
    translation = Geom::Transformation.translation([instance.definition.bounds.width + 300.mm, 0, 0])
    model.active_entities.add_instance(instance.definition, translation)
  end

  def select_instance(model, instance)
    selection = model.selection
    selection.clear
    selection.add(instance)
  end

  def params_from_definition(definition)
    dict = definition.attribute_dictionary('AICabinets')
    json = dict && dict['params_json_mm']
    JSON.parse(json, symbolize_names: true)
  end

  def deep_copy(object)
    Marshal.load(Marshal.dump(object))
  end
end
