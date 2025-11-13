# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module Parts
      module TopPanel
        module_function

        def build(parent_entities:, name:, width:, depth:, thickness:, x_offset:, y_offset:, z_offset:)
          group = parent_entities.add_group
          group.name = name

          face = group.entities.add_face(
            ::Geom::Point3d.new(0, 0, 0),
            ::Geom::Point3d.new(width, 0, 0),
            ::Geom::Point3d.new(width, depth, 0),
            ::Geom::Point3d.new(0, depth, 0)
          )
          face.reverse! if face.normal.z < 0
          distance = face.normal.z.positive? ? thickness : -thickness
          face.pushpull(distance)

          translation = ::Geom::Transformation.translation([x_offset, y_offset, z_offset])
          group.transform!(translation)
          group
        end
      end
    end
  end
end
