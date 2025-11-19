# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/ops/tags')

module AICabinets
  module Metadata
    module Tagging
      module_function

      FRONTS_TAG_NAME = 'Fronts'.freeze
      LEGACY_FRONTS_TAG_NAME = 'AICabinets/Fronts'.freeze

      # Retrieves (or creates) the tag used for face-frame and fronts geometry.
      # Falls back to the active model when no explicit model is provided.
      #
      # @param model [Sketchup::Model, nil]
      # @return [Sketchup::Layer]
      def fronts_tag(model)
        target_model = model if model.is_a?(Sketchup::Model)
        target_model ||= Sketchup.active_model
        validate_model!(target_model)

        layers = target_model.layers
        tag = layers[FRONTS_TAG_NAME]
        return tag if tag

        legacy = layers[LEGACY_FRONTS_TAG_NAME]
        return legacy if legacy

        Ops::Tags.ensure_tag(target_model, FRONTS_TAG_NAME)
      end

      # Assigns the given tag to container entities (groups/components).
      # Raw geometry should remain on the default tag to avoid visibility bugs.
      #
      # @param entity [Sketchup::Entity]
      # @param tag [Sketchup::Layer, nil]
      # @return [Sketchup::Entity, nil]
      def apply_tag!(entity, tag)
        return entity unless container?(entity)
        return entity unless tag.is_a?(Sketchup::Layer)
        return entity unless entity.respond_to?(:layer=)

        entity.layer = tag
        entity
      end

      def container?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end
      private_class_method :container?

      def validate_model!(model)
        return if model.is_a?(Sketchup::Model)

        raise ArgumentError, 'model must be a SketchUp::Model'
      end
      private_class_method :validate_model!
    end
  end
end
