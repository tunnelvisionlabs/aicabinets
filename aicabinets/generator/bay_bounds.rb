# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module BayBounds
      module_function

      Bounds = Struct.new(
        :bay_index,
        :axis,
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
      #   :end_mm, :width_mm, and optionally :axis.
      # @return [Bounds, nil]
      def interior_bounds(params:, bay:)
        return nil unless params && bay

        axis = bay.respond_to?(:axis) ? bay.axis : :x
        width_mm =
          if axis == :z
            interior_width_mm(params)
          else
            bay.width_mm.to_f
          end
        return nil if width_mm <= 0.0

        x_start_mm,
          x_end_mm =
            if axis == :z
              left = interior_left_face_mm(params)
              [left, left + width_mm]
            else
              [bay.start_mm.to_f, bay.end_mm.to_f]
            end

        Bounds.new(
          bay_index: bay.index,
          axis: axis,
          x_start_mm: x_start_mm,
          x_end_mm: x_end_mm,
          width_mm: width_mm,
          interior_bottom_z_mm: interior_bottom_mm(params, bay, axis),
          interior_top_z_mm: interior_top_mm(params, bay, axis),
          interior_height_mm: interior_height_mm(params, bay, axis),
          interior_depth_mm: params.interior_depth_mm.to_f
        )
      end

      def interior_width_mm(params)
        params.width_mm.to_f - (params.panel_thickness_mm.to_f * 2.0)
      end
      private_class_method :interior_width_mm

      def interior_left_face_mm(params)
        params.panel_thickness_mm.to_f
      end
      private_class_method :interior_left_face_mm

      def interior_bottom_mm(params, bay, axis)
        return params.interior_bottom_z_mm.to_f unless axis == :z

        bay.start_mm.to_f
      end
      private_class_method :interior_bottom_mm

      def interior_top_mm(params, bay, axis)
        return params.interior_top_z_mm.to_f unless axis == :z

        bay.end_mm.to_f
      end
      private_class_method :interior_top_mm

      def interior_height_mm(params, bay, axis)
        if axis == :z
          [bay.end_mm.to_f - bay.start_mm.to_f, 0.0].max
        else
          params.interior_clear_height_mm.to_f
        end
      end
      private_class_method :interior_height_mm
    end
  end
end

