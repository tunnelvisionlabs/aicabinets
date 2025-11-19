# frozen_string_literal: true

# Consolidated UI- and interaction-focused Rows scenarios including commands,
# dialog RPCs, highlight overlays, and auto-select behavior. Shared placement
# helpers live in tests/support/rows_shared_helpers.rb.
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/rows_shared_helpers'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/rows/selection')
Sketchup.require('aicabinets/ui/rows')
Sketchup.require('aicabinets/ui/rows/manager_dialog')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

class TC_Rows_UI < TestUp::TestCase
  include RowsSharedTestHelpers

  def setup
    manager_dialog.enable_test_mode!
    AICabinets::Rows::Selection.reset!
    AICabinets::Rows::Highlight.reset!
    AICabinets::Rows::Highlight.test_clear_override!
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    manager_dialog.disable_test_mode!
    AICabinets::Rows::Highlight.test_clear_override!
    AICabinets::Rows::Highlight.reset!
    AICabinets::Rows::Selection.reset!
    AICabinetsTestHelper.clean_model!
  end

  # -- Command registration and toolbar helpers --

  def test_registers_rows_commands
    AICabinets::UI.commands.clear
    AICabinets::UI.register_commands!

    assert_includes(AICabinets::UI.commands.keys, :rows_manage)
    assert_includes(AICabinets::UI.commands.keys, :rows_add_selection)
    assert_includes(AICabinets::UI.commands.keys, :rows_remove_selection)
    assert_includes(AICabinets::UI.commands.keys, :rows_toggle_highlight)
  ensure
    AICabinets::UI.commands.clear
  end

  # -- Command execution flows --

  def test_add_selection_command_appends_members
    model = Sketchup.active_model
    first, second, third = place_cabinets(model, count: 3)

    select_instances(model, [first, second])
    row_id = AICabinets::UI::Rows.create_from_selection
    refute_nil(row_id)

    select_instances(model, [third])
    detail = AICabinets::UI::Rows.add_selection_to_active_row
    refute_nil(detail)

    members = detail[:row][:member_pids]
    assert_equal(3, members.length)
    assert_includes(members, third.persistent_id.to_i)
  end

  def test_remove_selection_command_removes_member
    model = Sketchup.active_model
    first, second, third = place_cabinets(model, count: 3)

    select_instances(model, [first, second, third])
    row_id = AICabinets::UI::Rows.create_from_selection
    refute_nil(row_id)

    select_instances(model, [third])
    detail = AICabinets::UI::Rows.remove_selection_from_active_row
    refute_nil(detail)

    members = detail[:row][:member_pids]
    refute_includes(members, third.persistent_id.to_i)
    assert_equal(2, members.length)
  end

  def test_toggle_highlight_command
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)

    select_instances(model, [first, second])
    row_id = AICabinets::UI::Rows.create_from_selection
    refute_nil(row_id)

    response = AICabinets::UI::Rows.toggle_highlight
    assert(response)
    assert(manager_dialog.highlight_enabled?)

    response = AICabinets::UI::Rows.toggle_highlight
    assert(response)
    refute(manager_dialog.highlight_enabled?)
  end

  # -- Dialog RPC surface --

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

  # -- Highlight overlays --

  def test_overlay_registers_and_clears
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)

    select_instances(model, [first, second])
    row_id = AICabinets::Rows.create_from_selection(model: model)
    assert_kind_of(String, row_id)

    provider = FakeProvider.new
    AICabinets::Rows::Highlight.test_override_provider(
      strategy: :overlay,
      factory: ->(_model) { provider }
    )

    result = AICabinets::Rows.highlight(model: model, row_id: row_id, enabled: true)
    assert_kind_of(Hash, result)
    assert_equal(:overlay, result[:strategy])
    assert_equal(row_id, AICabinets::Rows::Highlight.active_row_id(model: model))

    assert_equal(1, provider.show_calls, 'Expected provider to receive one show call')
    refute_nil(provider.last_geometry, 'Expected geometry to be passed to provider')
    refute_empty(provider.last_geometry.polyline, 'Expected polyline to contain row points')

    result = AICabinets::Rows.highlight(model: model, row_id: row_id, enabled: false)
    assert_kind_of(Hash, result)
    assert_equal(:overlay, result[:strategy])
    assert_nil(AICabinets::Rows::Highlight.active_row_id(model: model))
    assert_equal(1, provider.hide_calls, 'Expected provider to receive one hide call')
  end

  def test_highlight_does_not_create_geometry
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)

    select_instances(model, [first, second])
    row_id = AICabinets::Rows.create_from_selection(model: model)
    assert_kind_of(String, row_id)

    baseline_count = model.entities.length

    AICabinets::Rows::Highlight.test_override_provider(
      strategy: :overlay,
      factory: ->(_model) { NullProvider.new }
    )

    AICabinets::Rows.highlight(model: model, row_id: row_id, enabled: true)
    AICabinets::Rows.highlight(model: model, row_id: row_id, enabled: false)

    assert_equal(baseline_count, model.entities.length, 'Highlight overlay should not add entities to the model')
  end

  # -- Auto-select behaviors --

  def test_auto_select_expands_single_selection
    model = Sketchup.active_model
    members = build_row(model, count: 3)

    AICabinets::Rows::Selection.set_auto_select_row(on: true, model: model)

    selection = model.selection
    selection.clear
    selection.add(members.first)

    assert_equal(3, selection.count, 'Selecting one member should select the full row')
    expected = members.map { |instance| instance.persistent_id.to_i }.sort
    actual = selection.grep(Sketchup::ComponentInstance).map { |entity| entity.persistent_id.to_i }.sort
    assert_equal(expected, actual)
  end

  def test_auto_select_can_be_disabled
    model = Sketchup.active_model
    members = build_row(model, count: 2)

    AICabinets::Rows::Selection.set_auto_select_row(on: true, model: model)
    AICabinets::Rows::Selection.set_auto_select_row(on: false, model: model)

    selection = model.selection
    selection.clear
    selection.add(members.first)

    assert_equal(1, selection.count, 'Preference off should not expand selection')
  end

  def test_auto_select_ignores_multi_row_selection
    model = Sketchup.active_model
    row_a = build_row(model, count: 2)
    row_b = build_row(model, count: 2, offset_mm: 2000.0)

    AICabinets::Rows::Selection.set_auto_select_row(on: true, model: model)

    selection = model.selection
    selection.clear
    selection.add(row_a.first)
    selection.add(row_b.first)

    assert_equal(2, selection.count, 'Mixed row selection should remain unchanged')
  end

  private

  def manager_dialog
    AICabinets::UI::Rows::ManagerDialog
  end

  def build_row(model, count:, offset_mm: 0.0)
    instances = place_cabinets(model, count: count, offset_mm: offset_mm)
    select_instances(model, instances)
    row_id = AICabinets::Rows.create_from_selection(model: model)
    assert_kind_of(String, row_id)
    instances
  end

  class FakeProvider
    attr_reader :show_calls, :hide_calls, :last_geometry

    def initialize
      @show_calls = 0
      @hide_calls = 0
      @last_geometry = nil
    end

    def show(geometry)
      @show_calls += 1
      @last_geometry = geometry
    end

    def hide
      @hide_calls += 1
    end

    def valid?
      true
    end

    def invalid?
      false
    end
  end

  class NullProvider
    def show(_geometry); end

    def hide; end

    def valid?
      true
    end

    def invalid?
      false
    end
  end
end
