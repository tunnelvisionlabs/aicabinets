# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'
require 'digest'

Sketchup.require('aicabinets/ops/insert_base_cabinet')
Sketchup.require('aicabinets/ops/edit_base_cabinet')
Sketchup.require('aicabinets/ops/params_schema')

class TC_SchemaV2 < TestUp::TestCase
  BASE_PARAMS_MM = {
    width_mm: 762.0,
    depth_mm: 600.0,
    height_mm: 720.0,
    overlay_mm: 0.0,
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

  def test_new_definition_uses_v2_schema
    model = Sketchup.active_model
    instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: BASE_PARAMS_MM
    )

    params = AICabinetsTestHelper.params_mm_from_definition(instance)

    assert_equal(2, params[:schema_version])
    assert_equal('base', params[:cabinet_type])
    %i[width_mm height_mm depth_mm overlay_mm].each do |key|
      assert(params.key?(key), "Expected params to include #{key}")
    end
    assert_kind_of(Hash, params[:base], 'Expected base style block to be present')
  end

  def test_legacy_upgrade_on_save
    model = Sketchup.active_model
    instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: BASE_PARAMS_MM
    )
    definition = instance.definition

    legacy_params = BASE_PARAMS_MM.reject { |key, _| key == :overlay_mm }
    legacy_json = JSON.generate(legacy_params)
    dictionary = definition.attribute_dictionary(AICabinetsTestHelper::DICTIONARY_NAME, true)
    dictionary[AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY] = legacy_json
    dictionary[AICabinets::Ops::InsertBaseCabinet::DEF_KEY] = 'legacy-key'
    dictionary[AICabinets::Ops::InsertBaseCabinet::SCHEMA_VERSION_KEY] = 1

    selection = model.selection
    selection.clear
    selection.add(instance)

    updated_width_mm = BASE_PARAMS_MM[:width_mm] + 25.0
    updated_params = BASE_PARAMS_MM.merge(width_mm: updated_width_mm)
    result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated_params,
      scope: 'all'
    )
    assert(result[:ok], "Expected edit to succeed: #{result.inspect}")

    upgraded_params = AICabinetsTestHelper.params_mm_from_definition(definition)
    assert_equal(2, upgraded_params[:schema_version], 'Expected schema_version to upgrade to 2')
    assert_equal('base', upgraded_params[:cabinet_type], 'Expected legacy definitions to infer base cabinet_type')
    assert_kind_of(Hash, upgraded_params[:base], 'Expected base style block after upgrade')

    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    bbox_width_mm = AICabinetsTestHelper.mm(definition.bounds.width)
    assert_in_delta(updated_width_mm, bbox_width_mm, tolerance_mm,
                    'Expected geometry to rebuild with updated width')
  end

  def test_upper_style_round_trip
    model = Sketchup.active_model
    definitions = model.definitions
    definition = definitions.add('AI Cabinets Upper Cabinet')

    params = {
      schema_version: 2,
      cabinet_type: 'upper',
      width_mm: 762.0,
      height_mm: 762.0,
      depth_mm: 305.0,
      overlay_mm: 2.0,
      upper: { num_shelves: 2, has_back: true }
    }

    json = AICabinets::Ops::ParamsSchema.canonical_json(params, cabinet_type: 'upper')
    def_key = Digest::SHA256.hexdigest(json)
    AICabinets::Ops::InsertBaseCabinet.__send__(
      :assign_definition_attributes,
      definition,
      def_key,
      json
    )

    round_tripped = AICabinetsTestHelper.params_mm_from_definition(definition)
    assert_equal('upper', round_tripped[:cabinet_type])
    assert_equal(2, round_tripped[:schema_version])
    assert_equal({ num_shelves: 2, has_back: true }, round_tripped[:upper])
  end

  def test_unknown_keys_preserved_through_edit
    model = Sketchup.active_model
    params_with_extra = BASE_PARAMS_MM.merge(custom_block: { note: 'keep_me' })
    instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: params_with_extra
    )

    selection = model.selection
    selection.clear
    selection.add(instance)

    updated_params = params_with_extra.merge(width_mm: BASE_PARAMS_MM[:width_mm] + 10.0)
    result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated_params,
      scope: 'all'
    )
    assert(result[:ok], "Expected edit to succeed: #{result.inspect}")

    stored_params = AICabinetsTestHelper.params_mm_from_definition(instance)
    assert_equal('keep_me', stored_params.dig(:custom_block, :note))
  end

  def test_params_not_stored_on_instance
    model = Sketchup.active_model
    instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: BASE_PARAMS_MM
    )

    dictionary = instance.attribute_dictionary(AICabinetsTestHelper::DICTIONARY_NAME)
    assert_nil(dictionary&.[]('params_json_mm'), 'Expected params_json_mm to be stored only on the definition')
  end
end
