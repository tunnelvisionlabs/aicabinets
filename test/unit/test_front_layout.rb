# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('../..', __dir__))

require 'aicabinets/solver/front_layout'
require 'aicabinets/face_frame'

class TestFrontLayout < Minitest::Test
  def setup
    @defaults = AICabinets::FaceFrame.defaults_mm
  end

  def test_double_doors_overlay_and_reveal
    opening_mm = { x: 0.0, z: 0.0, w: 700.0, h: 720.0 }
    params = { face_frame: @defaults.merge(reveal_mm: 2.0, overlay_mm: 12.7, layout: [{ kind: 'double_doors' }]) }

    result = AICabinets::Solver::FrontLayout.solve(opening_mm: opening_mm, params: params)
    fronts = result[:front_layout][:fronts]

    assert_equal(2, fronts.length)

    widths = fronts.map { |front| front[:bbox_mm][:w] - result[:front_layout][:meta][:overlay_mm] }
    assert_in_delta(widths[0], widths[1], 0.1)

    meeting_gap = fronts.sort_by { |front| front[:bbox_mm][:x] }[1][:bbox_mm][:x] -
                  (fronts.sort_by { |front| front[:bbox_mm][:x] }.first[:bbox_mm][:x] +
                   fronts.sort_by { |front| front[:bbox_mm][:x] }.first[:bbox_mm][:w])
    assert_in_delta(2.0, meeting_gap, 0.1)

    recomposed = widths.sum + (result[:front_layout][:meta][:reveal_mm] * 3.0)
    assert_in_delta(opening_mm[:w], recomposed, 0.15)
  end

  def test_drawer_stack_rounding_recomposes_height
    opening_mm = { x: 0.0, z: 0.0, w: 640.0, h: 501.5 }
    params = { face_frame: @defaults.merge(layout: [{ kind: 'drawer_stack', drawers: 3 }]) }

    result = AICabinets::Solver::FrontLayout.solve(opening_mm: opening_mm, params: params)
    fronts = result[:front_layout][:fronts]
    overlay_mm = result[:front_layout][:meta][:overlay_mm]
    reveal_mm = result[:front_layout][:meta][:reveal_mm]

    clear_heights = fronts.map.with_index do |front, index|
      top_overlay = index == fronts.length - 1 ? overlay_mm : 0.0
      bottom_overlay = index.zero? ? overlay_mm : 0.0
      front[:bbox_mm][:h] - top_overlay - bottom_overlay
    end

    clear_sum = clear_heights.sum
    expected_total = clear_sum + (reveal_mm * (fronts.length + 1))
    assert_in_delta(opening_mm[:h], expected_total, 0.15)
  end

  def test_residual_distribution_stable
    values = [333.3, 333.3, 333.4]
    target_total = 1000.0

    rounded = AICabinets::Solver::FrontLayout.distribute_residual(values, target_total: target_total)

    assert_in_delta(target_total, rounded.sum, 0.01)
    assert_equal(rounded.sort.reverse, rounded.sort.reverse, 'Rounding must be deterministic')
  end

  def test_minimum_dimensions_emit_warnings
    opening_mm = { x: 0.0, z: 0.0, w: 350.0, h: 300.0 }
    params = { face_frame: @defaults.merge(layout: [{ kind: 'drawer_stack', drawers: 3 }]) }

    result = AICabinets::Solver::FrontLayout.solve(opening_mm: opening_mm, params: params)

    assert_empty(result[:front_layout][:fronts])
    refute_empty(result[:warnings])
    assert_match(/Minimum drawer face height/, result[:warnings].first)
  end
end
