# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))
$LOAD_PATH.unshift(File.expand_path('support', __dir__))

require 'sketchup.rb'

require 'aicabinets/door_mode_rules'
require 'aicabinets/defaults'

class DoorModeRulesTest < Minitest::Test
  def setup
    @defaults = AICabinets::Defaults.load_effective_mm
  end

  def test_double_door_allowed_for_default_bay
    allowed, reason, metadata =
      AICabinets::DoorModeRules.double_door_validity(params_mm: @defaults, bay_index: 0)

    assert_equal(true, allowed)
    assert_nil(reason)
    assert_kind_of(Hash, metadata)
    refute_nil(metadata[:leaf_width_mm])
    refute_nil(metadata[:min_leaf_width_mm])
    assert(metadata[:leaf_width_mm] > metadata[:min_leaf_width_mm])
  end

  def test_double_door_rejected_for_narrow_bay
    params = Marshal.load(Marshal.dump(@defaults))
    params[:width_mm] = 41.0
    params[:panel_thickness_mm] = 18.0

    allowed, reason, metadata =
      AICabinets::DoorModeRules.double_door_validity(params_mm: params, bay_index: 0)

    refute(allowed)
    assert_equal(:door_mode_double_disabled_hint, reason)
    assert_kind_of(Hash, metadata)
    refute_nil(metadata[:min_leaf_width_mm])
    refute_nil(metadata[:leaf_width_mm])
    assert(metadata[:leaf_width_mm] < metadata[:min_leaf_width_mm])
  end

  def test_invalid_index_returns_failure
    allowed, reason, metadata =
      AICabinets::DoorModeRules.double_door_validity(params_mm: @defaults, bay_index: 5)

    refute(allowed)
    assert_equal(:door_mode_double_disabled_hint, reason)
    assert_kind_of(Hash, metadata)
    assert(metadata.key?(:min_leaf_width_mm))
  end
end
