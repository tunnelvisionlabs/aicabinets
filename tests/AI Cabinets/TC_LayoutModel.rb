# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/layout/model')

class TC_LayoutModel < TestUp::TestCase
  def test_even_three_bays_equal_width
    params = base_params.merge(
      width_mm: 762.0,
      height_mm: 762.0,
      partitions: {
        mode: 'even',
        count: 2,
        orientation: 'vertical',
        bays: Array.new(3) { {} }
      }
    )

    result = AICabinets::Layout::Model.build(params)

    assert_equal(3, result[:bays].length)
    assert_equal({ w_mm: 762.0, h_mm: 762.0 }, result[:outer])

    widths = result[:bays].map { |bay| bay[:w_mm] }
    AICabinetsTestHelper.assert_within_tolerance(self, 254.0, widths[0], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 254.0, widths[1], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 254.0, widths[2], 1.0e-6)

    x_values = result[:bays].map { |bay| bay[:x_mm] }
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, x_values[0], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 254.0, x_values[1], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 508.0, x_values[2], 1.0e-6)

    sum_width = widths.sum
    AICabinetsTestHelper.assert_within_tolerance(
      self,
      result[:outer][:w_mm],
      sum_width,
      AICabinets::Layout::Model::EPS_MM
    )
  end

  def test_positions_mixed_widths
    params = base_params.merge(
      width_mm: 762.0,
      height_mm: 700.0,
      partitions: {
        mode: 'positions',
        positions_mm: [300.0, 500.0],
        count: 2,
        orientation: 'vertical',
        bays: Array.new(3) { {} }
      }
    )

    result = AICabinets::Layout::Model.build(params)

    widths = result[:bays].map { |bay| bay[:w_mm] }
    AICabinetsTestHelper.assert_within_tolerance(self, 300.0, widths[0], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 200.0, widths[1], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 262.0, widths[2], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(
      self,
      result[:outer][:w_mm],
      widths.sum,
      AICabinets::Layout::Model::EPS_MM
    )

    heights = result[:bays].map { |bay| bay[:h_mm] }
    heights.each do |height|
      AICabinetsTestHelper.assert_within_tolerance(self, 700.0, height, 1.0e-6)
    end

    partitions = result[:partitions]
    refute_nil(partitions, 'Expected partitions data to be present.')
    assert_equal('vertical', partitions[:orientation])
    assert_equal([300.0, 500.0], partitions[:positions_mm])
  end

  def test_horizontal_partitions_respect_positions
    params = base_params.merge(
      width_mm: 762.0,
      height_mm: 900.0,
      partitions: {
        mode: 'positions',
        positions_mm: [200.0, 500.0],
        count: 2,
        orientation: 'horizontal',
        bays: Array.new(3) { {} }
      }
    )

    result = AICabinets::Layout::Model.build(params)

    partitions = result[:partitions]
    refute_nil(partitions, 'Expected partitions data to be present.')
    assert_equal('horizontal', partitions[:orientation])
    assert_equal([200.0, 500.0], partitions[:positions_mm])
  end

  def test_horizontal_partitions_build_rows
    params = base_params.merge(
      width_mm: 900.0,
      height_mm: 900.0,
      partitions: {
        mode: 'positions',
        positions_mm: [300.0, 650.0],
        count: 2,
        orientation: 'horizontal',
        bays: Array.new(3) { {} }
      }
    )

    result = AICabinets::Layout::Model.build(params)

    bays = result[:bays]
    assert_equal(3, bays.length, 'Expected three horizontal bays.')

    heights = bays.map { |bay| bay[:h_mm] }
    expected = [300.0, 350.0, 250.0]
    heights.each_with_index do |height, index|
      AICabinetsTestHelper.assert_within_tolerance(self, expected[index], height, 1.0e-6)
    end

    widths = bays.map { |bay| bay[:w_mm] }
    widths.each do |width|
      AICabinetsTestHelper.assert_within_tolerance(self, 900.0, width, 1.0e-6)
    end

    y_positions = bays.map { |bay| bay[:y_mm] }
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, y_positions[0], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 300.0, y_positions[1], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 650.0, y_positions[2], 1.0e-6)
  end

  def test_shelves_and_front_styles_are_reported
    params = base_params.merge(
      width_mm: 800.0,
      height_mm: 720.0,
      partitions: {
        mode: 'even',
        count: 1,
        orientation: 'vertical',
        bays: [
          {
            shelf_count: 2,
            fronts_shelves_state: { shelf_count: 2, door_mode: 'doors_left' },
            door_mode: 'doors_left'
          },
          {
            shelves: [{ y_mm: 200.0 }, { y_mm: 500.0 }],
            fronts_shelves_state: { shelf_count: 0, door_mode: 'doors_double' },
            door_mode: 'doors_double'
          }
        ]
      }
    )

    result = AICabinets::Layout::Model.build(params)

    shelves = result[:shelves]
    assert_equal(4, shelves.length, 'Expected shelves to include two per bay (two explicit).')
    bay_ids = result[:bays].map { |bay| bay[:id] }
    first_bay_id = bay_ids[0]
    second_bay_id = bay_ids[1]

    first_bay_shelves = shelves.select { |entry| entry[:bay_id] == first_bay_id }
    assert_equal(2, first_bay_shelves.length)
    expected_y = [240.0, 480.0]
    first_bay_shelves.each_with_index do |entry, index|
      AICabinetsTestHelper.assert_within_tolerance(self, expected_y[index], entry[:y_mm], 1.0e-6)
    end

    second_bay_shelves = shelves.select { |entry| entry[:bay_id] == second_bay_id }
    assert_equal([200.0, 500.0], second_bay_shelves.map { |entry| entry[:y_mm] })

    fronts = result[:fronts]
    assert_equal(2, fronts.length, 'Expected door fronts to be emitted for door bays.')
    assert_equal('doors_left', fronts.first[:style])
    assert_equal('doors_double', fronts.last[:style])
  end

  def test_global_front_style_used_when_no_partitions
    params = base_params.merge(
      width_mm: 840.0,
      height_mm: 720.0,
      fronts_shelves_state: { door_mode: 'doors_right' },
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        bays: []
      }
    )

    result = AICabinets::Layout::Model.build(params)

    assert_empty(result[:bays], 'Expected no bay rectangles when none are defined.')

    fronts = result[:fronts]
    assert_equal(1, fronts.length, 'Expected global door front to be emitted.')
    front = fronts.first
    assert_equal('doors_right', front[:style])
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, front[:x_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, front[:y_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 840.0, front[:w_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 720.0, front[:h_mm], 1.0e-6)
  end

  def test_global_front_style_uses_front_field_when_no_partitions
    params = base_params.merge(
      width_mm: 860.0,
      height_mm: 720.0,
      front: 'doors_left',
      shelves: '3',
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        bays: []
      }
    )

    result = AICabinets::Layout::Model.build(params)

    assert_empty(result[:bays], 'Expected cabinet to render as a single opening when partitions are none.')

    fronts = result[:fronts]
    assert_equal(1, fronts.length, 'Expected cabinet-level door front to be emitted from the front field.')
    front = fronts.first
    assert_equal('doors_left', front[:style])
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, front[:x_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, front[:y_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 860.0, front[:w_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 720.0, front[:h_mm], 1.0e-6)

    shelves = result[:shelves]
    assert_equal(3, shelves.length, 'Expected shelves to respect the global shelves field when partitions are none.')
    assert_equal(['cabinet'], shelves.map { |entry| entry[:bay_id] }.uniq)
    expected_positions = [180.0, 360.0, 540.0]
    assert_equal(expected_positions, shelves.map { |entry| entry[:y_mm] })
  end

  def test_global_front_style_ignores_empty_front_value
    params = base_params.merge(
      width_mm: 860.0,
      height_mm: 720.0,
      front: 'empty',
      shelves: 0,
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        bays: []
      }
    )

    result = AICabinets::Layout::Model.build(params)

    assert_empty(result[:fronts], 'Expected no door fronts when the front field requests an empty layout.')
    assert_empty(result[:shelves], 'Expected shelves to remain empty when no global count is provided.')
  end

  def test_degenerate_zero_bays
    params = base_params.merge(
      width_mm: 600.0,
      height_mm: 700.0,
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        bays: []
      }
    )

    result = AICabinets::Layout::Model.build(params)

    assert_equal([], result[:bays])
    assert_equal({ w_mm: 600.0, h_mm: 700.0 }, result[:outer])
  end

  def test_ignores_bay_specs_when_partition_mode_none
    params = base_params.merge(
      width_mm: 860.0,
      height_mm: 720.0,
      fronts_shelves_state: { door_mode: 'doors_double', shelf_count: 2 },
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        bays: [
          {
            id: 'legacy-bay',
            door_mode: 'doors_left',
            shelves: [{ y_mm: 200.0 }],
            fronts_shelves_state: { shelf_count: 3, door_mode: 'doors_left' }
          }
        ]
      }
    )

    result = AICabinets::Layout::Model.build(params)

    assert_empty(result[:bays], 'Expected bay specs to be ignored when partition mode is none.')

    fronts = result[:fronts]
    assert_equal(1, fronts.length, 'Expected a single global door front to render.')
    front = fronts.first
    assert_equal('doors_double', front[:style])
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, front[:x_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, front[:y_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 860.0, front[:w_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 720.0, front[:h_mm], 1.0e-6)

    shelves = result[:shelves]
    assert_equal(2, shelves.length, 'Expected global shelves to reflect the top-level shelf count.')
    bay_ids = shelves.map { |entry| entry[:bay_id] }.uniq
    assert_equal(['cabinet'], bay_ids)
    expected_positions = [240.0, 480.0]
    assert_equal(expected_positions, shelves.map { |entry| entry[:y_mm] })
  end

  def test_global_front_style_prefers_top_level_fields
    params = base_params.merge(
      width_mm: 900.0,
      height_mm: 720.0,
      front_layout: 'doors_right',
      shelf_count: 1,
      fronts_shelves_state: { door_mode: 'doors_double', shelf_count: 3 },
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        bays: []
      }
    )

    result = AICabinets::Layout::Model.build(params)

    fronts = result[:fronts]
    assert_equal(1, fronts.length, 'Expected a single cabinet-wide front when partitions are disabled.')
    assert_equal('doors_right', fronts.first[:style], 'Expected top-level front layout to override legacy nested state.')

    shelves = result[:shelves]
    assert_equal(1, shelves.length, 'Expected top-level shelf count to override nested shelf count when partitions are none.')
    assert_equal(['cabinet'], shelves.map { |entry| entry[:bay_id] }.uniq)
  end

  def test_partition_mode_prefers_top_level_none
    params = base_params.merge(
      width_mm: 840.0,
      height_mm: 700.0,
      partition_mode: 'none',
      fronts_shelves_state: { door_mode: 'doors_right', shelf_count: 3 },
      partitions: {
        mode: 'even',
        count: 1,
        orientation: 'vertical',
        bays: [
          {
            id: 'legacy-bay',
            door_mode: 'doors_left',
            shelf_count: 1,
            shelves: [{ y_mm: 233.0 }]
          }
        ]
      }
    )

    result = AICabinets::Layout::Model.build(params)

    assert_empty(result[:bays], 'Expected legacy bay specs to be ignored when partition_mode is none.')

    shelves = result[:shelves]
    assert_equal(3, shelves.length, 'Expected shelves to derive from the global shelf count.')
    assert_equal(['cabinet'], shelves.map { |entry| entry[:bay_id] }.uniq)

    fronts = result[:fronts]
    assert_equal(1, fronts.length, 'Expected cabinet-level door front to be emitted.')
    front = fronts.first
    assert_equal('doors_right', front[:style])
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, front[:x_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, front[:y_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 840.0, front[:w_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 700.0, front[:h_mm], 1.0e-6)
  end

  def test_normalizes_when_width_sum_deviates
    params = base_params.merge(
      width_mm: 900.0,
      height_mm: 700.0,
      partitions: {
        mode: 'even',
        count: 2,
        orientation: 'vertical',
        bays: [
          { layout: { width_mm: 250.0 } },
          { layout: { width_mm: 250.0 } },
          { layout: { width_mm: 250.0 } }
        ]
      }
    )

    result = AICabinets::Layout::Model.build(params)

    widths = result[:bays].map { |bay| bay[:w_mm] }
    AICabinetsTestHelper.assert_within_tolerance(
      self,
      900.0,
      widths.sum,
      AICabinets::Layout::Model::EPS_MM
    )
    refute_empty(result[:warnings])
    warning = result[:warnings].first
    assert(warning.include?('Normalized bay'), 'Expected normalization warning')
  end

  private

  def base_params
    {
      width_mm: 0.0,
      height_mm: 0.0,
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        bays: []
      }
    }
  end
end
