# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/metadata')
Sketchup.require('aicabinets/bom')
Sketchup.require('aicabinets/geometry/five_piece')
Sketchup.require('aicabinets/geometry/five_piece_panel')
Sketchup.require('aicabinets/params/five_piece')

class TC_FivePieceMetadataBOM < TestUp::TestCase
  OPENING_W_MM = 620.0
  OPENING_H_MM = 740.0
  BASE_PARAMS = AICabinets::Params::FivePiece.defaults.merge(
    door_thickness_mm: 19.0,
    groove_width_mm: 18.0
  ).freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_attributes_on_all_parts
    definition, parts = build_door_with_metadata

    part_definitions(parts).each do |component_def|
      dictionary = component_def.attribute_dictionary(AICabinets::Metadata::DICTIONARY_NAME)
      refute_nil(dictionary, 'Expected metadata dictionary to exist')

      assert_includes(%w[stile rail panel], dictionary['part_type'])
      assert_equal('cope_stick', dictionary['joint_type'])
      assert_equal('flat', dictionary['panel_type'])
      assert_equal(AICabinets::Metadata::SCHEMA_VERSION, dictionary['schema_version'])
    end
  end

  def test_tags_applied_to_all_parts
    definition, parts = build_door_with_metadata

    parts.values.flatten.compact.each do |group|
      assert_equal('AICabinets/Fronts', group.layer.name)
    end

    definition.entities.grep(Sketchup::Group).each do |group|
      assert_equal('AICabinets/Fronts', group.layer.name)
    end
  end

  def test_stable_names_without_dimensions
    definition, parts = build_door_with_metadata
    expected_names = %w[Door-Stile-L Door-Stile-R Door-Rail-Bottom Door-Rail-Top Door-Panel]

    names = (parts.values.flatten.compact.map(&:name) + part_definitions(parts).map(&:name)).uniq
    assert_equal(expected_names.sort, names.sort)
    names.each do |name|
      refute_match(/\d/, name, 'Names must not embed dimensions')
    end
  end

  def test_metadata_refreshes_with_joint_and_panel_changes
    params = BASE_PARAMS.dup
    definition, = build_door_with_metadata(params: params)

    params[:joint_type] = 'miter'
    params[:panel_style] = 'raised'

    frame_result = AICabinets::Geometry::FivePiece.build_frame!(
      target: definition,
      params: params,
      open_w_mm: OPENING_W_MM,
      open_h_mm: OPENING_H_MM
    )

    panel_result = AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      style: params[:panel_style],
      open_w_mm: OPENING_W_MM,
      open_h_mm: OPENING_H_MM
    )

    AICabinets::Metadata.write_five_piece!(
      definition: definition,
      params: params,
      parts: {
        stiles: frame_result[:stiles],
        rails: frame_result[:rails],
        panel: panel_result[:panel]
      }
    )

    part_definitions(stiles: frame_result[:stiles], rails: frame_result[:rails], panel: panel_result[:panel]).each do |component_def|
      dictionary = component_def.attribute_dictionary(AICabinets::Metadata::DICTIONARY_NAME)
      assert_equal('miter', dictionary['joint_type'])
      assert_equal('raised', dictionary['panel_type'])
    end

    names = definition.entities.grep(Sketchup::Group).map(&:name).uniq
    assert_equal(%w[Door-Rail-Bottom Door-Rail-Top Door-Stile-L Door-Stile-R Door-Panel].sort, names.sort)
  end

  def test_frame_only_metadata_and_bom
    definition, parts = build_door_with_metadata(include_panel: false)

    dictionary_values = part_definitions(parts).map do |component_def|
      component_def.attribute_dictionary(AICabinets::Metadata::DICTIONARY_NAME)
    end
    dictionary_values.each do |dictionary|
      assert_equal('flat', dictionary['panel_type'])
    end

    rows = AICabinets::BOM.parts_for(definition: definition)
    counts = rows.each_with_object(Hash.new(0)) { |row, memo| memo[row[:part_type]] += 1 }
    assert_equal({ stile: 2, rail: 2 }, counts)
  end

  def test_bom_grouping_counts
    definition, = build_door_with_metadata

    rows = AICabinets::BOM.parts_for(definition: definition)
    counts = rows.each_with_object(Hash.new(0)) { |row, memo| memo[row[:part_type]] += 1 }

    assert_equal({ stile: 2, rail: 2, panel: 1 }, counts)
  end

  def test_instance_only_metadata_is_isolated
    definition, = build_door_with_metadata
    model = Sketchup.active_model
    instance_one = model.entities.add_instance(definition, Geom::Transformation.new)
    instance_two = model.entities.add_instance(definition, Geom::Transformation.translation([100.mm, 0, 0]))

    updated_params = BASE_PARAMS.merge(joint_type: 'miter', panel_style: 'reverse_raised')
    frame_result = AICabinets::Geometry::FivePiece.build_frame!(
      target: instance_one,
      params: updated_params,
      open_w_mm: OPENING_W_MM,
      open_h_mm: OPENING_H_MM
    )

    panel_result = AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: instance_one,
      params: updated_params,
      style: updated_params[:panel_style],
      open_w_mm: OPENING_W_MM,
      open_h_mm: OPENING_H_MM
    )

    AICabinets::Metadata.write_five_piece!(
      definition: instance_one,
      params: updated_params,
      parts: {
        stiles: frame_result[:stiles],
        rails: frame_result[:rails],
        panel: panel_result[:panel]
      }
    )

    updated_definition = instance_one.definition
    sibling_definition = instance_two.definition

    updated_dictionary = part_definitions(stiles: frame_result[:stiles], rails: frame_result[:rails], panel: panel_result[:panel]).first.attribute_dictionary(AICabinets::Metadata::DICTIONARY_NAME)
    assert_equal('miter', updated_dictionary['joint_type'])
    assert_equal('reverse_raised', updated_dictionary['panel_type'])

    sibling_dictionaries = sibling_definition.entities.grep(Sketchup::Group).map do |group|
      group.definition.attribute_dictionary(AICabinets::Metadata::DICTIONARY_NAME)
    end
    sibling_dictionaries.each do |dictionary|
      assert_equal('cope_stick', dictionary['joint_type'])
      assert_equal('flat', dictionary['panel_type'])
    end

    refute_equal(updated_definition, sibling_definition)
  end

  def test_slabs_are_ignored
    model = Sketchup.active_model
    definition = model.definitions.add('Slab Door')
    group = definition.entities.add_group
    face = group.entities.add_face(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(OPENING_W_MM.mm, 0, 0), Geom::Point3d.new(OPENING_W_MM.mm, 0, OPENING_H_MM.mm), Geom::Point3d.new(0, 0, OPENING_H_MM.mm))
    face.pushpull(19.mm) if face

    result = AICabinets::Metadata.write_five_piece!(definition: definition, params: { door_type: 'slab' }, parts: {})

    refute(result[:applied])
    assert_nil(definition.attribute_dictionary(AICabinets::Metadata::DICTIONARY_NAME))
    assert_equal('Slab Door', definition.name)
  end

  private

  def build_door_with_metadata(params: BASE_PARAMS, include_panel: true)
    definition = Sketchup.active_model.definitions.add('Five-Piece Door')
    frame_result = AICabinets::Geometry::FivePiece.build_frame!(
      target: definition,
      params: params,
      open_w_mm: OPENING_W_MM,
      open_h_mm: OPENING_H_MM
    )

    panel_result = nil
    if include_panel
      panel_result = AICabinets::Geometry::FivePiecePanel.build_panel!(
        target: definition,
        params: params,
        style: params[:panel_style],
        open_w_mm: OPENING_W_MM,
        open_h_mm: OPENING_H_MM
      )
    end

    AICabinets::Metadata.write_five_piece!(
      definition: definition,
      params: params,
      parts: {
        stiles: frame_result[:stiles],
        rails: frame_result[:rails],
        panel: panel_result && panel_result[:panel]
      }
    )

    [definition, { stiles: frame_result[:stiles], rails: frame_result[:rails], panel: panel_result && panel_result[:panel] }]
  end

  def part_definitions(parts)
    parts.values.flatten.compact.map do |group|
      group.definition if group.respond_to?(:definition)
    end.compact
  end
end
