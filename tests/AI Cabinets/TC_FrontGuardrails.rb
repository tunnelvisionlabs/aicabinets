# frozen_string_literal: true

require 'testup/testcase'
require 'stringio'

require_relative 'suite_helper'
require_relative '../support/model_query'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/test_harness')

class TC_FrontGuardrails < TestUp::TestCase
  WIDTH_MM = 300.0

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_insert_skips_double_doors_when_below_minimum_width
    config = base_config(front: 'doors_double')

    warnings = capture_warnings do
      _definition, _instance = AICabinets::TestHarness.insert!(config: config)
      assert_equal(0, ModelQuery.count_tagged('AICabinets/Fronts'),
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
    assert_equal(1, ModelQuery.count_tagged('AICabinets/Fronts'),
                 'Baseline cabinet should include a single door front')

    warnings = capture_warnings do
      AICabinets::TestHarness.edit_this_instance!(
        instance: instance,
        config_patch: { front: 'doors_double' }
      )
    end

    assert_equal(0, ModelQuery.count_tagged('AICabinets/Fronts'),
                 'Edit should remove invalid double doors entirely')
    assert_includes(warnings, 'Skipped double doors',
                    'Expected guardrail warning when skipping double doors on edit')

    Sketchup.undo
    assert_equal(1, ModelQuery.count_tagged('AICabinets/Fronts'),
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
    defaults
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
end
