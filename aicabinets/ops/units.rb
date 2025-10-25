# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Ops
    # Units conversion helpers centralizing the millimeter to SketchUp Length
    # boundary. All serialized data, defaults, and UI interactions must remain
    # numeric millimeters. Modeling code should call these helpers at the last
    # possible moment before constructing geometry. Do not create Length objects
    # elsewhere—require this file only from generator code.
    module Units
      module_function

      LENGTH_CLASS =
        if defined?(Sketchup::Length)
          Sketchup::Length
        elsif defined?(Length)
          Length
        end

      # Converts a numeric millimeter value to a SketchUp Length. Length inputs
      # are returned unchanged so double conversions remain cheap.
      #
      # @param value_mm [Numeric, Sketchup::Length]
      # @return [Sketchup::Length]
      # @raise [ArgumentError] if value_mm cannot be interpreted as millimeters.
      def to_length_mm(value_mm)
        return value_mm if LENGTH_CLASS && value_mm.is_a?(LENGTH_CLASS)
        raise ArgumentError, 'value must be numeric millimeters' unless value_mm.is_a?(Numeric)

        result = value_mm.to_f.mm
        raise ArgumentError, 'resulting length is NaN' if result.to_f.nan?

        result
      end

      # Convenience constructor for Geom::Point3d using millimeter coordinates.
      # @return [Geom::Point3d]
      def point_mm(x_mm, y_mm, z_mm)
        Geom::Point3d.new(
          to_length_mm(x_mm),
          to_length_mm(y_mm),
          to_length_mm(z_mm)
        )
      end

      # Convenience constructor for Geom::Vector3d using millimeter components.
      # @return [Geom::Vector3d]
      def vector_mm(x_mm, y_mm, z_mm)
        Geom::Vector3d.new(
          to_length_mm(x_mm),
          to_length_mm(y_mm),
          to_length_mm(z_mm)
        )
      end
    end
  end
end
