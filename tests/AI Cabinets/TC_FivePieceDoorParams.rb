# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/params/five_piece')

class TC_FivePieceDoorParams < TestUp::TestCase
  VALID_BASE_PARAMS = AICabinets::Params::FivePiece.defaults.merge(
    groove_width_mm: 18.0
  ).freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_defaults_include_fallbacks
    defaults = AICabinets::Params::FivePiece.defaults

    assert_equal('five_piece', defaults[:door_type])
    assert_in_delta(57.0, defaults[:stile_width_mm], 1e-6)
    assert_equal(defaults[:stile_width_mm], defaults[:rail_width_mm])
    assert_in_delta(3.0, defaults[:panel_clearance_per_side_mm], 1e-6)
  end

  def test_coerce_normalizes_numeric_strings_and_unknown_keys
    raw = {
      'door_type' => 'five_piece',
      'joint_type' => 'cope_stick',
      'inside_profile_id' => 'square_inside',
      'stile_width_mm' => '60',
      'rail_width' => '',
      'panel_thickness_mm' => '9.5',
      'groove_depth_mm' => '11',
      'panel_clearance_per_side_mm' => '',
      'future_setting' => 'preserve-me'
    }

    params = AICabinets::Params::FivePiece.coerce(raw: raw)

    assert_in_delta(60.0, params[:stile_width_mm], 1e-6)
    assert_in_delta(60.0, params[:rail_width_mm], 1e-6)
    assert_in_delta(3.0, params[:panel_clearance_per_side_mm], 1e-6)
    assert_equal('preserve-me', params[:future_setting])
  end

  def test_validate_fills_rail_width_from_stile_width
    params = VALID_BASE_PARAMS.dup
    params.delete(:rail_width_mm)

    validated = AICabinets::Params::FivePiece.validate!(params: params)

    assert_equal(validated[:stile_width_mm], validated[:rail_width_mm])
  end

  def test_validate_rejects_stile_width_that_is_too_small
    params = VALID_BASE_PARAMS.merge(
      stile_width_mm: 40.0,
      groove_depth_mm: 15.0
    )

    error = assert_raises(AICabinets::ValidationError) do
      AICabinets::Params::FivePiece.validate!(params: params)
    end

    assert(error.messages.any? { |message| message.include?('stile_width_mm') })
  end

  def test_validate_rejects_panel_thickness_exceeding_groove_capacity
    params = VALID_BASE_PARAMS.merge(
      panel_thickness_mm: 12.0,
      groove_width_mm: 14.0,
      panel_clearance_per_side_mm: 3.0
    )

    error = assert_raises(AICabinets::ValidationError) do
      AICabinets::Params::FivePiece.validate!(params: params)
    end

    assert(error.messages.any? do |message|
      message.include?('panel_thickness_mm') && message.include?('groove_width_mm')
    end)
  end

  def test_write_definition_scope_persists_mm_values
    model = Sketchup.active_model
    definition = model.definitions.add('Five Piece Definition Persist Test')

    sanitized = AICabinets::Params::FivePiece.write!(
      definition,
      params: VALID_BASE_PARAMS,
      scope: :definition
    )

    dictionary = definition.attribute_dictionary(AICabinetsTestHelper::DICTIONARY_NAME)
    refute_nil(dictionary, 'Expected dictionary to be created')

    assert_equal('five_piece', dictionary['five_piece:door_type'])
    assert_in_delta(sanitized[:stile_width_mm], dictionary['five_piece:stile_width_mm'], 1e-6)
    assert_in_delta(sanitized[:rail_width_mm], dictionary['five_piece:rail_width_mm'], 1e-6)
    assert_in_delta(sanitized[:panel_clearance_per_side_mm],
                    dictionary['five_piece:panel_clearance_per_side_mm'], 1e-6)

    round_tripped = AICabinets::Params::FivePiece.read(definition)
    assert_in_delta(sanitized[:stile_width_mm], round_tripped[:stile_width_mm], 1e-6)
    assert_equal('five_piece', round_tripped[:door_type])
  end

  def test_write_instance_scope_makes_unique_definition
    model = Sketchup.active_model
    definition = model.definitions.add('Five Piece Shared Definition')
    definition.entities.add_line(ORIGIN, ::Geom::Point3d.new(100.mm, 0, 0))

    first = model.active_entities.add_instance(definition, ::Geom::Transformation.new)
    second = model.active_entities.add_instance(
      definition,
      ::Geom::Transformation.translation([250.mm, 0, 0])
    )

    AICabinets::Params::FivePiece.write!(
      first,
      params: VALID_BASE_PARAMS,
      scope: :instance
    )

    refute_equal(definition, first.definition, 'Expected make_unique to create a new definition')
    assert_equal(definition, second.definition, 'Second instance should still reference original definition')

    new_dictionary = first.definition.attribute_dictionary(AICabinetsTestHelper::DICTIONARY_NAME)
    refute_nil(new_dictionary)
    assert_equal('five_piece', new_dictionary['five_piece:door_type'])

    original_dictionary = definition.attribute_dictionary(AICabinetsTestHelper::DICTIONARY_NAME)
    assert_nil(original_dictionary&.[]('five_piece:door_type'),
               'Original definition should remain unchanged')
  end

  def test_read_returns_defaults_when_no_data_is_present
    model = Sketchup.active_model
    definition = model.definitions.add('Five Piece Read Defaults')

    params = AICabinets::Params::FivePiece.read(definition)

    assert_equal('five_piece', params[:door_type])
    assert_equal(params[:stile_width_mm], params[:rail_width_mm])
  end
end
