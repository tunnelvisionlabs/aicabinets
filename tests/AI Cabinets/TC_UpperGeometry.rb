# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'
require_relative '../support/model_query'

Sketchup.require('aicabinets/ops/insert_upper_cabinet')
Sketchup.require('aicabinets/ops/edit_upper_cabinet')

class TC_UpperGeometry < TestUp::TestCase
  include AICabinetsTestHelper

  BASE_PARAMS = {
    width_mm: 900.0,
    depth_mm: 350.0,
    height_mm: 700.0,
    overlay_mm: 0.0,
    panel_thickness_mm: 18.0,
    back_thickness_mm: 6.0,
    top_thickness_mm: 18.0,
    bottom_thickness_mm: 18.0,
    door_thickness_mm: 19.0,
    upper: { num_shelves: 2, has_back: true }
  }.freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_bounding_box_and_anchor
    model = Sketchup.active_model
    instance = insert_upper(BASE_PARAMS)
    definition = instance.definition
    bounds = definition.bounds

    assert_in_delta(BASE_PARAMS[:width_mm], mm_from_length(bounds.width), mm(tolerance_mm))
    assert_in_delta(BASE_PARAMS[:depth_mm], mm_from_length(bounds.depth), mm(tolerance_mm))
    assert_in_delta(BASE_PARAMS[:height_mm], mm_from_length(bounds.height), mm(tolerance_mm))

    assert_in_delta(0.0, mm_from_length(bounds.min.x), mm(tolerance_mm))
    assert_in_delta(0.0, mm_from_length(bounds.min.y), mm(tolerance_mm))
    assert_in_delta(0.0, mm_from_length(bounds.min.z), mm(tolerance_mm))

    Sketchup.undo
    assert_equal(0, model.active_entities.length, 'Insert should undo in a single step')
  end

  def test_parts_and_back_toggle
    params = BASE_PARAMS
    instance = insert_upper(params)
    assert_part_counts(instance.definition, back_expected: true)

    no_back_params = deep_dup_params(params)
    no_back_params[:upper] = params[:upper].merge(has_back: false)
    other_instance = insert_upper(no_back_params)
    assert_part_counts(other_instance.definition, back_expected: false)
  end

  def test_shelf_spacing_and_clearance
    params = BASE_PARAMS.merge(upper: { num_shelves: 2, has_back: true })
    instance = insert_upper(params)

    shelves = ModelQuery.shelves_by_bay(instance: instance).values.flatten
    assert_equal(2, shelves.length, 'Expected two shelves')

    shelves.each do |info|
      bounds = info[:bounds]
      assert_operator(mm_from_length(bounds.min.z), :>=, params[:bottom_thickness_mm] - tolerance_mm)
      assert_operator(mm_from_length(bounds.max.z), :<=, params[:height_mm] - params[:top_thickness_mm] + tolerance_mm)
      assert_operator(mm_from_length(bounds.min.y), :>=,
                      AICabinets::Generator::Shelves::FRONT_SETBACK_MM - tolerance_mm)

      rear_limit_mm = params[:depth_mm] - params[:back_thickness_mm] - AICabinets::Generator::Shelves::REAR_CLEARANCE_MM +
                      tolerance_mm
      assert_operator(mm_from_length(bounds.max.y), :<=, rear_limit_mm)
    end
  end

  def test_front_rules_and_overlays
    narrow = BASE_PARAMS.merge(width_mm: 500.0)
    narrow_instance = insert_upper(narrow)
    narrow_fronts = ModelQuery.front_entities(instance: narrow_instance)
    assert_equal(1, narrow_fronts.length, 'Narrow cabinet should use a single door')

    wide = BASE_PARAMS.merge(width_mm: 900.0)
    wide_instance = insert_upper(wide)
    wide_fronts = ModelQuery.front_entities(instance: wide_instance)
    assert_equal(2, wide_fronts.length, 'Wide cabinet should use double doors')

    leaf_width_mm = mm_from_length(wide_fronts.first.bounds.width)
    expected_leaf_width = (wide[:width_mm] - (2 * 2.0) - 2.0) / 2.0
    assert_in_delta(expected_leaf_width, leaf_width_mm, mm(tolerance_mm))
  end

  def test_edit_scope_and_undo
    model = Sketchup.active_model
    first = insert_upper(BASE_PARAMS)
    second = insert_upper(BASE_PARAMS.merge(width_mm: BASE_PARAMS[:width_mm]))

    selection = model.selection
    selection.clear
    selection.add(first)

    updated = BASE_PARAMS.merge(upper: { num_shelves: 3, has_back: true })
    result = AICabinets::Ops::EditUpperCabinet.apply_to_selection!(
      model: model,
      params_mm: updated,
      scope: 'instance'
    )
    assert(result[:ok], "Expected edit to succeed: #{result.inspect}")

    first_shelves = ModelQuery.shelves_by_bay(instance: first).values.flatten
    second_shelves = ModelQuery.shelves_by_bay(instance: second).values.flatten
    assert_equal(3, first_shelves.length, 'Instance edit should update only the selected cabinet')
    assert_equal(2, second_shelves.length, 'Sibling cabinet should remain unchanged')

    Sketchup.undo
    reverted_shelves = ModelQuery.shelves_by_bay(instance: first).values.flatten
    assert_equal(2, reverted_shelves.length, 'Undo should revert edit in a single step')
  end

  def test_params_schema_storage
    instance = insert_upper(BASE_PARAMS)
    params = AICabinetsTestHelper.params_mm_from_definition(instance)

    assert_equal(2, params[:schema_version])
    assert_equal('upper', params[:cabinet_type])
    assert_equal(BASE_PARAMS[:upper], params[:upper])
  end

  private

  def insert_upper(params)
    model = Sketchup.active_model
    AICabinets::Ops::InsertUpperCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: params
    )
  end

  def assert_part_counts(definition, back_expected: true)
    entities = definition.entities.grep(Sketchup::ComponentInstance)
    categories = entities.each_with_object(Hash.new(0)) do |entity, memo|
      category = ModelQuery.tag_category_for(entity)
      memo[category] += 1
    end

    assert_equal(2, categories['Sides'], 'Expected two side panels')
    assert_equal(1, categories['Top'], 'Expected one top panel')
    assert_equal(1, categories['Bottom'], 'Expected one bottom panel')
    assert_equal(back_expected ? 1 : 0, categories['Back'].to_i, 'Back presence should match has_back')
    assert_equal(BASE_PARAMS[:upper][:num_shelves], categories['Shelves'].to_i, 'Shelf count should match parameters')
    assert_operator(categories['Fronts'], :>=, 1, 'Expected at least one front component')
  end

  def deep_dup_params(params)
    Marshal.load(Marshal.dump(params))
  end

  def tolerance_mm
    AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
  end

  def length_mm(value)
    AICabinetsTestHelper.mm_from_length(value)
  end

  def mm(value)
    AICabinetsTestHelper.mm(value)
  end

  def mm_from_length(value)
    AICabinetsTestHelper.mm_from_length(value)
  end
end
