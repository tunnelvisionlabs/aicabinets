# frozen_string_literal: true

require_relative 'test_helper'

require 'aicabinets/params/five_piece'

class FivePieceParamsDefaultsTest < Minitest::Test
  def test_defaults_use_mm_suffix_for_lengths
    defaults = AICabinets::Params::FivePiece.defaults

    mm_keys = defaults.keys.select { |key| key.to_s.end_with?('_mm') }
    numeric_mm_keys = defaults.select { |key, value| value.is_a?(Numeric) && key.to_s.end_with?('_mm') }.keys

    assert_equal(mm_keys.sort, (mm_keys & numeric_mm_keys).sort,
                 'Numeric defaults should use _mm suffix for length keys')
    refute_empty(mm_keys)
  end

  def test_defaults_match_expected_values
    defaults = AICabinets::Params::FivePiece.defaults

    assert_equal('five_piece', defaults[:door_type])
    assert_equal('cope_stick', defaults[:joint_type])
    assert_in_delta(57.0, defaults[:stile_width_mm], 1e-6)
    assert_equal(defaults[:stile_width_mm], defaults[:rail_width_mm])
    assert_in_delta(3.0, defaults[:panel_clearance_per_side_mm], 1e-6)
  end
end
