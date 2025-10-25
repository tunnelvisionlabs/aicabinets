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
      DEFAULT_CARCASS_MATERIAL_COLOR = [222, 206, 170].freeze
      DEFAULT_DOOR_MATERIAL_NAME = if defined?(AICabinets::DEFAULT_DOOR_MATERIAL)
                                      AICabinets::DEFAULT_DOOR_MATERIAL
                                    else
                                      'MDF'
                                    end
      DEFAULT_DOOR_MATERIAL_COLOR = [164, 143, 122].freeze

      # Resolves (and creates if necessary) the default carcass material for
      # the given model. When the configured name is blank, callers can fall
      # back to SketchUp's default appearance without raising errors.
      #
      # @param model [Sketchup::Model]
      # @return [Sketchup::Material, nil]
      def default_carcass(model)
        raise ArgumentError, 'model must be a Sketchup::Model' unless model.is_a?(Sketchup::Model)

        name = DEFAULT_CARCASS_MATERIAL_NAME
        return nil if name.to_s.empty?

        ensure_material(model, name, DEFAULT_CARCASS_MATERIAL_COLOR)
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

        ensure_material(model, name, DEFAULT_DOOR_MATERIAL_COLOR)
      end

      def ensure_material(model, name, rgb)
        materials = model.materials
        existing = materials[name]
        return existing if existing

        material = materials.add(name)
        if material.respond_to?(:color=) && rgb
          color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
          material.color = color
        end
        material
      end
      private_class_method :ensure_material
    end
  end
end
