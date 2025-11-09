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

  def test_degenerate_single_bay_matches_outer
    params = base_params.merge(
      width_mm: 500.0,
      height_mm: 640.0,
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        bays: [{}]
      }
    )

    result = AICabinets::Layout::Model.build(params)

    assert_equal(1, result[:bays].length)
    bay = result[:bays].first
    AICabinetsTestHelper.assert_within_tolerance(self, 500.0, bay[:w_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 640.0, bay[:h_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, bay[:x_mm], 1.0e-6)
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, bay[:y_mm], 1.0e-6)
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
    assert(result[:warnings].first.include?('Normalized bay widths'), 'Expected normalization warning')
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
