# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module BayBounds
      module_function

      Bounds = Struct.new(
        :bay_index,
        :x_start_mm,
        :x_end_mm,
        :width_mm,
        :interior_bottom_z_mm,
        :interior_top_z_mm,
        :interior_height_mm,
        :interior_depth_mm,
        keyword_init: true
      )

      # Computes clear interior bounds for a partition bay.
      #
      # @param params [Object] parameter object responding to
      #   :interior_bottom_z_mm, :interior_top_z_mm, :interior_clear_height_mm,
      #   and :interior_depth_mm.
      # @param bay [Object] partition bay responding to :index, :start_mm,
      #   :end_mm, and :width_mm.
      # @return [Bounds, nil]
      def interior_bounds(params:, bay:)
        return nil unless params && bay

        width_mm = bay.width_mm.to_f
        return nil if width_mm <= 0.0

        Bounds.new(
          bay_index: bay.index,
          x_start_mm: bay.start_mm.to_f,
          x_end_mm: bay.end_mm.to_f,
          width_mm: width_mm,
          interior_bottom_z_mm: params.interior_bottom_z_mm.to_f,
          interior_top_z_mm: params.interior_top_z_mm.to_f,
          interior_height_mm: params.interior_clear_height_mm.to_f,
          interior_depth_mm: params.interior_depth_mm.to_f
        )
      end
    end
  end
end

