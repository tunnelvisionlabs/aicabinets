# frozen_string_literal: true

begin
  require 'testup/testcase'
rescue LoadError
  warn('SketchUp TestUp not available; skipping boolean fallback tests.')
else
  require_relative 'suite_helper'

  Sketchup.require('aicabinets/geometry/five_piece')
  Sketchup.require('aicabinets/params/five_piece')

  class TC_FivePiece_NoBooleans_Fallback < TestUp::TestCase
    def setup
      AICabinetsTestHelper.clean_model!
    end

    def teardown
      AICabinetsTestHelper.clean_model!
    end

    def test_frame_builds_with_square_fallback_when_booleans_missing
      params = AICabinets::Params::FivePiece.defaults
      definition = Sketchup.active_model.definitions.add('Five Piece No Boolean Fallback')

      warnings = nil
      coping_mode = nil
      with_solid_booleans(false) do
        result = AICabinets::Geometry::FivePiece.build_frame!(
          target: definition,
          params: params,
          open_w_mm: 500.0,
          open_h_mm: 600.0
        )
        warnings = result[:warnings]
        coping_mode = result[:coping_mode]
      end

      assert_equal(:square_fallback, coping_mode)
      assert(warnings.any?)

      definition.entities.grep(Sketchup::Group).each do |group|
        assert(group.volume.positive?) if group.respond_to?(:volume)
      end
    end

    private

    def with_solid_booleans(value)
      capabilities = AICabinets::Capabilities
      singleton = class << capabilities; self; end
      original = capabilities.method(:solid_booleans?)
      singleton.send(:define_method, :solid_booleans?) { value }
      yield
    ensure
      singleton.send(:define_method, :solid_booleans?, original)
    end
  end
end
