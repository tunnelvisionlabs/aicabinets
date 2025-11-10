# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/ui/rows')
Sketchup.require('aicabinets/ui/rows/manager_dialog')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

class TC_Rows_Commands < TestUp::TestCase
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

  def test_registers_rows_commands
    AICabinets::UI.commands.clear
    AICabinets::UI.register_commands!

    assert_includes(AICabinets::UI.commands.keys, :rows_manage)
    assert_includes(AICabinets::UI.commands.keys, :rows_add_selection)
    assert_includes(AICabinets::UI.commands.keys, :rows_remove_selection)
    assert_includes(AICabinets::UI.commands.keys, :rows_toggle_highlight)
  end

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

  private

  def manager_dialog
    AICabinets::UI::Rows::ManagerDialog
  end

  def place_cabinets(model, count: 1)
    instances = []
    count.times do |index|
      offset_mm = index * (BASE_PARAMS_MM[:width_mm] + 5.0)
      point = Geom::Point3d.new(offset_mm.mm, 0, 0)
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
