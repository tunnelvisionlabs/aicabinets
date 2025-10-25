# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Ops
    module Materials
      module_function

      DEFAULT_CARCASS_MATERIAL_NAME = if defined?(AICabinets::DEFAULT_CABINET_MATERIAL)
                                         AICabinets::DEFAULT_CABINET_MATERIAL
                                       else
                                         'Birch Plywood'
                                       end
      DEFAULT_DOOR_MATERIAL_NAME = if defined?(AICabinets::DEFAULT_DOOR_MATERIAL)
                                      AICabinets::DEFAULT_DOOR_MATERIAL
                                    else
                                      'MDF'
                                    end
      DEFAULT_DOOR_MATERIAL_COLOR = [164, 143, 122].freeze

      # Resolves the default carcass material for the given model. Returns nil
      # when the configured material is not present, allowing callers to fall
      # back to SketchUp's default appearance without raising errors.
      #
      # @param model [Sketchup::Model]
      # @return [Sketchup::Material, nil]
      def default_carcass(model)
        raise ArgumentError, 'model must be a Sketchup::Model' unless model.is_a?(Sketchup::Model)

        name = DEFAULT_CARCASS_MATERIAL_NAME
        return nil if name.to_s.empty?

        model.materials[name]
      end

      # Resolves (and creates if necessary) the default door material. Doors use
      # a solid-color MDF when the material is missing so newly generated
      # cabinets look consistent with README defaults.
      #
      # @param model [Sketchup::Model]
      # @return [Sketchup::Material, nil]
      def default_door(model)
        raise ArgumentError, 'model must be a Sketchup::Model' unless model.is_a?(Sketchup::Model)

        name = DEFAULT_DOOR_MATERIAL_NAME
        return nil if name.to_s.empty?

        materials = model.materials
        existing = materials[name]
        return existing if existing

        material = materials.add(name)
        if material.respond_to?(:color=)
          rgb = DEFAULT_DOOR_MATERIAL_COLOR
          material.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
        end
        material
      end
    end
  end
end
