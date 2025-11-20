# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/defaults')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

class TC_FaceFrameValidation < TestUp::TestCase
  def setup
    @defaults = AICabinets::Defaults.load_mm
  end

  def test_schema_bounds_rejected
    params = deep_copy(@defaults)
    params[:face_frame][:thickness_mm] = 9.0

    error = assert_raises(ArgumentError) do
      AICabinets::Ops::InsertBaseCabinet.send(:validate_params!, params)
    end

    assert_includes(error.message, 'thickness_mm')
  end

  def test_minimum_door_width_rejected
    params = deep_copy(@defaults)
    params[:width_mm] = 400.0
    params[:face_frame][:layout] = [{ kind: 'double_doors' }]

    error = assert_raises(ArgumentError) do
      AICabinets::Ops::InsertBaseCabinet.send(:validate_params!, params)
    end

    assert_match(/Minimum door width/, error.message)
  end

  def test_minimum_drawer_face_height_rejected
    params = deep_copy(@defaults)
    params[:height_mm] = 450.0
    params[:face_frame][:layout] = [{ kind: 'drawer_stack', drawers: 3 }]
    params[:face_frame][:mid_rail_mm] = 25.0

    error = assert_raises(ArgumentError) do
      AICabinets::Ops::InsertBaseCabinet.send(:validate_params!, params)
    end

    assert_match(/Minimum drawer face height/, error.message)
  end

  private

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
