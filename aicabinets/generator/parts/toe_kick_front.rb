# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module Parts
      module ToeKickFront
        module_function

        def build(parent_entities:, name:, width:, height:, thickness:, x_offset:, y_offset:, z_offset:)
          group = parent_entities.add_group
          group.name = name if group.respond_to?(:name=)

          face = group.entities.add_face(
            ::Geom::Point3d.new(0, 0, 0),
            ::Geom::Point3d.new(width, 0, 0),
            ::Geom::Point3d.new(width, 0, height),
            ::Geom::Point3d.new(0, 0, height)
          )

          if face.normal.y.positive?
            face.reverse!
          end

          distance = face.normal.y.negative? ? thickness : -thickness
          face.pushpull(distance)

          translation = ::Geom::Transformation.translation([x_offset, y_offset, z_offset])
          group.transform!(translation)

          instance = group.to_component
          instance.name = name if instance.respond_to?(:name=)
          definition = instance.definition
          definition.name = name if definition.respond_to?(:name=)

          instance
        end
      end
    end
  end
end
