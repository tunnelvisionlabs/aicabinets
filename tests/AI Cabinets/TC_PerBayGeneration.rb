# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

require 'aicabinets/defaults'
require 'aicabinets/params_sanitizer'

Sketchup.require('aicabinets/generator/carcass')
Sketchup.require('aicabinets/ops/insert_base_cabinet')
Sketchup.require('aicabinets/ops/edit_base_cabinet')

class TC_PerBayGeneration < TestUp::TestCase
  BASE_PARAMS_MM = {
    width_mm: 900.0,
    depth_mm: 600.0,
    height_mm: 720.0,
    panel_thickness_mm: 19.0,
    toe_kick_height_mm: 0.0,
    toe_kick_depth_mm: 0.0,
    toe_kick_thickness_mm: 19.0,
    back_thickness_mm: 6.0,
    top_thickness_mm: 19.0,
    bottom_thickness_mm: 19.0,
    door_reveal_mm: 2.0,
    door_gap_mm: 2.0,
    top_reveal_mm: 3.0,
    bottom_reveal_mm: 4.0,
    front: 'empty',
    shelves: 0,
    partitions: {
      mode: 'none',
      count: 0,
      bays: [{ shelf_count: 0, door_mode: 'none' }]
    }
  }.freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_per_bay_shelves_and_fronts
    params_mm = sanitized_params(
      partitions: {
        mode: 'even',
        count: 2,
        bays: [
          { shelf_count: 2, door_mode: 'doors_left' },
          { shelf_count: 1, door_mode: 'doors_double' },
          { shelf_count: 0, door_mode: 'none' }
        ]
      }
    )

    definition, = build_carcass_definition(params_mm)

    ranges_mm = bay_ranges_for(params_mm)

    shelf_instances = collect_tagged_instances(definition, 'AICabinets/Shelves')
    assert_equal(3, shelf_instances.length, 'Expected per-bay shelf instances')
    shelf_counts = count_instances_by_bay(shelf_instances, ranges_mm)
    assert_equal([2, 1, 0], shelf_counts, 'Shelf counts per bay did not match params')

    front_instances = collect_tagged_instances(definition, 'AICabinets/Fronts')
    assert_equal(3, front_instances.length, 'Expected per-bay front instances')
    front_counts = count_instances_by_bay(front_instances, ranges_mm)
    assert_equal([1, 2, 0], front_counts, 'Front counts per bay did not match params')

    double_leaf_widths = widths_for_bay(front_instances, ranges_mm[1])
    clear_width_mm = bay_clear_width_mm(ranges_mm[1], params_mm)
    expected_width_mm = clear_width_mm - center_gap_mm(params_mm)

    assert_in_delta(
      expected_width_mm,
      double_leaf_widths.sum,
      tolerance_mm,
      'Double doors should leave the configured center gap'
    )
  end

  def test_edit_updates_target_bay_fronts_and_supports_undo
    params_mm = sanitized_params(
      partitions: {
        mode: 'even',
        count: 2,
        bays: [
          { shelf_count: 2, door_mode: 'doors_left' },
          { shelf_count: 1, door_mode: 'doors_double' },
          { shelf_count: 0, door_mode: 'none' }
        ]
      }
    )

    model = Sketchup.active_model
    instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: params_mm
    )

    ranges_mm = bay_ranges_for(params_mm)

    fronts_before = collect_tagged_instances(instance.definition, 'AICabinets/Fronts')
    counts_before = count_instances_by_bay(fronts_before, ranges_mm)
    assert_equal([1, 2, 0], counts_before)

    updated_params = sanitized_params(
      partitions: {
        mode: 'even',
        count: 2,
        bays: [
          { shelf_count: 2, door_mode: 'doors_left' },
          { shelf_count: 1, door_mode: 'none' },
          { shelf_count: 0, door_mode: 'none' }
        ]
      }
    )

    result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated_params,
      scope: 'instance'
    )
    assert(result[:ok], "Edit operation failed: #{result[:error]}")

    fronts_after = collect_tagged_instances(instance.definition, 'AICabinets/Fronts')
    counts_after = count_instances_by_bay(fronts_after, ranges_mm)
    assert_equal([1, 0, 0], counts_after, 'Only the second bay fronts should be removed')

    Sketchup.undo

    fronts_undo = collect_tagged_instances(instance.definition, 'AICabinets/Fronts')
    counts_undo = count_instances_by_bay(fronts_undo, ranges_mm)
    assert_equal([1, 2, 0], counts_undo, 'Undo should restore prior front configuration')
  end

  private

  def sanitized_params(overrides = {})
    params = Marshal.load(Marshal.dump(BASE_PARAMS_MM))

    overrides.each do |key, value|
      if key == :partitions
        params[:partitions] = Marshal.load(Marshal.dump(value))
      else
        params[key] = value
      end
    end

    defaults = AICabinets::Defaults.load_effective_mm
    AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: defaults)
    params
  end

  def build_carcass_definition(params_mm)
    model = Sketchup.active_model
    definition = model.definitions.add(next_definition_name)
    result = AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params_mm)
    [definition, result]
  end

  def collect_tagged_instances(definition, tag_name)
    definition.entities.grep(Sketchup::ComponentInstance).select do |instance|
      layer = instance.layer if instance.respond_to?(:layer)
      layer && layer.respond_to?(:name) && layer.name == tag_name
    end
  end

  def count_instances_by_bay(instances, ranges_mm)
    counts = Array.new(ranges_mm.length, 0)
    instances.each do |instance|
      bay_index = bay_index_for(instance, ranges_mm)
      counts[bay_index] += 1 if bay_index
    end
    counts
  end

  def widths_for_bay(instances, range_mm)
    instances.each_with_object([]) do |instance, memo|
      next unless within_range?(instance, range_mm)

      bbox = instance.definition.bounds
      width_mm = AICabinetsTestHelper.mm_from_length(bbox.max.x - bbox.min.x)
      memo << width_mm
    end
  end

  def bay_clear_width_mm(range_mm, params_mm)
    edge_reveal = edge_reveal_mm(params_mm)
    left = range_mm[0] + edge_reveal
    right = range_mm[1] - edge_reveal
    right - left
  end

  def bay_ranges_for(params_mm)
    parameter_set = AICabinets::Generator::Carcass::Builder::ParameterSet.new(params_mm)
    parameter_set.partition_bay_ranges_mm
  end

  def bay_index_for(instance, ranges_mm)
    bbox = instance.bounds
    center_x = (bbox.min.x + bbox.max.x) / 2.0
    center_x_mm = AICabinetsTestHelper.mm_from_length(center_x)

    ranges_mm.each_with_index do |(left_mm, right_mm), index|
      return index if center_x_mm >= left_mm - tolerance_mm && center_x_mm <= right_mm + tolerance_mm
    end

    nil
  end

  def within_range?(instance, range_mm)
    bbox = instance.bounds
    min_x = AICabinetsTestHelper.mm_from_length(bbox.min.x)
    max_x = AICabinetsTestHelper.mm_from_length(bbox.max.x)
    left_mm, right_mm = range_mm

    min_x >= left_mm - tolerance_mm && max_x <= right_mm + tolerance_mm
  end

  def next_definition_name
    sequence = self.class.instance_variable_get(:@definition_sequence) || 0
    sequence += 1
    self.class.instance_variable_set(:@definition_sequence, sequence)
    "PerBay #{sequence}"
  end

  def tolerance_mm
    AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
  end

  def edge_reveal_mm(params_mm)
    params_mm[:door_edge_reveal_mm] || params_mm[:door_reveal_mm] ||
      params_mm[:door_reveal] || AICabinets::Generator::Fronts::REVEAL_EDGE_MM
  end

  def center_gap_mm(params_mm)
    params_mm[:door_gap_mm] || params_mm[:door_gap] ||
      AICabinets::Generator::Fronts::REVEAL_CENTER_MM
  end
end
