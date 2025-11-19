# frozen_string_literal: true

begin
  require 'testup/testcase'
rescue LoadError
  warn('SketchUp TestUp not available; skipping five-piece miter tests.')
else
  require_relative 'suite_helper'

  Sketchup.require('aicabinets/geometry/five_piece')
  Sketchup.require('aicabinets/params/five_piece')
  require_relative '../support/testing'

  class TC_FivePiece_Frame_Miter < TestUp::TestCase
    def setup
      AICabinetsTestHelper.clean_model!
    end

    def teardown
      AICabinetsTestHelper.clean_model!
    end

    def test_mitered_frame_dimensions_and_angle
      params = AICabinets::Params::FivePiece.defaults.merge(joint_type: 'miter')
      definition = Sketchup.active_model.definitions.add('Five Piece Frame Mitered Variant')

      result = AICabinets::Geometry::FivePiece.build_frame!(
        target: definition,
        params: params,
        open_w_mm: 600.0,
        open_h_mm: 720.0
      )

      assert_equal(:miter, result[:joint_type])
      assert_equal(4, definition.entities.grep(Sketchup::Group).length)

      bounds = AICabinetsTestHelper.bbox_local_of(definition)
      expected_w = 600.0 + (2.0 * params[:stile_width_mm])
      expected_h = 720.0 + (2.0 * params[:rail_width_mm])

      assert_in_delta(expected_w, bounds.width.to_mm, AICabinets::Testing.tolerance)
      # BoundingBox dimensions map width->X, height->Y, depth->Z in SketchUp.
      assert_in_delta(params[:door_thickness_mm], bounds.height.to_mm, AICabinets::Testing.tolerance)
      assert_in_delta(expected_h, bounds.depth.to_mm, AICabinets::Testing.tolerance)

      diagonal_face = result[:stiles].flat_map { |stile| stile.entities.grep(Sketchup::Face) }
                                .find do |face|
        next false unless face.normal.x.abs > 1e-3 && face.normal.z.abs > 1e-3

        (face.normal.x.abs - face.normal.z.abs).abs < 1e-2
      end
      refute_nil(diagonal_face)
      x_axis = Geom::Vector3d.new(diagonal_face.normal.x.positive? ? 1 : -1, 0, 0)
      z_axis = Geom::Vector3d.new(0, 0, diagonal_face.normal.z.positive? ? 1 : -1)
      angle_x = diagonal_face.normal.angle_between(x_axis)
      angle_z = diagonal_face.normal.angle_between(z_axis)
      assert_in_delta(Math::PI / 4.0, angle_x, 0.05)
      assert_in_delta(Math::PI / 4.0, angle_z, 0.05)
    end
  end
end
