# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module Parts
      module PartitionPanel
        module_function

        def build(parent_entities:, name:, thickness:, depth:, height:, x_offset:, z_offset:)
          group = parent_entities.add_group
          group.name = name if group.respond_to?(:name=)

          face = group.entities.add_face(
            ::Geom::Point3d.new(0, 0, 0),
            ::Geom::Point3d.new(0, depth, 0),
            ::Geom::Point3d.new(0, depth, height),
            ::Geom::Point3d.new(0, 0, height)
          )
          face.reverse! if face.normal.x < 0
          distance = face.normal.x.positive? ? thickness : -thickness
          face.pushpull(distance)

          translation = ::Geom::Transformation.translation([x_offset, 0, z_offset])
          group.transform!(translation)

          component = group.to_component
          definition = component.definition
          if definition.respond_to?(:name=)
            definition.name = name
          end
          component.name = name if component.respond_to?(:name=)
          component
        end
      end
    end
  end
end

