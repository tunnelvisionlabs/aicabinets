# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('support', __dir__))
$LOAD_PATH.unshift(File.expand_path('..', __dir__))

module Geom
  class Point3d; end

  class Transformation
    def initialize(*); end
  end
end

require 'aicabinets/ops/insert_base_cabinet'

class FaceFrameParamsIntegrationTest < Minitest::Test
  def setup
    @defaults = AICabinets::Defaults.load_mm
  end

  def test_schema_version_and_face_frame_defaults_added
    sanitized = AICabinets::Ops::InsertBaseCabinet.send(:validate_params!, @defaults)

    assert_equal(AICabinets::PARAMS_SCHEMA_VERSION, sanitized[:schema_version])
    assert_equal(@defaults[:face_frame], sanitized[:face_frame])
  end

  def test_invalid_face_frame_rejected
    params = Marshal.load(Marshal.dump(@defaults))
    params[:face_frame][:thickness_mm] = 9.0

    error = assert_raises(ArgumentError) do
      AICabinets::Ops::InsertBaseCabinet.send(:validate_params!, params)
    end

    assert_includes(error.message, 'thickness_mm')
  end
end
