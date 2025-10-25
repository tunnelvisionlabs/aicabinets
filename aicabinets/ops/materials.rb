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
    end
  end
end
