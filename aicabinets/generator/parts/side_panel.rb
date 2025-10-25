# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module Parts
      module SidePanel
        module_function

        def build(parent_entities:, name:, panel_thickness:, height:, depth:, toe_kick_height:, toe_kick_depth:, x_offset:)
          group = parent_entities.add_group
          group.name = name

          face = group.entities.add_face(*profile_points(depth, height, toe_kick_height, toe_kick_depth))
          face.reverse! if face.normal.x < 0
          distance = face.normal.x.positive? ? panel_thickness : -panel_thickness
          face.pushpull(distance)

          translation = Geom::Transformation.translation([x_offset, 0, 0])
          group.transform!(translation)
          group
        end

        def profile_points(depth, height, toe_kick_height, toe_kick_depth)
          points = []
          points << Geom::Point3d.new(0, 0, 0)

          if toe_kick_depth.positive?
            points << Geom::Point3d.new(0, toe_kick_depth, 0)
            if toe_kick_height.positive?
              points << Geom::Point3d.new(0, toe_kick_depth, toe_kick_height)
              points << Geom::Point3d.new(0, depth, toe_kick_height)
            else
              points << Geom::Point3d.new(0, depth, 0)
            end
          else
            if toe_kick_height.positive?
              points << Geom::Point3d.new(0, 0, toe_kick_height)
              points << Geom::Point3d.new(0, depth, toe_kick_height)
            else
              points << Geom::Point3d.new(0, depth, 0)
            end
          end

          points << Geom::Point3d.new(0, depth, height)
          points << Geom::Point3d.new(0, 0, height)
          points
        end
        private_class_method :profile_points
      end
    end
  end
end
