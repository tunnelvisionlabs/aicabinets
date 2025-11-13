# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/ui/rows/manager_dialog')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

class TC_Rows_Dialog_RPC < TestUp::TestCase
  BASE_PARAMS_MM = {
    width_mm: 762.0,
    depth_mm: 609.6,
    height_mm: 914.4,
    panel_thickness_mm: 18.0,
    toe_kick_height_mm: 101.6,
    toe_kick_depth_mm: 76.2,
    bay_count: 1,
    partitions_enabled: false,
    fronts_enabled: false
  }.freeze

  def setup
    manager_dialog.enable_test_mode!
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    manager_dialog.disable_test_mode!
    AICabinetsTestHelper.clean_model!
  end

  def test_rows_list_returns_summary
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)
    select_instances(model, [first, second])
    AICabinets::Rows.create_from_selection(model: model)

    result = manager_dialog.invoke_rpc_for_test('rows.list')
    assert_kind_of(Hash, result)
    rows = result[:rows] || result['rows']
    assert_equal(1, rows.length)
    summary = rows.first
    assert(summary[:row_reveal_formatted] || summary['row_reveal_formatted'])
  end

  def test_rows_get_sets_active_row
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)
    select_instances(model, [first, second])
    row_id = AICabinets::Rows.create_from_selection(model: model)

    detail = manager_dialog.invoke_rpc_for_test('rows.get', row_id: row_id)
    row = detail[:row]
    assert_equal(row_id, row[:row_id])
    assert_equal(2, row[:member_pids].length)

    selection = model.selection
    assert_equal(2, selection.length)
  end

  def test_rows_add_members
    model = Sketchup.active_model
    first, second, third = place_cabinets(model, count: 3)
    select_instances(model, [first, second])
    row_id = AICabinets::Rows.create_from_selection(model: model)

    detail = manager_dialog.invoke_rpc_for_test('rows.add_members', row_id: row_id, pids: [third.persistent_id])
    row = detail[:row]
    assert_equal(3, row[:member_pids].length)
  end

  def test_rows_remove_members
    model = Sketchup.active_model
    first, second, third = place_cabinets(model, count: 3)
    select_instances(model, [first, second, third])
    row_id = AICabinets::Rows.create_from_selection(model: model)

    detail = manager_dialog.invoke_rpc_for_test('rows.remove_members', row_id: row_id, pids: [third.persistent_id])
    row = detail[:row]
    assert_equal(2, row[:member_pids].length)
    refute_includes(row[:member_pids], third.persistent_id)
  end

  def test_rows_reorder
    model = Sketchup.active_model
    first, second, third = place_cabinets(model, count: 3)
    select_instances(model, [first, second, third])
    row_id = AICabinets::Rows.create_from_selection(model: model)

    order = [third, second, first].map { |instance| instance.persistent_id }
    detail = manager_dialog.invoke_rpc_for_test('rows.reorder', row_id: row_id, order: order)
    row = detail[:row]
    assert_equal(order, row[:member_pids])
  end

  def test_rows_update_reveal
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)
    select_instances(model, [first, second])
    row_id = AICabinets::Rows.create_from_selection(model: model)

    detail = manager_dialog.invoke_rpc_for_test('rows.update', row_id: row_id, row_reveal_mm: 5.0)
    row = detail[:row]
    assert_in_delta(5.0, row[:row_reveal_mm], 1e-6)
    assert_match(/5/, row[:row_reveal_formatted])
  end

  def test_rows_highlight_toggle
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)
    select_instances(model, [first, second])
    row_id = AICabinets::Rows.create_from_selection(model: model)

    response = manager_dialog.invoke_rpc_for_test('rows.highlight', row_id: row_id, on: true)
    assert_kind_of(Hash, response)
    assert(response[:ok] || response['ok'])
  end

  private

  def manager_dialog
    AICabinets::UI::Rows::ManagerDialog
  end

  def place_cabinets(model, count: 1)
    instances = []
    count.times do |index|
      offset_mm = index * (BASE_PARAMS_MM[:width_mm] + 5.0)
      point = ::Geom::Point3d.new(offset_mm.mm, 0, 0)
      instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
        model: model,
        point3d: point,
        params_mm: BASE_PARAMS_MM
      )
      instances << instance
    end
    instances
  end

  def select_instances(model, entities)
    selection = model.selection
    selection.clear
    Array(entities).each { |entity| selection.add(entity) }
  end
end
