# frozen_string_literal: true

require_relative 'test_helper'

require 'aicabinets/params/five_piece'
require 'aicabinets/validation_error'

class FivePieceParamsValidateTest < Minitest::Test
  def test_coerce_normalizes_strings_and_aliases
    raw = {
      'stile_width_mm' => '60.5',
      'rail_width' => '42',
      panel_clearance_per_side: '2.5',
      joint_type: 'miter'
    }

    params = AICabinets::Params::FivePiece.coerce(raw: raw)

    assert_in_delta(60.5, params[:stile_width_mm], 1e-6)
    assert_in_delta(42.0, params[:rail_width_mm], 1e-6)
    assert_in_delta(2.5, params[:panel_clearance_per_side_mm], 1e-6)
    assert_equal('miter', params[:joint_type])
  end

  def test_validate_rejects_panel_thicker_than_groove
    params = AICabinets::Params::FivePiece.defaults.merge(
      groove_width_mm: 10.0,
      panel_thickness_mm: 9.5,
      panel_clearance_per_side_mm: 1.0
    )

    error = assert_raises(AICabinets::ValidationError) do
      AICabinets::Params::FivePiece.validate!(params: params)
    end

    assert_includes(error.messages.first, 'groove_width_mm')
    assert_includes(error.message, 'groove_width_mm')
  end

  def test_validate_enforces_stile_width_by_joint
    params = AICabinets::Params::FivePiece.defaults.merge(
      joint_type: 'cope_stick',
      stile_width_mm: 30.0,
      groove_depth_mm: 15.0
    )

    error = assert_raises(AICabinets::ValidationError) do
      AICabinets::Params::FivePiece.validate!(params: params)
    end

    assert(error.messages.any? { |message| message.include?('stile_width_mm') })
  end
end
