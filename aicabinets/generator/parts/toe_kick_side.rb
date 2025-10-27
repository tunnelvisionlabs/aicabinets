# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Generator
    module Parts
      module ToeKickSide
        module_function

        DICTIONARY_NAME = 'AICabinets'
        PART_KEY = 'part'
        SIDE_KEY = 'side'

        # Builds a toe-kick side block positioned relative to the FLB origin.
        # Geometry is authored in the local definition frame with the minimum
        # corner located at the origin so transforms only translate instances.
        #
        # @param parent_entities [Sketchup::Entities]
        # @param name [String]
        # @param panel_thickness [Length]
        # @param toe_kick_depth [Length]
        # @param toe_kick_height [Length]
        # @param x_offset [Length]
        # @param side [Symbol, String, nil]
        # @return [Sketchup::Group]
        def build(parent_entities:, name:, panel_thickness:, toe_kick_depth:, toe_kick_height:, x_offset:, side: nil)
          group = parent_entities.add_group
          group.name = name

          face = group.entities.add_face(
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(panel_thickness, 0, 0),
            Geom::Point3d.new(panel_thickness, toe_kick_depth, 0),
            Geom::Point3d.new(0, toe_kick_depth, 0)
          )
          face.reverse! if face.normal.z < 0
          distance = face.normal.z.positive? ? toe_kick_height : -toe_kick_height
          face.pushpull(distance)

          dictionary = group.attribute_dictionary(DICTIONARY_NAME, true)
          dictionary[PART_KEY] = 'toe_kick_side'
          dictionary[SIDE_KEY] = side.to_s unless side.nil?

          translation = Geom::Transformation.translation([x_offset, 0, 0])
          group.transform!(translation)
          group
        end
      end
    end
  end
end
