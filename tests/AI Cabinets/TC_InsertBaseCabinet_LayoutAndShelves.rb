# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/model_query'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/test_harness')

class TC_InsertBaseCabinet_LayoutAndShelves < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_partition_none_respects_left_layout_and_shelves
    definition, instance = insert_base(front: 'doors_left', shelves: 1)

    assert_single_hinged_door(instance, hinge: 'Left')
    assert_shelf_count(instance, expected: 1)
    assert_params(definition, front: 'doors_left', shelves: 1)
  end

  def test_partition_none_respects_right_layout_and_shelves
    definition, instance = insert_base(front: 'doors_right', shelves: 0)

    assert_single_hinged_door(instance, hinge: 'Right')
    assert_shelf_count(instance, expected: 0)
    assert_params(definition, front: 'doors_right', shelves: 0)
  end

  def test_partition_none_respects_double_layout_and_shelves
    definition, instance = insert_base(front: 'doors_double', shelves: 3)

    assert_double_doors(instance)
    assert_shelf_count(instance, expected: 3)
    assert_params(definition, front: 'doors_double', shelves: 3)
  end

  private

  def insert_base(front:, shelves:)
    config = base_config(front: front, shelves: shelves)
    AICabinets::TestHarness.insert!(config: config)
  end

  def base_config(front:, shelves:)
    defaults = deep_copy(AICabinets::Defaults.load_effective_mm)
    defaults[:front] = front
    defaults[:shelves] = shelves
    defaults[:partition_mode] = 'none'
    defaults[:partitions] = { mode: 'none', count: 0, positions_mm: [], bays: [] }
    defaults
  end

  def assert_single_hinged_door(instance, hinge:)
    fronts = ModelQuery.front_entities(instance: instance)
    assert_equal(1, fronts.length, 'Expected a single hinged door')

    names = fronts.map { |entry| name_for(entry[:entity]) }
    assert(names.all? { |name| name.include?(hinge) },
           "Expected door name(s) to include '#{hinge}': #{names.inspect}")
  end

  def assert_double_doors(instance)
    fronts = ModelQuery.front_entities(instance: instance)
    assert_equal(2, fronts.length, 'Expected a pair of doors for double layout')

    names = fronts.map { |entry| name_for(entry[:entity]) }
    assert(names.any? { |name| name.include?('Left') },
           "Expected one leaf to include 'Left': #{names.inspect}")
    assert(names.any? { |name| name.include?('Right') },
           "Expected one leaf to include 'Right': #{names.inspect}")
  end

  def assert_shelf_count(instance, expected:)
    shelves = ModelQuery.shelves_by_bay(instance: instance)
    actual = shelves.fetch(1, []).length
    assert_equal(expected, actual, 'Shelf count should match selection')
  end

  def assert_params(definition, front:, shelves:)
    params = AICabinetsTestHelper.params_mm_from_definition(definition)

    assert_equal('none', params[:partition_mode], 'Partition mode should be none')
    assert_equal(front, params[:front], 'Front layout should be persisted')
    assert_equal(shelves, params[:shelves], 'Shelves should be persisted')

    partitions = params[:partitions] || {}
    assert_equal('none', partitions[:mode], 'Partitions mode should remain none')
    assert_equal([], partitions[:bays] || [], 'Partitions bays should not seed defaults')
  end

  def name_for(entity)
    definition = entity.definition if entity.respond_to?(:definition)
    name = entity.respond_to?(:name) ? entity.name.to_s : ''
    definition_name = definition&.respond_to?(:name) ? definition.name.to_s : ''
    name.empty? ? definition_name : name
  end

  def deep_copy(object)
    Marshal.load(Marshal.dump(object))
  end
end
