# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/face_frame'

class FaceFrameTest < Minitest::Test
  def test_defaults_mm_matches_expected_values
    defaults = AICabinets::FaceFrame.defaults_mm

    assert_equal(true, defaults[:enabled])
    assert_in_delta(19.0, defaults[:thickness_mm])
    assert_equal([{ kind: 'double_doors' }], defaults[:layout])
  end

  def test_normalize_and_validate_allows_zero_mid_members
    normalized, errors = AICabinets::FaceFrame.normalize({ mid_stile_mm: 0, mid_rail_mm: 0 }, defaults: {})
    assert_empty(errors)

    validation_result = AICabinets::FaceFrame.validate(normalized)
    assert(validation_result[:ok], 'Expected zero validation errors')
  end

  def test_validate_rejects_out_of_range_values
    defaults = AICabinets::FaceFrame.defaults_mm
    normalized, errors = AICabinets::FaceFrame.normalize({ thickness_mm: 9, overlay_mm: 40 }, defaults: defaults)
    assert_empty(errors)

    validation_result = AICabinets::FaceFrame.validate(normalized)
    refute(validation_result[:ok])
    first_error = validation_result[:errors].first
    assert_includes(first_error[:field], 'thickness_mm')
  end

  def test_validate_rejects_unknown_layout_kind
    defaults = AICabinets::FaceFrame.defaults_mm
    normalized, errors = AICabinets::FaceFrame.normalize({ layout: [{ kind: 'unknown' }] }, defaults: defaults)
    assert_empty(errors)

    validation_result = AICabinets::FaceFrame.validate(normalized)
    refute(validation_result[:ok])
    first_error = validation_result[:errors].first
    assert_includes(first_error[:field], 'layout[0].kind')
  end

  def test_normalize_preserves_reveal_and_overlay_mm
    defaults = AICabinets::FaceFrame.defaults_mm
    input = { reveal_mm: 2.0, overlay_mm: 14.7 }

    normalized, errors = AICabinets::FaceFrame.normalize(input, defaults: defaults)

    assert_empty(errors)
    assert_in_delta(2.0, normalized[:reveal_mm], 1.0e-6)
    assert_in_delta(14.7, normalized[:overlay_mm], 1.0e-6)
  end
end
