# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('support', __dir__))
require 'sketchup'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/generator/shelves'
require 'aicabinets/generator/fronts'

class GeneratorPerBayTest < Minitest::Test
  class FakeBay
    attr_reader :index, :start_mm, :end_mm, :shelf_count, :door_mode

    def initialize(index:, start_mm:, end_mm:, shelf_count: 0, door_mode: :none, leaf: true)
      @index = index
      @start_mm = start_mm
      @end_mm = end_mm
      @shelf_count = shelf_count
      @door_mode = door_mode
      @leaf = leaf
    end

    def width_mm
      @end_mm - @start_mm
    end

    def leaf?
      @leaf
    end
  end

  class FakeParams
    attr_reader :partition_bays, :shelf_thickness_mm, :interior_clear_height_mm,
                :interior_depth_mm, :interior_bottom_z_mm, :interior_top_z_mm,
                :door_edge_reveal_mm,
                :door_top_reveal_mm, :door_bottom_reveal_mm, :door_center_reveal_mm,
                :door_thickness_mm, :height_mm, :toe_kick_height_mm,
                :toe_kick_depth_mm, :width_mm, :panel_thickness_mm

    attr_accessor :front_mode

    def initialize(partition_bays:, shelf_thickness_mm: 18.0, interior_clear_height_mm: 0.0,
                   interior_depth_mm: 0.0, interior_bottom_z_mm: 0.0,
                   door_edge_reveal_mm: 0.0, door_top_reveal_mm: 0.0,
                   door_bottom_reveal_mm: 0.0, door_center_reveal_mm: 0.0,
                   door_thickness_mm: 19.0, height_mm: 0.0,
                   toe_kick_height_mm: 0.0, toe_kick_depth_mm: 0.0,
                   width_mm: 0.0, front_mode: :empty,
                   panel_thickness_mm: 0.0)
      @partition_bays = partition_bays
      @shelf_thickness_mm = shelf_thickness_mm
      @interior_clear_height_mm = interior_clear_height_mm
      @interior_depth_mm = interior_depth_mm
      @interior_bottom_z_mm = interior_bottom_z_mm
      @interior_top_z_mm = interior_bottom_z_mm + interior_clear_height_mm
      @door_edge_reveal_mm = door_edge_reveal_mm
      @door_top_reveal_mm = door_top_reveal_mm
      @door_bottom_reveal_mm = door_bottom_reveal_mm
      @door_center_reveal_mm = door_center_reveal_mm
      @door_thickness_mm = door_thickness_mm
      @height_mm = height_mm
      @toe_kick_height_mm = toe_kick_height_mm
      @toe_kick_depth_mm = toe_kick_depth_mm
      @width_mm = width_mm
      @front_mode = front_mode
      @panel_thickness_mm = panel_thickness_mm
    end
  end

  def test_shelves_plan_layout_respects_per_bay_counts
    bays = [
      FakeBay.new(index: 0, start_mm: 18.0, end_mm: 218.0, shelf_count: 0, leaf: true),
      FakeBay.new(index: 1, start_mm: 218.0, end_mm: 418.0, shelf_count: 2, leaf: true),
      FakeBay.new(index: 2, start_mm: 418.0, end_mm: 618.0, shelf_count: 1, leaf: true)
    ]

    params = FakeParams.new(
      partition_bays: bays,
      shelf_thickness_mm: 18.0,
      interior_clear_height_mm: 600.0,
      interior_depth_mm: 550.0,
      interior_bottom_z_mm: 100.0
    )

    layout = AICabinets::Generator::Shelves.plan_layout(params)
    refute_nil(layout)
    placements = layout.placements
    assert_equal(3, placements.length)

    counts = placements.group_by(&:bay_index).transform_values(&:length)
    assert_equal({ 1 => 2, 2 => 1 }, counts)

    bay2_tops = placements.select { |placement| placement.bay_index == 1 }.map(&:top_z_mm).sort
    assert_in_delta(306.0, bay2_tops[0], 1.0e-6)
    assert_in_delta(512.0, bay2_tops[1], 1.0e-6)

    bay3 = placements.find { |placement| placement.bay_index == 2 }
    refute_nil(bay3)
    assert_in_delta(409.0, bay3.top_z_mm, 1.0e-6)
    assert_in_delta(418.0, bay3.x_start_mm, 1.0e-6)
  end

  def test_fronts_plan_layout_respects_per_bay_modes
    bays = [
      FakeBay.new(index: 0, start_mm: 18.0, end_mm: 218.0, door_mode: :none, leaf: true),
      FakeBay.new(index: 1, start_mm: 236.0, end_mm: 468.0, door_mode: :left, leaf: true),
      FakeBay.new(index: 2, start_mm: 486.0, end_mm: 782.0, door_mode: :double, leaf: true)
    ]

    params = FakeParams.new(
      partition_bays: bays,
      door_edge_reveal_mm: 2.0,
      door_top_reveal_mm: 2.0,
      door_bottom_reveal_mm: 2.0,
      door_center_reveal_mm: 4.0,
      door_thickness_mm: 19.0,
      height_mm: 720.0,
      toe_kick_height_mm: 100.0,
      toe_kick_depth_mm: 50.0,
      width_mm: 800.0,
      front_mode: :empty,
      panel_thickness_mm: 18.0
    )

    placements = AICabinets::Generator::Fronts.plan_layout(params)
    assert_equal(3, placements.length)

    single = placements.find { |placement| placement.bay_index == 1 }
    refute_nil(single)
    assert_in_delta(228.0, single.width_mm, 1.0e-6)
    assert_in_delta(238.0, single.x_start_mm, 1.0e-6)
    assert_in_delta(616.0, single.height_mm, 1.0e-6)
    assert_in_delta(102.0, single.bottom_z_mm, 1.0e-6)

    double = placements.select { |placement| placement.bay_index == 2 }
    assert_equal(2, double.length)
    double.sort_by!(&:x_start_mm)
    assert_in_delta(153.0, double[0].width_mm, 1.0e-6)
    assert_in_delta(153.0, double[1].width_mm, 1.0e-6)
    gap = double[1].x_start_mm - (double[0].x_start_mm + double[0].width_mm)
    assert_in_delta(4.0, gap, 1.0e-6)
  end
end
