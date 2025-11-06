# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/params_sanitizer'

class SanitizerTest < Minitest::Test
  def setup
    @defaults = {
      partition_mode: 'none',
      shelves: 4,
      front: 'doors_right',
      partitions: {
        mode: 'none',
        count: 0,
        orientation: 'vertical',
        positions_mm: [],
        panel_thickness_mm: nil,
        bays: [
          {
            mode: 'fronts_shelves',
            shelf_count: 4,
            door_mode: 'doors_right',
            fronts_shelves_state: { shelf_count: 4, door_mode: 'doors_right' },
            subpartitions_state: { count: 0 },
            subpartitions: { count: 0, orientation: 'horizontal', bays: [] }
          }
        ]
      }
    }
  end

  def test_expands_bays_to_match_count
    params = {
      partition_mode: 'vertical',
      partitions: {
        count: 2,
        bays: [
          {
            shelf_count: 1,
            door_mode: 'doors_left',
            fronts_shelves_state: { shelf_count: 1, door_mode: 'doors_left' }
          }
        ]
      }
    }

    sanitized, _warnings = sanitize_copy(params)

    bays = sanitized[:partitions][:bays]
    assert_equal(3, bays.length)
    assert_equal(1, bays.first[:shelf_count])
    assert_equal('doors_left', bays.first[:door_mode])
    bays[1..].each do |bay|
      assert_equal(4, bay[:shelf_count])
      assert_equal('doors_right', bay[:door_mode])
    end
  end

  def test_subpartition_bays_created_when_missing
    params = {
      partition_mode: 'vertical',
      partitions: {
        count: 0,
        orientation: 'vertical',
        bays: [
          {
            mode: 'subpartitions',
            subpartitions: { count: 1 }
          }
        ]
      }
    }

    sanitized, _warnings = sanitize_copy(params)

    sub = sanitized[:partitions][:bays].first[:subpartitions]
    assert_equal(2, sub[:bays].length)
    assert_equal(1, sub[:count])
  end

  def test_perpendicular_orientation_enforced_with_warning
    params = {
      partition_mode: 'vertical',
      partitions: {
        count: 1,
        orientation: 'vertical',
        bays: [
          {
            mode: 'subpartitions',
            subpartitions: {
              count: 1,
              orientation: 'vertical',
              bays: []
            }
          },
          {
            mode: 'subpartitions',
            subpartitions: {
              count: 0,
              orientation: 'vertical'
            }
          }
        ]
      }
    }

    sanitized, warnings = sanitize_copy(params)

    sanitized[:partitions][:bays].each do |bay|
      assert_equal('horizontal', bay[:subpartitions][:orientation])
    end

    expected = 'Sub-partitions orientation forced to horizontal to remain perpendicular to vertical.'
    assert_includes(warnings, expected)
    assert_equal(1, warnings.count { |w| w == expected })
  end

  def test_partition_mode_none_resets_count_and_bays
    params = {
      partition_mode: 'none',
      partitions: {
        count: 3,
        bays: [
          { shelf_count: 2 },
          { shelf_count: 2 },
          { shelf_count: 2 },
          { shelf_count: 2 }
        ]
      }
    }

    sanitized, _warnings = sanitize_copy(params)

    partitions = sanitized[:partitions]
    assert_equal(0, partitions[:count])
    assert_equal(1, partitions[:bays].length)
  end

  def test_missing_orientation_backfilled
    params = {
      partition_mode: 'horizontal',
      partitions: {
        count: 0
      }
    }

    sanitized, _warnings = sanitize_copy(params)

    assert_equal('horizontal', sanitized[:partitions][:orientation])
  end

  def test_idempotent
    params = {
      partition_mode: 'vertical',
      partitions: {
        count: 1,
        bays: [
          {
            mode: 'fronts_shelves',
            shelf_count: 2,
            door_mode: 'doors_left',
            fronts_shelves_state: { shelf_count: 2, door_mode: 'doors_left' }
          }
        ]
      }
    }

    first, = sanitize_copy(params)
    second, = AICabinets::ParamsSanitizer.sanitize(first, global_defaults: @defaults)

    assert_equal(first, second)
  end

  def test_nested_counts_match_bays_after_sanitization
    params = {
      partition_mode: 'vertical',
      partitions: {
        count: 2,
        bays: [
          {
            mode: 'subpartitions',
            subpartitions: {
              count: 3,
              bays: []
            }
          }
        ]
      }
    }

    sanitized, = sanitize_copy(params)

    top = sanitized[:partitions]
    assert_equal(top[:count] + 1, top[:bays].length)
    bay_with_sub = top[:bays].find { |bay| bay[:subpartitions].is_a?(Hash) }
    refute_nil(bay_with_sub, 'Expected at least one bay with subpartitions after sanitization')

    sub = bay_with_sub[:subpartitions]
    assert_equal(sub[:count] + 1, sub[:bays].length)
    assert_equal('horizontal', sub[:orientation], 'Nested orientation should be perpendicular to parent')
  end

  private

  def sanitize_copy(params)
    cloned = Marshal.load(Marshal.dump(params))
    AICabinets::ParamsSanitizer.sanitize(cloned, global_defaults: @defaults)
  end
end
