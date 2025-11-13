# frozen_string_literal: true

# Consolidated core Rows scenarios covering persistence, membership, and
# validation flows. Shared placement helpers live in
# tests/support/rows_shared_helpers.rb.
require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/rows_shared_helpers'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

class TC_Rows < TestUp::TestCase
  include RowsSharedTestHelpers

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_create_row_from_selection_persists_membership
    model = Sketchup.active_model
    first, second, third = place_cabinets(model, count: 3)

    select_instances(model, [first, second, third])

    row_id = AICabinets::Rows.create_from_selection(model: model)

    assert_kind_of(String, row_id)
    refute_empty(row_id, 'Expected create_from_selection to return a row id')

    rows = AICabinets::Rows.list(model)
    assert_equal(1, rows.length, 'Expected one row to be stored')

    row = rows.first
    assert_equal(row_id, row[:row_id])

    expected_pids = [first, second, third].map { |instance| instance.persistent_id.to_i }
    assert_equal(expected_pids, row[:member_pids])

    assert_in_delta(AICabinets::Rows::DEFAULT_ROW_REVEAL_MM, row[:row_reveal_mm], 1e-6)
    assert_equal(false, row[:lock_total_length])
    assert_nil(row[:total_length_mm])

    [first, second, third].each_with_index do |instance, index|
      membership = AICabinets::Rows.for_instance(instance)
      refute_nil(membership, 'Expected row membership attributes to be stamped')
      assert_equal(row_id, membership[:row_id])
      assert_equal(index + 1, membership[:row_pos])
    end

    dictionary = model.attribute_dictionary(AICabinets::Rows::MODEL_DICTIONARY)
    refute_nil(dictionary, 'Expected model dictionary to exist after creating a row')

    json = dictionary[AICabinets::Rows::MODEL_JSON_KEY]
    refute_nil(json, 'Expected JSON state to be stored in the model dictionary')

    parsed = JSON.parse(json)
    assert_equal(1, parsed['schema_version'])
    assert(parsed['rows'].key?(row_id), 'Row id should be present in persisted state')
  end

  def test_row_membership_updates_after_deletion
    model = Sketchup.active_model
    first, second, third = place_cabinets(model, count: 3)

    select_instances(model, [first, second, third])
    row_id = AICabinets::Rows.create_from_selection(model: model)
    assert_kind_of(String, row_id)

    model.entities.erase_entities(first)

    rows = AICabinets::Rows.list(model)
    assert_equal(1, rows.length, 'Row should remain while members exist')

    row = rows.first
    expected_pids = [second, third].map { |instance| instance.persistent_id.to_i }
    assert_equal(expected_pids, row[:member_pids])

    membership_second = AICabinets::Rows.for_instance(second)
    assert_equal(1, membership_second[:row_pos], 'Row positions should be renumbered after deletion')

    membership_third = AICabinets::Rows.for_instance(third)
    assert_equal(2, membership_third[:row_pos])
  end

  def test_create_row_rejects_non_cabinet_selection
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)
    stray_group = model.entities.add_group

    select_instances(model, [first, stray_group, second])

    result = AICabinets::Rows.create_from_selection(model: model)

    assert_kind_of(AICabinets::Rows::Result, result)
    refute(result.ok?)
    assert_equal(:invalid_entities, result.code)

    rows = AICabinets::Rows.list(model)
    assert_empty(rows, 'Invalid selection should not create any rows')
  end

  def test_duplicate_instance_does_not_join_row
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)
    select_instances(model, [first, second])

    row_id = AICabinets::Rows.create_from_selection(model: model)
    assert_kind_of(String, row_id)

    duplicate = model.entities.add_instance(second.definition, second.transformation)
    duplicate.set_attribute(AICabinets::Rows::INSTANCE_DICTIONARY, AICabinets::Rows::ROW_ID_KEY, row_id)
    duplicate.set_attribute(AICabinets::Rows::INSTANCE_DICTIONARY, AICabinets::Rows::ROW_POS_KEY, 99)

    rows = AICabinets::Rows.list(model)
    assert_equal(1, rows.length)

    membership = AICabinets::Rows.for_instance(duplicate)
    assert_nil(membership, 'Duplicate should not remain associated with the row')

    row = rows.first
    expected_pids = [first, second].map { |instance| instance.persistent_id.to_i }
    assert_equal(expected_pids, row[:member_pids])
  end
end
