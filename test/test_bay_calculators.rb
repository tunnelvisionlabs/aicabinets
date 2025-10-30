# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/geometry/bay_openings'

class BayOpeningsTest < Minitest::Test
  def test_compute_returns_openings_with_reveals
    openings = AICabinets::Geometry::BayOpenings.compute(
      bay_ranges_mm: [[19.0, 219.0], [238.0, 438.0]],
      edge_reveal_mm: 2.0,
      top_reveal_mm: 3.0,
      bottom_reveal_mm: 4.0,
      toe_kick_height_mm: 0.0,
      toe_kick_depth_mm: 0.0,
      cabinet_height_mm: 720.0
    )

    assert_equal(2, openings.length)

    first = openings.first
    assert_in_delta(21.0, first.left_mm, 1.0e-6)
    assert_in_delta(217.0, first.right_mm, 1.0e-6)
    assert_in_delta(196.0, first.width_mm, 1.0e-6)
    assert_in_delta(4.0, first.bottom_mm, 1.0e-6)
    assert_in_delta(717.0, first.top_mm, 1.0e-6)
    assert_in_delta(713.0, first.height_mm, 1.0e-6)

    second = openings.last
    assert_in_delta(240.0, second.left_mm, 1.0e-6)
    assert_in_delta(436.0, second.right_mm, 1.0e-6)
    assert_in_delta(196.0, second.width_mm, 1.0e-6)
  end

  def test_compute_accounts_for_toe_kick
    openings = AICabinets::Geometry::BayOpenings.compute(
      bay_ranges_mm: [[19.0, 419.0]],
      edge_reveal_mm: 2.0,
      top_reveal_mm: 5.0,
      bottom_reveal_mm: 3.0,
      toe_kick_height_mm: 100.0,
      toe_kick_depth_mm: 80.0,
      cabinet_height_mm: 900.0
    )

    assert_equal(1, openings.length)
    opening = openings.first

    assert_in_delta(103.0, opening.bottom_mm, 1.0e-6)
    assert_in_delta(895.0, opening.top_mm, 1.0e-6)
    assert_in_delta(792.0, opening.height_mm, 1.0e-6)
  end

  def test_compute_returns_empty_array_for_missing_ranges
    openings = AICabinets::Geometry::BayOpenings.compute(
      bay_ranges_mm: [],
      edge_reveal_mm: 2.0,
      top_reveal_mm: 5.0,
      bottom_reveal_mm: 3.0,
      toe_kick_height_mm: 0.0,
      toe_kick_depth_mm: 0.0,
      cabinet_height_mm: 900.0
    )

    assert_empty(openings)
  end
end
