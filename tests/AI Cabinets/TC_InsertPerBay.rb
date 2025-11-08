# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/model_query'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/test_harness')
Sketchup.require('aicabinets/generator/fronts')
Sketchup.require('aicabinets/generator/carcass')

class TC_InsertPerBay < TestUp::TestCase
  DOOR_GAP_MM = 4.0
  WIDTH_MM = 1100.0

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_insert_generates_per_bay_shelves_and_fronts
    config = base_config

    definition, instance = AICabinets::TestHarness.insert!(config: config)

    shelf_counts = ModelQuery.shelves_by_bay(instance: instance).transform_values(&:length)
    assert_equal(0, shelf_counts.fetch(1, 0), 'Expected bay 1 to omit shelves')
    assert_equal(2, shelf_counts.fetch(2, 0), 'Expected bay 2 to include two shelves')
    assert_equal(1, shelf_counts.fetch(3, 0), 'Expected bay 3 to include one shelf')

    shelves = shelf_entities(definition)
    refute_empty(shelves, 'Expected shelves to be created for populated bays')
    shelves.each do |entity|
      assert_equal('Shelves', ModelQuery.tag_category_for(entity),
                   'Shelves should use the dedicated tag category')
    end

    fronts_by_bay = ModelQuery.fronts_by_bay(instance: instance)
    assert_equal(1, fronts_by_bay.fetch(2, []).length,
                 'Expected a single hinged door for bay 2')
    assert_equal(2, fronts_by_bay.fetch(3, []).length,
                 'Expected a pair of leaves for bay 3')
    fronts_by_bay.values.flatten.each do |info|
      assert_equal('Fronts',
                   ModelQuery.tag_category_for(info[:entity]),
                   'Front leaves should use the dedicated tag category')
    end

    verify_double_leaf_widths(definition, instance, fronts_by_bay.fetch(3, []))

    Sketchup.undo
    model = Sketchup.active_model
    assert_empty(model.entities.grep(Sketchup::ComponentInstance),
                 'Undo should remove the inserted cabinet in one step')
  end

  private

  def base_config
    defaults = deep_copy(AICabinets::Defaults.load_effective_mm)
    defaults[:width_mm] = WIDTH_MM
    defaults[:front] = 'empty'
    defaults[:door_gap_mm] = DOOR_GAP_MM
    defaults[:partition_mode] = 'vertical'

    partitions = defaults[:partitions]
    partitions[:mode] = 'even'
    partitions[:count] = 2
    partitions[:orientation] = 'vertical'
    partitions[:bays] = [
      bay_config(shelf_count: 0, door_mode: 'empty'),
      bay_config(shelf_count: 2, door_mode: 'doors_left'),
      bay_config(shelf_count: 1, door_mode: 'doors_double')
    ]

    defaults
  end

  def bay_config(shelf_count:, door_mode:)
    {
      mode: 'fronts_shelves',
      shelf_count: shelf_count,
      door_mode: door_mode,
      fronts_shelves_state: {
        shelf_count: shelf_count,
        door_mode: door_mode
      },
      subpartitions_state: { count: 0 },
      subpartitions: {
        count: 0,
        orientation: 'horizontal',
        bays: []
      }
    }
  end

  def shelf_entities(definition)
    definition.entities.grep(Sketchup::ComponentInstance).select do |entity|
      name = entity.definition&.name.to_s
      name.downcase.include?('shelf')
    end
  end

  def verify_double_leaf_widths(definition, instance, leaf_infos)
    params = AICabinetsTestHelper.params_mm_from_definition(definition)
    param_set = AICabinets::Generator::Carcass::ParameterSet.new(params)
    placements = AICabinets::Generator::Fronts.plan_layout(param_set)
    bay3_layout = placements.select { |placement| placement.bay_index == 2 }
    assert_equal(2, bay3_layout.length,
                 'Expected generator to plan two leaves for bay 3')

    assert_equal(bay3_layout.sum(&:width_mm),
                 leaf_infos.sum { |info| info[:width_mm] },
                 'Leaf widths should match planned layout')

    ordered = leaf_infos.sort_by { |info| info[:bounds].min.x }
    gap_length = ordered[1][:bounds].min.x - ordered[0][:bounds].max.x
    gap_mm = AICabinetsTestHelper.mm_from_length(gap_length)
    tolerance_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    assert_in_delta(DOOR_GAP_MM, gap_mm, tolerance_mm,
                    'Leaf gap should respect the requested door gap')
  end

  def deep_copy(object)
    Marshal.load(Marshal.dump(object))
  end
end
