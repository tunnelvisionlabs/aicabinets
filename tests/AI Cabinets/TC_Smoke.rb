# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

class TC_Smoke < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_sketchup_version_present
    version = Sketchup.version
    refute_nil(version, 'SketchUp version should be available')
    refute_empty(version, 'SketchUp version string should not be empty')

    major = Integer(version.split('.').first, 10)
    assert(major.positive? || major.zero?, 'SketchUp major version should be non-negative')
  end

  def test_extension_namespace_available
    assert(defined?(AICabinets), 'AICabinets namespace should be defined after loading the extension')
    assert_equal('AI Cabinets', AICabinets::EXTENSION_NAME)
  end

  def test_clean_model_leaves_blank_model
    model = Sketchup.active_model

    AICabinetsTestHelper.with_undo('Create geometry') do |m|
      edge = m.active_entities.add_line(ORIGIN, Geom::Point3d.new(12, 0, 0))
      m.selection.add(edge)
    end

    refute_empty(model.active_entities.to_a, 'Precondition failed: expected temporary geometry')
    refute(model.selection.empty?, 'Precondition failed: expected selection populated')

    AICabinetsTestHelper.clean_model!

    assert_equal(0, model.active_entities.count, 'Model should be empty after clean_model!')
    assert(model.selection.empty?, 'Selection should be cleared after clean_model!')
  end

  def test_with_undo_prevents_nesting
    assert_raises(ArgumentError) do
      AICabinetsTestHelper.with_undo('Outer Operation') do
        AICabinetsTestHelper.with_undo('Inner Operation') {}
      end
    end
  end

  def test_with_undo_returns_block_value
    value = AICabinetsTestHelper.with_undo('Return Value') { 42 }
    assert_equal(42, value)
  end

  def test_tolerance_helper
    expected = 10.0
    actual = expected + (AICabinetsTestHelper::TOL / 2.0)
    AICabinetsTestHelper.assert_within_tolerance(self, expected, actual)
  end
end
