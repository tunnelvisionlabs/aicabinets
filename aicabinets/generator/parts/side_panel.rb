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

          face = group.entities.add_face(
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(0, depth, 0),
            Geom::Point3d.new(0, depth, height),
            Geom::Point3d.new(0, 0, height)
          )
          face.reverse! if face.normal.x < 0
          distance = face.normal.x.positive? ? panel_thickness : -panel_thickness
          face.pushpull(distance)

          cut_toe_kick_notch(
            group.entities,
            panel_thickness,
            toe_kick_height,
            toe_kick_depth,
            toe_kick_thickness
          )

          translation = Geom::Transformation.translation([x_offset, 0, 0])
          group.transform!(translation)
          group
        end

        def cut_toe_kick_notch(entities, panel_thickness, toe_kick_height, toe_kick_depth, toe_kick_thickness)
          return unless toe_kick_depth.positive? && toe_kick_height.positive?

          effective_thickness = [toe_kick_thickness, toe_kick_depth].min
          total_depth = toe_kick_depth + effective_thickness

          notch = entities.add_face(
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(panel_thickness, 0, 0),
            Geom::Point3d.new(panel_thickness, 0, toe_kick_height),
            Geom::Point3d.new(0, 0, toe_kick_height)
          )

          return unless notch

          notch.reverse! if notch.normal.y.positive?
          notch.pushpull(-total_depth)
        end
        private_class_method :cut_toe_kick_notch
      end
    end
  end
end
