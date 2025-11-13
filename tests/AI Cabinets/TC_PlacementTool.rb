# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/ui/tools/insert_base_cabinet_tool')

class TC_PlacementTool < TestUp::TestCase
  BASE_PARAMS_MM = {
    width_mm: 900.0,
    depth_mm: 600.0,
    height_mm: 720.0,
    panel_thickness_mm: 18.0,
    toe_kick_height_mm: 100.0,
    toe_kick_depth_mm: 75.0,
    toe_kick_thickness_mm: 18.0,
    partition_mode: 'none',
    front: 'empty',
    shelves: 2,
    partitions: { mode: 'none', count: 0, positions_mm: [] }
  }.freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_preview_bounds_reflect_dimensions
    bounds = AICabinets::UI::Tools::InsertBaseCabinetTool.preview_bounds_mm(BASE_PARAMS_MM)

    assert_equal([0.0, 0.0, 0.0], bounds[:min], 'Expected FLB anchor at origin')
    assert_in_delta(BASE_PARAMS_MM[:width_mm], bounds[:max][0], 1e-6, 'Width should match params')
    assert_in_delta(BASE_PARAMS_MM[:depth_mm], bounds[:max][1], 1e-6, 'Depth should match params')
    assert_in_delta(BASE_PARAMS_MM[:height_mm], bounds[:max][2], 1e-6, 'Height should match params')
  end

  def test_cancel_notifies_callback
    cancel_count = 0
    tool = build_tool(callbacks: { cancel: -> { cancel_count += 1 } })

    tool.define_singleton_method(:exit_tool) { |_options = {}| @exit_called = true }

    tool.onCancel(0, nil)

    assert_equal(1, cancel_count, 'Expected cancel callback to fire once')
    assert(tool.instance_variable_get(:@exit_called), 'Exit should be invoked during cancel')
    assert(tool.send(:finish?), 'Tool should mark placement session as finished')
  end

  def test_cancel_from_ui_triggers_callback_once
    cancel_count = 0
    tool = build_tool(callbacks: { cancel: -> { cancel_count += 1 } })

    tool.define_singleton_method(:exit_tool) { |_options = {}| @exit_called = true }

    tool.cancel_from_ui

    assert_equal(1, cancel_count, 'Cancel callback should fire exactly once when invoked from UI')
    assert(tool.instance_variable_get(:@exit_called), 'Exit should be invoked when cancelling from UI')
    assert(tool.send(:finish?), 'Tool should mark placement session as finished after cancel_from_ui')
  end

  def test_escape_key_triggers_cancel
    cancel_count = 0
    tool = build_tool(callbacks: { cancel: -> { cancel_count += 1 } })

    tool.define_singleton_method(:exit_tool) { |_options = {}| @exit_called = true }

    tool.onKeyDown(27, 0, 0, nil)

    assert_equal(1, cancel_count, 'Cancel callback should fire when escape key is pressed')
    assert(tool.instance_variable_get(:@exit_called), 'Escape key should exit the tool')
    assert(tool.send(:finish?), 'Tool should mark placement session as finished after escape key cancel')
  end

  def test_double_click_guard_prevents_duplicate_insert
    placements = []
    created_instances = []

    placer = lambda do |model:, **_|
      instance = model.entities.add_group.to_component
      placements << instance
      created_instances << instance
      instance
    end

    tool = build_tool(callbacks: {}, placer: placer)
    stub_input_point(tool)
    tool.define_singleton_method(:exit_tool) { |_options = {}| nil }

    tool.onLButtonDown(0, 0, 0, nil)
    tool.onLButtonDown(0, 0, 0, nil)

    assert_equal(1, placements.length, 'Placement should occur only once despite repeated clicks')
  ensure
    created_instances.each do |instance|
      instance.erase! if instance.valid?
    end
  end

  private

  def build_tool(callbacks:, placer: nil)
    AICabinets::UI::Tools::InsertBaseCabinetTool.new(
      BASE_PARAMS_MM,
      callbacks: callbacks,
      placer: placer
    )
  end

  def stub_input_point(tool)
    point = Geom::Point3d.new(0, 0, 0)
    input_point = Object.new
    input_point.define_singleton_method(:pick) { |_view, _x, _y| self }
    input_point.define_singleton_method(:valid?) { true }
    input_point.define_singleton_method(:position) { point }

    tool.instance_variable_set(:@input_point, input_point)
    tool.define_singleton_method(:pick_point) { |_view, _x, _y| input_point }
  end
end
