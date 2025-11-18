# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module Parts
      module SidePanel
        module_function

        def build(parent_entities:, name:, panel_thickness:, height:, depth:, toe_kick_height:, toe_kick_depth:, toe_kick_thickness:, x_offset:)
          group = parent_entities.add_group
          group.name = name

          profile = profile_points(
            height: height,
            depth: depth,
            toe_kick_height: toe_kick_height,
            toe_kick_depth: toe_kick_depth,
            toe_kick_thickness: toe_kick_thickness
          )

          face = group.entities.add_face(*profile)
          face.reverse! if face.normal.x < 0
          distance = face.normal.x.positive? ? panel_thickness : -panel_thickness
          face.pushpull(distance)

          translation = Geom::Transformation.translation([x_offset, 0, 0])
          group.transform!(translation)

          component = group.to_component
          definition = component.definition
          definition.name = name if definition.respond_to?(:name=)
          component.name = name if component.respond_to?(:name=)
          component
        end

        def profile_points(height:, depth:, toe_kick_height:, toe_kick_depth:, toe_kick_thickness:)
          height_in = clamp_positive(length_in_inches(height))
          depth_in = clamp_positive(length_in_inches(depth))
          toe_height_in = clamp_range(length_in_inches(toe_kick_height), 0.0, height_in)
          toe_depth_in = clamp_range(length_in_inches(toe_kick_depth), 0.0, depth_in)
          toe_thickness_in = clamp_range(length_in_inches(toe_kick_thickness), 0.0, toe_depth_in)

          return rectangle_profile(depth_in, height_in) if toe_height_in <= 0.0 || toe_depth_in <= 0.0

          notch_depth_in = clamp_range(toe_depth_in + toe_thickness_in, 0.0, depth_in)
          [
            Geom::Point3d.new(0, notch_depth_in, 0),
            Geom::Point3d.new(0, depth_in, 0),
            Geom::Point3d.new(0, depth_in, height_in),
            Geom::Point3d.new(0, 0, height_in),
            Geom::Point3d.new(0, 0, toe_height_in),
            Geom::Point3d.new(0, notch_depth_in, toe_height_in)
          ]
        end
        private_class_method :profile_points

        def rectangle_profile(depth_in, height_in)
          [
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(0, depth_in, 0),
            Geom::Point3d.new(0, depth_in, height_in),
            Geom::Point3d.new(0, 0, height_in)
          ]
        end
        private_class_method :rectangle_profile

        def clamp_positive(value)
          value.positive? ? value : 0.0
        end
        private_class_method :clamp_positive

        def clamp_range(value, min_value, max_value)
          [[value, max_value].min, min_value].max
        end
        private_class_method :clamp_range

        def length_in_inches(length)
          length.respond_to?(:to_f) ? length.to_f : 0.0
        end
        private_class_method :length_in_inches
      end
    end
  end
end
