# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('../..', __dir__))

require 'aicabinets/face_frame'

class TestFaceFrameValidator < Minitest::Test
  def setup
    @defaults = AICabinets::FaceFrame.defaults_mm
  end

  def test_rejects_out_of_bounds_fields
    params = @defaults.merge(thickness_mm: 9.0, reveal_mm: 0.0, overlay_mm: 40.0)

    result = AICabinets::FaceFrame.validate(params)

    refute(result[:ok])
    assert_includes(result[:errors].map { |error| error[:field] }, 'face_frame.thickness_mm')
    assert_includes(result[:errors].map { |error| error[:field] }, 'face_frame.reveal_mm')
  end

  def test_accepts_zero_mid_members
    params = @defaults.merge(mid_stile_mm: 0.0, mid_rail_mm: 0.0)

    result = AICabinets::FaceFrame.validate(params)

    assert(result[:ok], "Expected optional mid members to allow zero: #{result[:errors]}")
  end

  def test_layout_type_errors
    params = @defaults.merge(layout: 'double_doors')

    result = AICabinets::FaceFrame.validate(params)

    refute(result[:ok])
    assert_equal('invalid_type', result[:errors].first[:code])
  end

  def test_minimum_door_width_rejected_with_opening
    params = @defaults.merge(layout: [{ kind: 'double_doors' }])
    opening_mm = { x: 0.0, z: 0.0, w: 380.0, h: 700.0 }

    result = AICabinets::FaceFrame.validate(params, opening_mm: opening_mm)

    refute(result[:ok])
    assert_equal('layout_unfeasible', result[:errors].first[:code])
    assert_match(/Minimum door width/, result[:errors].first[:message])
  end

  def test_minimum_drawer_face_height_rejected
    params = @defaults.merge(layout: [{ kind: 'drawer_stack', drawers: 3 }])
    opening_mm = { x: 0.0, z: 0.0, w: 600.0, h: 300.0 }

    result = AICabinets::FaceFrame.validate(params, opening_mm: opening_mm)

    refute(result[:ok])
    assert_equal('layout_unfeasible', result[:errors].first[:code])
    assert_match(/Minimum drawer face height/, result[:errors].first[:message])
  end
end
