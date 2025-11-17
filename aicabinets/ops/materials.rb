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
      DEFAULT_DOOR_FRAME_MATERIAL_NAME = if defined?(AICabinets::DEFAULT_DOOR_FRAME_MATERIAL)
                                            AICabinets::DEFAULT_DOOR_FRAME_MATERIAL
                                          else
                                            'Maple'
                                          end
      DEFAULT_DOOR_FRAME_MATERIAL_COLOR = [224, 200, 160].freeze

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

      # Resolves the default frame material used for five-piece door frames.
      # Maple is used when the project has not provided a specific override.
      #
      # @param model [Sketchup::Model]
      # @return [Sketchup::Material, nil]
      def default_frame(model)
        raise ArgumentError, 'model must be a Sketchup::Model' unless model.is_a?(Sketchup::Model)

        name = DEFAULT_DOOR_FRAME_MATERIAL_NAME
        return nil if name.to_s.empty?

        ensure_material(model, name, DEFAULT_DOOR_FRAME_MATERIAL_COLOR)
      end

      # Finds a material by identifier or falls back to the default door
      # material when no identifier is provided or the material cannot be
      # located.
      #
      # @param model [Sketchup::Model]
      # @param material_id [String, nil]
      # @return [Sketchup::Material, nil]
      def find_or_default(model:, material_id: nil)
        raise ArgumentError, 'model must be a Sketchup::Model' unless model.is_a?(Sketchup::Model)

        materials = model.materials
        material_key = material_id.to_s
        unless material_key.empty?
          material = materials[material_key]
          return material if material

          return ensure_material(model, material_key, nil)
        end

        default_door(model)
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
