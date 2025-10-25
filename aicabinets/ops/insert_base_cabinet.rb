# frozen_string_literal: true

require 'json'
require 'digest'
require 'sketchup.rb'

Sketchup.require('aicabinets/generator/carcass')

module AICabinets
  module Ops
    module InsertBaseCabinet
      module_function

      OPERATION_NAME = 'AI Cabinets — Insert Base Cabinet'
      DICTIONARY_NAME = 'AICabinets'
      TYPE_KEY = 'type'
      TYPE_VALUE = 'base_cabinet'
      FINGERPRINT_KEY = 'fingerprint'
      PARAMS_JSON_KEY = 'params_json_mm'

      REQUIRED_LENGTH_KEYS = %i[
        width_mm
        depth_mm
        height_mm
        panel_thickness_mm
        toe_kick_height_mm
        toe_kick_depth_mm
      ].freeze

      POSITIVE_KEYS = %i[
        width_mm
        depth_mm
        height_mm
        panel_thickness_mm
      ].freeze

      NON_NEGATIVE_KEYS = %i[
        toe_kick_height_mm
        toe_kick_depth_mm
      ].freeze

      IDENTITY_TRANSFORMATION = Geom::Transformation.new

      def place_at_point!(model:, point3d:, params_mm:)
        unless model.is_a?(Sketchup::Model)
          warn('AI Cabinets: place_at_point! requires a SketchUp model.')
          return nil
        end

        unless point3d.is_a?(Geom::Point3d)
          warn('AI Cabinets: place_at_point! requires a Geom::Point3d pick point.')
          return nil
        end

        params = validate_params(params_mm)
        return nil unless params

        fingerprint, params_json = build_fingerprint(params)

        model.start_operation(OPERATION_NAME, true)

        definition = ensure_definition(model, params, fingerprint, params_json)
        transform = placement_transform(model, point3d)
        instance = add_instance(model, definition, transform)
        select_instance(model, instance)
        model.commit_operation
        instance
      rescue StandardError => e
        warn("AI Cabinets: Failed to insert base cabinet: #{e.message}")
        model.abort_operation if model.respond_to?(:abort_operation)
        nil
      end

      def validate_params(params_mm)
        unless params_mm.is_a?(Hash)
          warn('AI Cabinets: Cabinet parameters must be a Hash.')
          return nil
        end

        missing = REQUIRED_LENGTH_KEYS.reject { |key| params_mm.key?(key) }
        unless missing.empty?
          warn("AI Cabinets: Missing cabinet parameters: #{missing.join(', ')}")
          return nil
        end

        REQUIRED_LENGTH_KEYS.each do |key|
          value = params_mm[key]
          unless value.is_a?(Numeric) && value.finite?
            warn("AI Cabinets: Parameter #{key} must be a finite number.")
            return nil
          end
        end

        POSITIVE_KEYS.each do |key|
          if params_mm[key] <= 0
            warn("AI Cabinets: Parameter #{key} must be greater than 0 mm.")
            return nil
          end
        end

        NON_NEGATIVE_KEYS.each do |key|
          if params_mm[key] < 0
            warn("AI Cabinets: Parameter #{key} must be at least 0 mm.")
            return nil
          end
        end

        deep_copy(params_mm)
      end
      private_class_method :validate_params

      def build_fingerprint(params)
        canonical = canonicalize(params)
        json = JSON.generate(canonical)
        digest = Digest::SHA256.hexdigest(json)
        [digest, json]
      end
      private_class_method :build_fingerprint

      def ensure_definition(model, params, fingerprint, params_json)
        existing = find_definition(model, fingerprint)
        return existing if existing

        create_definition(model, params, fingerprint, params_json)
      end
      private_class_method :ensure_definition

      def find_definition(model, fingerprint)
        model.definitions.each do |definition|
          next unless definition.is_a?(Sketchup::ComponentDefinition)
          next if definition.image?

          dict = definition.attribute_dictionary(DICTIONARY_NAME)
          next unless dict
          next unless dict[FINGERPRINT_KEY] == fingerprint
          next unless dict[TYPE_KEY] == TYPE_VALUE

          return definition
        end

        nil
      end
      private_class_method :find_definition

      def create_definition(model, params, fingerprint, params_json)
        definitions = model.definitions
        definition = definitions.add('AI Cabinets Base Cabinet')
        assign_definition_attributes(definition, fingerprint, params_json)
        AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params)
        definition
      rescue StandardError => e
        definitions.remove(definition) if definitions.respond_to?(:remove) && definition&.valid?
        raise e
      end
      private_class_method :create_definition

      def assign_definition_attributes(definition, fingerprint, params_json)
        definition.set_attribute(DICTIONARY_NAME, TYPE_KEY, TYPE_VALUE)
        definition.set_attribute(DICTIONARY_NAME, FINGERPRINT_KEY, fingerprint)
        definition.set_attribute(DICTIONARY_NAME, PARAMS_JSON_KEY, params_json)
      end
      private_class_method :assign_definition_attributes

      def placement_transform(model, point3d)
        context_transform = active_path_transform(model)
        local_point = point3d.transform(context_transform.inverse)
        Geom::Transformation.translation(local_point)
      end
      private_class_method :placement_transform

      def active_path_transform(model)
        path = model.active_path
        return IDENTITY_TRANSFORMATION if path.nil? || path.empty?

        Sketchup::InstancePath.new(path).transformation
      rescue StandardError => e
        warn("AI Cabinets: Unable to resolve active path transform: #{e.message}")
        IDENTITY_TRANSFORMATION
      end
      private_class_method :active_path_transform

      def add_instance(model, definition, transform)
        instance = model.active_entities.add_instance(definition, transform)
        unless instance.is_a?(Sketchup::ComponentInstance)
          raise 'Instance placement failed.'
        end

        instance
      end
      private_class_method :add_instance

      def select_instance(model, instance)
        selection = model.selection
        return unless selection

        selection.clear
        selection.add(instance) if instance&.valid?
      end
      private_class_method :select_instance

      def canonicalize(value)
        case value
        when Hash
          value.keys.sort_by(&:to_s).each_with_object({}) do |key, memo|
            memo[key.to_s] = canonicalize(value[key])
          end
        when Array
          value.map { |item| canonicalize(item) }
        else
          value
        end
      end
      private_class_method :canonicalize

      def deep_copy(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, val), memo|
            memo[key] = deep_copy(val)
          end
        when Array
          value.map { |item| deep_copy(item) }
        else
          value
        end
      end
      private_class_method :deep_copy
    end
  end
end
