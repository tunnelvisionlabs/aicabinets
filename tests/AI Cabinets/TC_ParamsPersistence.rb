# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/params/persistence')
Sketchup.require('aicabinets/defaults')

class TC_ParamsPersistence < TestUp::TestCase
  include AICabinetsTestHelper

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_read_missing_params_creates_defaults
    definition = create_definition

    params = AICabinets::Params.read(definition)

    assert_equal(AICabinets::PARAMS_SCHEMA_VERSION, params[:schema_version])
    assert_kind_of(Hash, params[:face_frame])
    face_frame_keys = AICabinets::FaceFrame.defaults_mm.keys.select { |key| key.to_s.end_with?('_mm') }
    face_frame_keys.each do |key|
      assert(params[:face_frame].key?(key), "face_frame missing #{key}")
      assert(params[:face_frame][key].is_a?(Numeric), "face_frame #{key} should be numeric")
    end
  end

  def test_migrate_missing_face_frame
    legacy = {
      'schema_version' => 1,
      'width_mm' => 600.0,
      'depth_mm' => 600.0,
      'height_mm' => 720.0,
      'panel_thickness_mm' => 18.0,
      'toe_kick_height_mm' => 100.0,
      'toe_kick_depth_mm' => 50.0,
      'toe_kick_thickness_mm' => 18.0
    }
    definition = create_definition
    definition.set_attribute('AICabinets', 'params_json_mm', JSON.generate(legacy))

    params = AICabinets::Params.read(definition)

    assert_equal(AICabinets::PARAMS_SCHEMA_VERSION, params[:schema_version])
    assert_kind_of(Hash, params[:face_frame])
    AICabinets::Params.write!(definition, params)

    stored = JSON.parse(definition.get_attribute('AICabinets', 'params_json_mm'))
    assert(stored.key?('face_frame'))
    assert_equal(AICabinets::PARAMS_SCHEMA_VERSION, stored['schema_version'])
  end

  def test_copy_and_make_unique_preserves_params
    defaults = default_params
    definition = create_definition
    AICabinets::Params.write!(definition, defaults)

    model = Sketchup.active_model
    instance = model.entities.add_instance(definition, Geom::Transformation.new)
    unique_instance = model.entities.add_instance(definition, Geom::Transformation.translation([10, 0, 0]))
    unique_instance.make_unique

    unique_definition = unique_instance.definition
    copied_params = AICabinets::Params.read(unique_definition)

    assert_equal(defaults[:schema_version], copied_params[:schema_version])
    assert_equal(defaults[:face_frame][:thickness_mm], copied_params[:face_frame][:thickness_mm])
  end

  def test_round_trip_preserves_unknown_fields
    definition = create_definition
    params = default_params
    params[:custom] = { 'note' => 'keep me', future: [1, 2, 3] }

    AICabinets::Params.write!(definition, params)
    first_json = definition.get_attribute('AICabinets', 'params_json_mm')

    reloaded = AICabinets::Params.read(definition)
    AICabinets::Params.write!(definition, reloaded)

    second_json = definition.get_attribute('AICabinets', 'params_json_mm')
    assert_equal(first_json, second_json)
  end

  def test_validation_blocks_invalid_face_frame
    definition = create_definition
    params = default_params
    params[:face_frame][:thickness_mm] = 9.0

    assert_raises(ArgumentError) do
      AICabinets::Params.write!(definition, params)
    end

    assert_nil(definition.get_attribute('AICabinets', 'params_json_mm'))
  end

  private

  def create_definition
    Sketchup.active_model.definitions.add('Params Test')
  end

  def default_params
    defaults = AICabinets::Defaults.load_effective_mm
    base = defaults[:cabinet_base].merge(face_frame: defaults[:face_frame])
    base[:schema_version] = AICabinets::PARAMS_SCHEMA_VERSION
    base
  end
end
