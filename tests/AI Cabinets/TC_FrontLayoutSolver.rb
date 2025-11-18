# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/solver/front_layout')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

class TC_FrontLayoutSolver < TestUp::TestCase
  def setup
    @defaults = AICabinets::Defaults.load_mm
  end

  def test_double_doors_basic
    params = deep_copy(@defaults)
    params[:face_frame][:layout] = [{ kind: 'double_doors' }]

    opening_mm = opening_from_params(params)

    result = AICabinets::Solver::FrontLayout.solve(opening_mm: opening_mm, params: params)
    layout = result[:front_layout]
    fronts = layout[:fronts]
    assert_equal(2, fronts.length, 'Expected two doors for double_doors preset')

    left, right = fronts.sort_by { |front| front[:bbox_mm][:x] }
    overlay_mm = layout[:meta][:overlay_mm]
    reveal_mm = layout[:meta][:reveal_mm]

    clear_width_left = left[:bbox_mm][:w] - overlay_mm
    clear_width_right = right[:bbox_mm][:w] - overlay_mm
    assert_in_delta(clear_width_left, clear_width_right, 1.0e-6, 'Doors should be equal width after rounding distribution')

    meeting_gap = right[:bbox_mm][:x] - (left[:bbox_mm][:x] + left[:bbox_mm][:w] - overlay_mm)
    assert_in_delta(reveal_mm, meeting_gap, 1.0e-6, 'Meeting gap should equal reveal')

    left_clear_left = left[:bbox_mm][:x] + overlay_mm
    right_clear_right = opening_mm[:w] - (right[:bbox_mm][:x] + right[:bbox_mm][:w] - overlay_mm)
    assert_in_delta(reveal_mm, left_clear_left, 1.0e-6, 'Left frame clearance should equal reveal')
    assert_in_delta(reveal_mm, right_clear_right, 1.0e-6, 'Right frame clearance should equal reveal')

    bottom_clearance = left[:bbox_mm][:z] + overlay_mm
    top_clearance = opening_mm[:h] - (left[:bbox_mm][:z] + left[:bbox_mm][:h] - overlay_mm)
    assert_in_delta(reveal_mm, bottom_clearance, 1.0e-6, 'Bottom clearance should equal reveal')
    assert_in_delta(reveal_mm, top_clearance, 1.0e-6, 'Top clearance should equal reveal')

    composed_width = clear_width_left + clear_width_right + (reveal_mm * 3.0)
    assert_in_delta(opening_mm[:w], composed_width, 1.0e-6, 'Door widths plus reveals should recompose opening width')
  end

  def test_drawer_stack_with_mid_rails
    params = deep_copy(@defaults)
    params[:face_frame][:layout] = [{ kind: 'drawer_stack', drawers: 3 }]
    params[:face_frame][:mid_rail_mm] = 25.0

    opening_mm = opening_from_params(params)

    result = AICabinets::Solver::FrontLayout.solve(opening_mm: opening_mm, params: params)
    layout = result[:front_layout]
    fronts = layout[:fronts]

    assert_equal(3, fronts.length, 'Expected three drawers')

    overlay_mm = layout[:meta][:overlay_mm]
    reveal_mm = layout[:meta][:reveal_mm]

    clears = fronts.map.with_index do |front, index|
      top_overlay = index == fronts.length - 1 ? overlay_mm : 0.0
      bottom_overlay = index.zero? ? overlay_mm : 0.0
      front[:bbox_mm][:h] - top_overlay - bottom_overlay
    end

    assert_in_delta(clears[0], clears[1], 1.0e-6, 'Drawer heights should be equal after rounding')
    assert_in_delta(clears[1], clears[2], 1.0e-6, 'Drawer heights should be equal after rounding')

    gap_one = fronts[1][:bbox_mm][:z] - (fronts[0][:bbox_mm][:z] + fronts[0][:bbox_mm][:h])
    gap_two = fronts[2][:bbox_mm][:z] - (fronts[1][:bbox_mm][:z] + fronts[1][:bbox_mm][:h])
    assert_in_delta(reveal_mm, gap_one, 1.0e-6, 'Inter-drawer gap should equal reveal')
    assert_in_delta(reveal_mm, gap_two, 1.0e-6, 'Inter-drawer gap should equal reveal')

    left_clear = fronts.first[:bbox_mm][:x] + overlay_mm
    right_clear = opening_mm[:w] - (fronts.first[:bbox_mm][:x] + fronts.first[:bbox_mm][:w] - overlay_mm)
    assert_in_delta(reveal_mm, left_clear, 1.0e-6, 'Left clearance should equal reveal')
    assert_in_delta(reveal_mm, right_clear, 1.0e-6, 'Right clearance should equal reveal')

    mid_rails = layout[:mid_members][:mid_rails]
    assert_equal(2, mid_rails.length, 'Expected mid rails for drawer gaps when mid_rail_mm > 0')

    expected_first = fronts[0][:bbox_mm][:z] + fronts[0][:bbox_mm][:h] + (reveal_mm / 2.0)
    expected_second = fronts[1][:bbox_mm][:z] + fronts[1][:bbox_mm][:h] + (reveal_mm / 2.0)
    assert_in_delta(expected_first, mid_rails[0][:z], 1.0e-6, 'First mid rail should sit at first gap center')
    assert_in_delta(expected_second, mid_rails[1][:z], 1.0e-6, 'Second mid rail should sit at second gap center')
  end

  def test_minimum_enforcement
    params = deep_copy(@defaults)
    params[:face_frame][:layout] = [{ kind: 'double_doors' }]

    opening_mm = { x: 0.0, z: 0.0, w: 380.0, h: 640.0 }

    result = AICabinets::Solver::FrontLayout.solve(opening_mm: opening_mm, params: params)

    assert_empty(result[:front_layout][:fronts], 'Expected no fronts when minimum width not met')
    refute_empty(result[:warnings], 'Expected warnings explaining constraint failure')
  end

  def test_persistence_idempotent
    params = deep_copy(@defaults)
    params[:face_frame][:layout] = [{ kind: 'drawer_stack', drawers: 2 }]

    first = AICabinets::Ops::InsertBaseCabinet.send(:validate_params!, deep_copy(params))
    second = AICabinets::Ops::InsertBaseCabinet.send(:validate_params!, deep_copy(params))

    assert_equal(first[:front_layout], second[:front_layout], 'front_layout should be stable across runs')
    assert_equal(first[:front_layout], AICabinets::Ops::InsertBaseCabinet.send(:validate_params!, deep_copy(first))[:front_layout])
  end

  private

  def opening_from_params(params)
    face_frame = params[:face_frame]
    {
      x: face_frame[:stile_left_mm],
      z: face_frame[:rail_bottom_mm],
      w: params[:width_mm] - face_frame[:stile_left_mm] - face_frame[:stile_right_mm],
      h: params[:height_mm] - face_frame[:rail_top_mm] - face_frame[:rail_bottom_mm]
    }
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
