# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module Parts
      module BackPanel
        module_function

        def build(parent_entities:, name:, width:, height:, thickness:, x_offset:, y_offset:, z_offset:)
          group = parent_entities.add_group
          group.name = name

          face = group.entities.add_face(
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(width, 0, 0),
            Geom::Point3d.new(width, 0, height),
            Geom::Point3d.new(0, 0, height)
          )
          face.reverse! if face.normal.y < 0
          distance = face.normal.y.positive? ? thickness : -thickness
          face.pushpull(distance)

          translation = Geom::Transformation.translation([x_offset, y_offset, z_offset])
          group.transform!(translation)
          group
        end
      end
    end
  end
end
