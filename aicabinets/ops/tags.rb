# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Ops
    module Tags
      module_function

      # Ensures a tag exists on the model and returns it. SketchUp's Ruby API
      # exposes tags through Model#layers.
      #
      # @param model [Sketchup::Model]
      # @param name [String]
      # @return [Sketchup::Layer]
      def ensure_tag(model, name)
        raise ArgumentError, 'model must be a Sketchup::Model' unless model.is_a?(Sketchup::Model)
        raise ArgumentError, 'name must be provided' if name.to_s.empty?

        layers = model.layers
        layers[name] || layers.add(name)
      end

      # Assigns a tag to an entity, creating the tag if necessary.
      #
      # @param entity [Sketchup::Entity]
      # @param name [String]
      # @return [Sketchup::Layer]
      def assign!(entity, name)
        raise ArgumentError, 'entity must be a Sketchup::Entity' unless entity.is_a?(Sketchup::Entity)

        layer = ensure_tag(entity.model, name)
        entity.layer = layer if entity.respond_to?(:layer=)
        layer
      end
    end
  end
end
