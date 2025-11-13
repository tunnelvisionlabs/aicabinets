# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/ops/insert_base_cabinet')
Sketchup.require('aicabinets/rows/selection')

class TC_Rows_Selection_AutoSelect < TestUp::TestCase
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
    AICabinetsTestHelper.clean_model!
    AICabinets::Rows::Selection.reset!
  end

  def teardown
    AICabinets::Rows::Selection.reset!
    AICabinetsTestHelper.clean_model!
  end

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

  def build_row(model, count:, offset_mm: 0.0)
    instances = []

    count.times do |index|
      origin_offset = offset_mm + index * (BASE_PARAMS_MM[:width_mm] + 5.0)
      point = Geom::Point3d.new(origin_offset.mm, 0, 0)
      instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
        model: model,
        point3d: point,
        params_mm: BASE_PARAMS_MM
      )
      instances << instance
    end

    select_instances(model, instances)
    row_id = AICabinets::Rows.create_from_selection(model: model)
    assert_kind_of(String, row_id)
    instances
  end

  def select_instances(model, entities)
    selection = model.selection
    selection.clear
    entities.each { |entity| selection.add(entity) }
  end
end
