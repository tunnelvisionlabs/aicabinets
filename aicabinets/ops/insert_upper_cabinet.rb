# frozen_string_literal: true

require 'json'
require 'digest'
require 'sketchup.rb'

require 'aicabinets/defaults'
require 'aicabinets/ops/params_schema'

Sketchup.require('aicabinets/generator/upper_cabinet')
Sketchup.require('aicabinets/ops/tags')
Sketchup.require('aicabinets/tags')

module AICabinets
  module Ops
    module InsertUpperCabinet
      module_function

      OPERATION_NAME = 'AI Cabinets — Insert Upper Cabinet'
      DICTIONARY_NAME = 'AICabinets'
      SCHEMA_VERSION = AICabinets::Ops::ParamsSchema::CURRENT_VERSION
      SCHEMA_VERSION_KEY = 'schema_version'
      TYPE_KEY = 'type'
      TYPE_VALUE = 'upper'
      DEF_KEY = 'def_key'
      PARAMS_JSON_KEY = 'params_json_mm'

      WRAPPER_TAG_NAME = AICabinets::Tags::LEGACY_CABINET_TAG_NAME

      PREFERRED_WRAPPER_TAG_NAME = AICabinets::Tags::CABINET_TAG_NAME
      CABINET_TAG_COLLISION_NAME = AICabinets::Tags::CABINET_TAG_COLLISION_NAME

      REQUIRED_LENGTH_KEYS = %i[width_mm depth_mm height_mm panel_thickness_mm].freeze
      POSITIVE_KEYS = %i[width_mm depth_mm height_mm panel_thickness_mm].freeze

      IDENTITY_TRANSFORMATION = Geom::Transformation.new

      def place_at_point!(model:, point3d:, params_mm:)
        validate_model!(model)
        validate_point!(point3d)

        params = validate_params!(params_mm)
        def_key, params_json = build_definition_key(params)

        cabinet_tag = AICabinets::Tags.ensure_structure!(model)

        operation_open = false
        model.start_operation(OPERATION_NAME, true)
        operation_open = true

        definition = ensure_definition(model, params, def_key, params_json)
        transform = placement_transform(model, point3d)
        instance = add_instance(model, definition, transform)
        assign_wrapper_tag(instance, cabinet_tag)
        model.commit_operation
        operation_open = false
        select_instance(model, instance)
        instance
      ensure
        model.abort_operation if operation_open
      end

      def validate_model!(model)
        return if model.is_a?(Sketchup::Model)

        raise ArgumentError, 'model must be a SketchUp::Model'
      end
      private_class_method :validate_model!

      def validate_point!(point3d)
        return if point3d.is_a?(Geom::Point3d)

        raise ArgumentError, 'point3d must be a Geom::Point3d'
      end
      private_class_method :validate_point!

      def assign_wrapper_tag(instance, cabinet_tag)
        return unless instance.respond_to?(:layer=)

        model = instance.model
        tag =
          if cabinet_tag && cabinet_tag.valid?
            cabinet_tag
          else
            fallback_name = cabinet_tag_name_for(model)
            Ops::Tags.ensure_tag(model, fallback_name)
          end

        instance.layer = tag if tag
        tag
      end
      private_class_method :assign_wrapper_tag

      def cabinet_tag_name_for(model)
        layers = model.layers
        preferred = layers[PREFERRED_WRAPPER_TAG_NAME]
        return preferred.name if preferred && preferred.valid?

        collision = layers[CABINET_TAG_COLLISION_NAME]
        return collision.name if collision && collision.valid?

        WRAPPER_TAG_NAME
      end
      private_class_method :cabinet_tag_name_for

      def validate_params!(params_mm)
        unless params_mm.is_a?(Hash)
          raise ArgumentError, 'params_mm must be a Hash of millimeter values'
        end

        missing = REQUIRED_LENGTH_KEYS.reject { |key| params_mm.key?(key) }
        if missing.any?
          raise ArgumentError, "Missing cabinet parameters: #{missing.join(', ')}"
        end

        REQUIRED_LENGTH_KEYS.each do |key|
          value = params_mm[key]
          unless value.is_a?(Numeric) && value.finite?
            raise ArgumentError, "Parameter #{key} must be a finite number in millimeters"
          end
        end

        POSITIVE_KEYS.each do |key|
          raise ArgumentError, "Parameter #{key} must be greater than 0 mm" if params_mm[key] <= 0
        end

        overlay_mm = params_mm[:overlay_mm]
        if !overlay_mm.nil? && (!overlay_mm.is_a?(Numeric) || overlay_mm < 0)
          raise ArgumentError, 'overlay_mm must be zero or greater'
        end

        copy = deep_copy(params_mm)

        defaults = AICabinets::Defaults.load_effective_mm
        upper_defaults = defaults[:cabinet_upper] || {}
        style_defaults = upper_defaults[:upper] || {}

        copy[:overlay_mm] = overlay_mm || upper_defaults[:overlay_mm] || 0.0
        copy[:back_thickness_mm] =
          if copy.key?(:back_thickness_mm)
            copy[:back_thickness_mm]
          else
            upper_defaults[:back_thickness_mm] || copy[:panel_thickness_mm]
          end
        copy[:top_thickness_mm] ||= upper_defaults[:top_thickness_mm] || copy[:panel_thickness_mm]
        copy[:bottom_thickness_mm] ||= upper_defaults[:bottom_thickness_mm] || copy[:panel_thickness_mm]
        copy[:door_thickness_mm] ||= upper_defaults[:door_thickness_mm]

        style = copy[:upper] || copy['upper'] || {}
        style[:num_shelves] = coerce_non_negative_integer(style[:num_shelves])
        style[:num_shelves] = style_defaults[:num_shelves] if style[:num_shelves].nil?
        style[:num_shelves] = 0 if style[:num_shelves].nil? || style[:num_shelves].negative?
        style[:has_back] = style.key?(:has_back) ? !!style[:has_back] : !!style_defaults[:has_back]
        style[:has_back] = true if style[:has_back].nil?
        copy[:upper] = style

        panel = copy[:panel_thickness_mm].to_f
        if panel * 2 >= copy[:width_mm].to_f
          raise ArgumentError, 'panel_thickness_mm must be less than half of width_mm'
        end
        raise ArgumentError, 'panel_thickness_mm must be less than depth_mm' if panel >= copy[:depth_mm].to_f
        raise ArgumentError, 'panel_thickness_mm must be less than height_mm' if panel >= copy[:height_mm].to_f

        copy
      end
      private_class_method :validate_params!

      def coerce_non_negative_integer(value)
        return nil if value.nil?

        integer = Integer(value)
        integer >= 0 ? integer : nil
      rescue ArgumentError, TypeError
        nil
      end
      private_class_method :coerce_non_negative_integer

      def build_definition_key(params)
        json = AICabinets::Ops::ParamsSchema.canonical_json(params, cabinet_type: TYPE_VALUE)
        digest = Digest::SHA256.hexdigest(json)
        [digest, json]
      end
      private_class_method :build_definition_key

      def ensure_definition(model, params, def_key, params_json)
        existing = find_definition(model, def_key)
        if existing
          assign_definition_attributes(existing, def_key, params_json)
          return existing
        end

        create_definition(model, params, def_key, params_json)
      end
      private_class_method :ensure_definition

      def find_definition(model, def_key)
        model.definitions.each do |definition|
          next unless definition.is_a?(Sketchup::ComponentDefinition)
          next if definition.image?

          dict = definition.attribute_dictionary(DICTIONARY_NAME)
          next unless dict

          type = dict[TYPE_KEY]
          next if type && type != TYPE_VALUE

          stored_def_key = dict[DEF_KEY]
          return definition if stored_def_key == def_key

          params_json = dict[PARAMS_JSON_KEY]
          next unless params_json.is_a?(String) && !params_json.empty?

          stored_digest = AICabinets::Ops::ParamsSchema.digest_from_json(params_json, cabinet_type: TYPE_VALUE)
          return definition if stored_digest == def_key
        end

        nil
      end
      private_class_method :find_definition

      def create_definition(model, params, def_key, params_json)
        definitions = model.definitions
        definition = definitions.add('AI Cabinets Upper Cabinet')
        assign_definition_attributes(definition, def_key, params_json)
        AICabinets::Generator::UpperCabinet.build!(parent: definition, params_mm: params)
        definition
      rescue StandardError => e
        definitions.remove(definition) if definitions.respond_to?(:remove) && definition&.valid?
        raise e
      end
      private_class_method :create_definition

      def assign_definition_attributes(definition, def_key, params_json)
        definition.set_attribute(DICTIONARY_NAME, SCHEMA_VERSION_KEY, SCHEMA_VERSION)
        definition.set_attribute(DICTIONARY_NAME, TYPE_KEY, TYPE_VALUE)
        definition.set_attribute(DICTIONARY_NAME, DEF_KEY, def_key)
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
        raise RuntimeError, "Unable to resolve active path transform: #{e.message}"
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
