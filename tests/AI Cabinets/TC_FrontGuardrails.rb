# frozen_string_literal: true

require 'testup/testcase'
require 'stringio'

require_relative 'suite_helper'
require_relative '../support/model_query'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/test_harness')

class TC_FrontGuardrails < TestUp::TestCase
  # Width selected so each double-door leaf would fall below the 140 mm guardrail.
  WIDTH_MM = 280.0

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_insert_skips_double_doors_when_below_minimum_width
    config = base_config(front: 'doors_double')

    warnings = capture_warnings do
      _definition, instance = AICabinets::TestHarness.insert!(config: config)
      fronts = ModelQuery.front_entities(instance: instance)
      assert_equal(0, fronts.length,
                   'Generator should skip creating double fronts for narrow bays')
      Sketchup.undo
      assert_empty(Sketchup.active_model.entities.grep(Sketchup::ComponentInstance),
                   'Undo should remove the inserted cabinet in one step')
    end

    assert_includes(warnings, 'Skipped double doors',
                    'Expected guardrail warning when skipping invalid double doors')
  end

  def test_edit_skips_double_doors_when_below_minimum_width
    definition, instance = AICabinets::TestHarness.insert!(config: base_config(front: 'doors_left'))
    fronts = ModelQuery.front_entities(instance: instance)
    assert_equal(1, fronts.length,
                 'Baseline cabinet should include a single door front')

    warnings = capture_warnings do
      AICabinets::TestHarness.edit_this_instance!(
        instance: instance,
        config_patch: front_patch('doors_double')
      )
    end

    fronts_after_edit = ModelQuery.front_entities(instance: instance)
    assert_equal(0, fronts_after_edit.length,
                 'Edit should remove invalid double doors entirely')
    assert_includes(warnings, 'Skipped double doors',
                    'Expected guardrail warning when skipping double doors on edit')

    Sketchup.undo
    fronts_after_undo = ModelQuery.front_entities(instance: instance)
    assert_equal(1, fronts_after_undo.length,
                 'Undo should restore the original single door front')

    params = AICabinetsTestHelper.params_mm_from_definition(definition)
    assert_equal('doors_left', params[:front],
                 'Undo should restore stored parameters to the prior state')
  end

  private

  def base_config(front: 'doors_double')
    defaults = deep_copy(AICabinets::Defaults.load_effective_mm)
    defaults[:width_mm] = WIDTH_MM
    defaults[:front] = front
    defaults[:partition_mode] = 'none'
    defaults[:door_gap_mm] = 2.0
    defaults[:fronts_shelves_state] = deep_copy(defaults[:fronts_shelves_state]) || {}
    defaults[:fronts_shelves_state][:door_mode] = front
    sync_front_to_partitions!(defaults, front)
    defaults
  end

  def front_patch(front)
    {
      front: front,
      fronts_shelves_state: { door_mode: front },
      partitions: {
        bays: [
          {
            door_mode: front,
            fronts_shelves_state: { door_mode: front }
          }
        ]
      }
    }
  end

  def capture_warnings
    original = $stderr
    buffer = StringIO.new
    $stderr = buffer
    yield
    buffer.string
  ensure
    $stderr = original
  end

  def deep_copy(object)
    Marshal.load(Marshal.dump(object))
  end

  def sync_front_to_partitions!(config, front)
    partitions = config[:partitions]
    unless partitions.is_a?(Hash)
      partitions = {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        positions_mm: [],
        panel_thickness_mm: nil,
        bays: []
      }
      config[:partitions] = partitions
    end

    partitions[:bays] = Array(partitions[:bays]).map do |bay|
      bay.is_a?(Hash) ? deep_copy(bay) : {}
    end
    partitions[:bays] = [{}] if partitions[:bays].empty?

    partitions[:bays].map! do |bay|
      bay[:mode] ||= 'fronts_shelves'
      bay[:door_mode] = front

      state = bay[:fronts_shelves_state]
      state = state.is_a?(Hash) ? deep_copy(state) : {}
      state[:door_mode] = front
      bay[:fronts_shelves_state] = state

      bay
    end

    partitions[:count] = 0 if partitions[:count].nil?
    partitions[:mode] ||= 'none'
    partitions[:orientation] ||= 'vertical'
    partitions[:positions_mm] ||= []
  end
end
