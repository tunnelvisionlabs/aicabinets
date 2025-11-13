# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/ops/insert_base_cabinet')
Sketchup.require('aicabinets/ui/dialogs/insert_base_cabinet_dialog')

class TC_EditDialogSelection < TestUp::TestCase
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

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_selection_details_single_instance_returns_unique_metadata
    model = Sketchup.active_model
    instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: BASE_PARAMS_MM
    )

    definition = instance.definition
    definition.name = ' ' if definition.respond_to?(:name=)

    details = AICabinets::UI::Dialogs::InsertBaseCabinet.selection_details_for(instance)

    assert_kind_of(Hash, details)
    assert_equal(1, details[:instances_count], 'Expected single instance to report count = 1')
    assert_equal(false, details[:shares_definition], 'Unique instance should not report shared definition')
    assert_nil(details[:definition_name], 'Blank definition name should be normalized to nil')
  end

  def test_selection_details_multiple_instances_includes_count_and_name
    definition, first_instance, second_instance = build_two_instances(BASE_PARAMS_MM)
    definition.name = 'Dialog Metadata Cabinet' if definition.respond_to?(:name=)

    details = AICabinets::UI::Dialogs::InsertBaseCabinet.selection_details_for(first_instance)

    assert_equal(2, details[:instances_count], 'Expected shared definition count to include both instances')
    assert(details[:shares_definition], 'Shared definition should report shares_definition = true')
    assert_equal('Dialog Metadata Cabinet', details[:definition_name])

    details_second = AICabinets::UI::Dialogs::InsertBaseCabinet.selection_details_for(second_instance)
    assert_equal(details, details_second, 'Selection details should be identical for siblings')
  end

  private

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
