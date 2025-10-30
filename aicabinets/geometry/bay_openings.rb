# frozen_string_literal: true

module AICabinets
  module Geometry
    module BayOpenings
      module_function

      Opening = Struct.new(
        :index,
        :left_mm,
        :right_mm,
        :bottom_mm,
        :top_mm,
        :width_mm,
        :height_mm,
        keyword_init: true
      )

      # Computes the clear opening for each bay at the cabinet front.
      #
      # @param bay_ranges_mm [Array<Array<Float>>] pairs of [left, right] mm values
      # @param edge_reveal_mm [Float]
      # @param top_reveal_mm [Float]
      # @param bottom_reveal_mm [Float]
      # @param toe_kick_height_mm [Float]
      # @param toe_kick_depth_mm [Float]
      # @param cabinet_height_mm [Float]
      # @return [Array<Opening>]
      def compute(
        bay_ranges_mm:,
        edge_reveal_mm:,
        top_reveal_mm:,
        bottom_reveal_mm:,
        toe_kick_height_mm:,
        toe_kick_depth_mm:,
        cabinet_height_mm:
      )
        ranges = Array(bay_ranges_mm)
        return [] if ranges.empty?

        left_reveal = edge_reveal_mm.to_f
        top_reveal = top_reveal_mm.to_f
        bottom_reveal = bottom_reveal_mm.to_f
        toe_clearance = toe_kick_clearance_mm(toe_kick_height_mm, toe_kick_depth_mm)
        total_height = cabinet_height_mm.to_f

        available_height_mm = total_height - toe_clearance
        clear_height_mm = available_height_mm - top_reveal - bottom_reveal
        bottom_mm = toe_clearance + bottom_reveal
        top_mm = bottom_mm + clear_height_mm

        ranges.each_with_index.map do |(left_mm, right_mm), index|
          left = left_mm.to_f + left_reveal
          right = right_mm.to_f - left_reveal

          Opening.new(
            index: index,
            left_mm: left,
            right_mm: right,
            bottom_mm: bottom_mm,
            top_mm: top_mm,
            width_mm: right - left,
            height_mm: clear_height_mm
          )
        end
      end

      def toe_kick_clearance_mm(height_mm, depth_mm)
        height = height_mm.to_f
        depth = depth_mm.to_f
        return 0.0 unless height.positive? && depth.positive?

        height
      end
      private_class_method :toe_kick_clearance_mm
    end
  end
end
