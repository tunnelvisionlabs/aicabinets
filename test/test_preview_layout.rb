# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/preview/layout'

class PreviewLayoutTest < Minitest::Test
  Layout = AICabinets::Preview::Layout

  def test_vertical_orientation_creates_vertical_divisions
    config = build_config(
      partition_mode: 'vertical',
      orientation: 'vertical',
      count: 2,
      bays: Array.new(3) { bay_template(sub_orientation: 'horizontal') }
    )

    plan = Layout.plan(config, selected_path: [1])
    lines = Layout.collect_lines(plan.container_plan)

    assert_equal(2, lines.length)
    assert(lines.all? { |line| line.orientation == :vertical })

    positions = lines.map(&:position)
    assert_in_delta(200.0, positions.first, 1e-6)
    assert_in_delta(400.0, positions.last, 1e-6)

    highlight = plan.highlight_rect
    assert_in_delta(200.0, highlight.left, 1e-6)
    assert_in_delta(400.0, highlight.right, 1e-6)
    assert_in_delta(0.0, highlight.bottom, 1e-6)
    assert_in_delta(720.0, highlight.top, 1e-6)
  end

  def test_horizontal_orientation_creates_horizontal_divisions
    config = build_config(
      partition_mode: 'horizontal',
      orientation: 'horizontal',
      count: 1,
      bays: Array.new(2) { bay_template(sub_orientation: 'vertical') }
    )

    plan = Layout.plan(config, selected_path: [0])
    lines = Layout.collect_lines(plan.container_plan)

    assert_equal(1, lines.length)
    assert_equal(:horizontal, lines.first.orientation)
    assert_in_delta(360.0, lines.first.position, 1e-6)

    highlight = plan.highlight_rect
    assert_in_delta(0.0, highlight.bottom, 1e-6)
    assert_in_delta(360.0, highlight.top, 1e-6)
  end

  def test_nested_subpartitions_follow_perpendicular_orientation
    bays = [
      bay_template(sub_orientation: 'horizontal', sub_count: 1),
      bay_template(sub_orientation: 'horizontal')
    ]
    config = build_config(
      partition_mode: 'vertical',
      orientation: 'vertical',
      count: 1,
      bays: bays
    )

    plan = Layout.plan(config, selected_path: [0, 1])
    lines = Layout.collect_lines(plan.container_plan)

    horizontal = lines.select { |line| line.orientation == :horizontal }
    refute_empty(horizontal)

    nested_line = horizontal.first
    assert_in_delta(360.0, nested_line.position, 1e-6)
    assert_in_delta(0.0, nested_line.range_start, 1e-6)
    assert_in_delta(300.0, nested_line.range_end, 1e-6)

    highlight = plan.highlight_rect
    assert_in_delta(0.0, highlight.left, 1e-6)
    assert_in_delta(300.0, highlight.right, 1e-6)
    assert_in_delta(360.0, highlight.bottom, 1e-6)
    assert_in_delta(720.0, highlight.top, 1e-6)
  end

  def test_partition_mode_none_produces_single_bay
    config = build_config(
      partition_mode: 'none',
      orientation: 'vertical',
      count: 0,
      bays: []
    )

    plan = Layout.plan(config, selected_path: [])
    lines = Layout.collect_lines(plan.container_plan)

    assert_empty(lines)

    highlight = plan.highlight_rect
    assert_in_delta(0.0, highlight.left, 1e-6)
    assert_in_delta(600.0, highlight.right, 1e-6)
    assert_in_delta(0.0, highlight.bottom, 1e-6)
    assert_in_delta(720.0, highlight.top, 1e-6)
  end

  private

  def build_config(partition_mode:, orientation:, count:, bays:)
    {
      width_mm: 600.0,
      height_mm: 720.0,
      partition_mode: partition_mode,
      partitions: {
        orientation: orientation,
        count: count,
        positions_mm: [],
        bays: bays
      }
    }
  end

  def bay_template(sub_orientation:, sub_count: 0)
    {
      mode: 'fronts_shelves',
      fronts_shelves_state: { shelf_count: 0, door_mode: nil },
      shelf_count: 0,
      door_mode: nil,
      subpartitions_state: { count: sub_count },
      subpartitions: {
        count: sub_count,
        orientation: sub_orientation,
        bays: build_nested_bays(sub_orientation, sub_count)
      }
    }
  end

  def build_nested_bays(sub_orientation, sub_count)
    return [] unless sub_count.positive?

    Array.new(sub_count + 1) do
      {
        mode: 'fronts_shelves',
        fronts_shelves_state: { shelf_count: 0, door_mode: nil },
        shelf_count: 0,
        door_mode: nil,
        subpartitions_state: { count: 0 },
        subpartitions: { count: 0, orientation: sub_orientation, bays: [] }
      }
    end
  end
end
