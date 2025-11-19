# frozen_string_literal: true

begin
  require 'testup/testcase'
rescue LoadError
  warn('SketchUp TestUp not available; skipping five-piece frame cope tests.')
else
  require_relative 'suite_helper'

  Sketchup.require('aicabinets/geometry/five_piece')
  Sketchup.require('aicabinets/params/five_piece')
  require_relative '../support/testing'

  class TC_FivePiece_Frame_Coped < TestUp::TestCase
    def setup
      AICabinetsTestHelper.clean_model!
    end

    def teardown
      AICabinetsTestHelper.clean_model!
    end

    def test_default_frame_uses_front_tag_and_is_solid
      params = AICabinets::Params::FivePiece.defaults
      definition = Sketchup.active_model.definitions.add('Five Piece Frame Coped')

      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )

      assert_equal(:cope_stick, result[:joint_type])
      assert_equal(4, definition.entities.grep(Sketchup::Group).length)

      bounds = AICabinetsTestHelper.bbox_local_of(definition)
      assert_in_delta(0.0, bounds.min.x.to_mm, AICabinets::Testing.tolerance)
      assert_in_delta(0.0, bounds.min.y.to_mm, AICabinets::Testing.tolerance)
      assert_in_delta(0.0, bounds.min.z.to_mm, AICabinets::Testing.tolerance)

      definition.entities.grep(Sketchup::Group).each do |group|
        assert_equal('AICabinets/Fronts', group.layer.name)
        assert(group.volume.positive?) if group.respond_to?(:volume)
      end
    end
  end
end
