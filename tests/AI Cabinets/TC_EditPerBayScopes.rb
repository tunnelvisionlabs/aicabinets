# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/model_query'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/test_harness')

class TC_EditPerBayScopes < TestUp::TestCase
  WIDTH_MM = 1100.0
  DOOR_GAP_MM = 4.0

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_edit_all_instances_updates_each_copy
    definition, first_instance, second_instance = build_two_instances

    patch = {
      partitions: {
        bays: [
          nil,
          {
            door_mode: 'doors_right',
            fronts_shelves_state: { door_mode: 'doors_right' }
          }
        ]
      }
    }

    AICabinets::TestHarness.edit_all_instances!(definition: definition, config_patch: patch)

    assert_same(first_instance.definition, second_instance.definition,
                'All-instances edit should keep instances sharing one definition')

    params = AICabinetsTestHelper.params_mm_from_definition(first_instance.definition)
    door_mode = params[:partitions][:bays][1][:door_mode]
    assert_equal('doors_right', door_mode,
                 'Door mode should update on the shared definition')

    [first_instance, second_instance].each do |instance|
      fronts = ModelQuery.fronts_by_bay(instance: instance)
      door = fronts.fetch(2, []).first
      refute_nil(door, 'Expected bay 2 to retain a single leaf after edit')
      name = door[:entity].definition&.name.to_s
      assert_includes(name, 'Hinge Right', 'Door should change to hinge-right orientation')
    end

    Sketchup.undo

    params_after_undo = AICabinetsTestHelper.params_mm_from_definition(definition)
    assert_equal('doors_left', params_after_undo[:partitions][:bays][1][:door_mode],
                 'Undo should restore the prior door mode for all instances')
  end

  def test_edit_this_instance_only_updates_selected_copy
    definition, first_instance, second_instance = build_two_instances

    patch = {
      partitions: {
        bays: [
          nil,
          nil,
          {
            shelf_count: 3,
            fronts_shelves_state: { shelf_count: 3 }
          }
        ]
      }
    }

    AICabinets::TestHarness.edit_this_instance!(instance: first_instance, config_patch: patch)

    refute_same(first_instance.definition, second_instance.definition,
                'Instance edit should create a unique definition for the edited copy')

    edited_counts = ModelQuery.shelves_by_bay(instance: first_instance).transform_values(&:length)
    assert_equal(3, edited_counts.fetch(3, 0),
                 'Edited instance should reflect the new shelf count')

    sibling_counts = ModelQuery.shelves_by_bay(instance: second_instance).transform_values(&:length)
    assert_equal(1, sibling_counts.fetch(3, 0),
                 'Sibling instance should retain the original shelf count')

    Sketchup.undo

    reverted_counts = ModelQuery.shelves_by_bay(instance: first_instance).transform_values(&:length)
    assert_equal(1, reverted_counts.fetch(3, 0),
                 'Undo should restore the original bay shelf count for the edited instance')
    assert_same(second_instance.definition, first_instance.definition,
                'Undo should restore a shared definition across both instances')
  end

  private

  def build_two_instances
    config = base_config
    definition, first_instance = AICabinets::TestHarness.insert!(config: config)

    offset = Geom::Transformation.translation([(WIDTH_MM + 200.0).mm, 0, 0])
    second_instance = Sketchup.active_model.active_entities.add_instance(definition, offset)

    [definition, first_instance, second_instance]
  end

  def base_config
    defaults = deep_copy(AICabinets::Defaults.load_effective_mm)
    defaults[:width_mm] = WIDTH_MM
    defaults[:door_gap_mm] = DOOR_GAP_MM
    defaults[:front] = 'empty'
    defaults[:partition_mode] = 'vertical'

    partitions = defaults[:partitions]
    partitions[:mode] = 'even'
    partitions[:count] = 2
    partitions[:orientation] = 'vertical'
    partitions[:bays] = [
      bay_config(shelf_count: 0, door_mode: 'empty'),
      bay_config(shelf_count: 1, door_mode: 'doors_left'),
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

  def deep_copy(object)
    Marshal.load(Marshal.dump(object))
  end
end
