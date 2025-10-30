# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/ui_visibility'

class UiVisibilityTest < Minitest::Test
  def test_flags_default_to_global_controls
    flags = AICabinets::UiVisibility.flags_for(nil)

    assert_equal(false, flags[:show_bays])
    assert_equal(true, flags[:show_global_front_layout])
    assert_equal(true, flags[:show_global_shelves])
  end

  def test_flags_for_none_mode
    params = { partitions: { mode: 'none' } }

    flags = AICabinets::UiVisibility.flags_for(params)

    assert_equal(false, flags[:show_bays])
    assert_equal(true, flags[:show_global_front_layout])
    assert_equal(true, flags[:show_global_shelves])
  end

  def test_flags_for_partitioned_mode
    params = { partitions: { mode: 'even' } }

    flags = AICabinets::UiVisibility.flags_for(params)

    assert_equal(true, flags[:show_bays])
    assert_equal(false, flags[:show_global_front_layout])
    assert_equal(false, flags[:show_global_shelves])
  end

  def test_flags_for_unknown_mode_defaults_to_none
    params = { partitions: { mode: 'unexpected' } }

    flags = AICabinets::UiVisibility.flags_for(params)

    assert_equal(false, flags[:show_bays])
    assert_equal(true, flags[:show_global_front_layout])
    assert_equal(true, flags[:show_global_shelves])
  end

  def test_clamp_selected_index_handles_bounds
    assert_equal(0, AICabinets::UiVisibility.clamp_selected_index(0, 0))
    assert_equal(0, AICabinets::UiVisibility.clamp_selected_index(-1, 3))
    assert_equal(2, AICabinets::UiVisibility.clamp_selected_index(5, 3))
    assert_equal(1, AICabinets::UiVisibility.clamp_selected_index(1, 3))
  end
end
