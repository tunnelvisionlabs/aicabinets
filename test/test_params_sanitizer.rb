# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/params_sanitizer'

class ParamsSanitizerTest < Minitest::Test
  def setup
    @defaults = {
      partition_mode: 'none',
      shelves: 4,
      front: 'doors_right',
      partitions: {
        mode: 'none',
        count: 0,
        positions_mm: [],
        panel_thickness_mm: nil,
        bays: [{ shelf_count: 4, door_mode: 'doors_right' }]
      }
    }
  end

  def test_creates_partitions_when_missing
    params = {}

    result = AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)

    partitions = result.fetch(:partitions)
    assert_equal(0, partitions[:count])
    assert_equal(1, partitions[:bays].length)
    bay = partitions[:bays].first
    assert_equal(4, bay[:shelf_count])
    assert_equal('doors_right', bay[:door_mode])
  end

  def test_expands_bays_to_match_count
    params = {
      partitions: {
        count: 2,
        bays: [{ shelf_count: 1, door_mode: 'doors_left' }]
      }
    }

    result = AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)

    bays = result[:partitions][:bays]
    assert_equal(3, bays.length)
    assert_equal({ shelf_count: 1, door_mode: 'doors_left' }, bays.first)
    bays[1..].each do |bay|
      assert_equal(4, bay[:shelf_count])
      assert_equal('doors_right', bay[:door_mode])
    end
  end

  def test_truncates_extra_bays
    params = {
      partitions: {
        count: 0,
        bays: [
          { shelf_count: 2, door_mode: 'doors_double' },
          { shelf_count: 3, door_mode: 'doors_left' }
        ]
      }
    }

    result = AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)

    bays = result[:partitions][:bays]
    assert_equal(1, bays.length)
    assert_equal(2, bays.first[:shelf_count])
    assert_equal('doors_double', bays.first[:door_mode])
  end

  def test_coerces_invalid_count_and_bay_values
    params = {
      shelves: 2,
      front: 'doors_left',
      partitions: {
        count: '-3',
        bays: [
          { shelf_count: -5, door_mode: 'invalid' },
          'not a hash'
        ]
      }
    }

    result = AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)

    partitions = result[:partitions]
    assert_equal(1, partitions[:bays].length)
    bay = partitions[:bays].first
    # Invalid shelf count and door mode fall back to defaults
    assert_equal(4, bay[:shelf_count])
    assert_equal('doors_right', bay[:door_mode])
  end

  def test_idempotent
    params = {
      partitions: {
        count: 1,
        bays: [
          { 'shelf_count' => 3, 'door_mode' => 'doors_left' },
          { shelf_count: 2 }
        ]
      }
    }

    first = AICabinets::ParamsSanitizer.sanitize!(Marshal.load(Marshal.dump(params)), global_defaults: @defaults)
    second = AICabinets::ParamsSanitizer.sanitize!(first, global_defaults: @defaults)

    assert_equal(first, second)
    assert_equal(2, second[:partitions][:bays].length)
  end

  def test_preserves_explicit_nil_door_mode
    params = {
      partitions: {
        count: 0,
        bays: [{ shelf_count: 1, door_mode: nil }]
      }
    }

    result = AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)

    bay = result[:partitions][:bays].first
    assert_nil(bay[:door_mode])
    assert_equal(1, bay[:shelf_count])
  end

  def test_maps_none_string_to_nil_door_mode
    params = {
      partitions: {
        count: 0,
        bays: [{ door_mode: 'none' }]
      }
    }

    result = AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)

    bay = result[:partitions][:bays].first
    assert_nil(bay[:door_mode])
  end

  def test_partition_mode_defaults_to_none
    params = { partition_mode: 'diagonal' }

    result = AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)

    assert_equal('none', result[:partition_mode])
  end

  def test_partition_mode_respects_valid_values
    params = { partition_mode: 'vertical' }

    result = AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)

    assert_equal('vertical', result[:partition_mode])
  end
end
