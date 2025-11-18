# frozen_string_literal: true

require 'json'
require 'digest'
require 'sketchup.rb'

Sketchup.require('aicabinets/generator/upper_cabinet')
Sketchup.require('aicabinets/ops/insert_upper_cabinet')
Sketchup.require('aicabinets/tags')
Sketchup.require('aicabinets/ops/params_schema')

module AICabinets
  module Ops
    module EditUpperCabinet
      module_function

      OPERATION_NAME = 'AI Cabinets — Edit Upper Cabinet'
      VALID_SCOPES = %w[instance all].freeze

      DICTIONARY_NAME = InsertUpperCabinet::DICTIONARY_NAME
      SCHEMA_VERSION_KEY = InsertUpperCabinet::SCHEMA_VERSION_KEY
      SCHEMA_VERSION = AICabinets::Ops::ParamsSchema::CURRENT_VERSION
      TYPE_KEY = InsertUpperCabinet::TYPE_KEY
      TYPE_VALUE = InsertUpperCabinet::TYPE_VALUE
      DEF_KEY = InsertUpperCabinet::DEF_KEY
      PARAMS_JSON_KEY = InsertUpperCabinet::PARAMS_JSON_KEY
      WRAPPER_TAG_NAME = InsertUpperCabinet::WRAPPER_TAG_NAME
      OWNED_TAG_PREFIX = 'AICabinets/'.freeze

      Result = Struct.new(:instance, :definition, :error_code, keyword_init: true)
      private_constant :Result

      def apply_to_selection!(model:, params_mm:, scope: 'instance')
        validate_model!(model)

        scope_value = normalize_scope(scope)
        params = validate_params!(params_mm)

        AICabinets::Tags.ensure_structure!(model)

        selection_result = selected_cabinet_instance(model)
        unless selection_result.error_code.nil?
          return build_selection_error(selection_result.error_code)
        end

        instance = selection_result.instance
        definition = selection_result.definition
        unless definition&.valid?
          return build_selection_error(:not_cabinet)
        end

        def_key, params_json = build_definition_key(params)
        stored_params_json = definition.get_attribute(DICTIONARY_NAME, PARAMS_JSON_KEY)
        stored_def_key = definition.get_attribute(DICTIONARY_NAME, DEF_KEY)
        stored_digest = AICabinets::Ops::ParamsSchema.digest_from_json(stored_params_json, cabinet_type: TYPE_VALUE)

        if stored_def_key == def_key && stored_params_json == params_json && stored_digest == def_key
          return { ok: true }
        end

        operation_open = false
        model.start_operation(OPERATION_NAME, true)
        operation_open = true

        definition = ensure_definition_for_scope(instance, scope_value)
        rebuild_definition!(definition, params)
        assign_definition_attributes(definition, def_key, params_json)

        model.commit_operation
        operation_open = false

        ensure_instance_selected(model, instance)

        { ok: true }
      rescue ArgumentError => e
        { ok: false, error: { code: 'invalid_params', message: e.message } }
      rescue StandardError => e
        warn("AI Cabinets: Unexpected error while editing upper cabinet: #{e.message}")
        { ok: false, error: { code: 'internal_error', message: 'Unable to edit the selected cabinet.' } }
      ensure
        model.abort_operation if operation_open
      end

      def validate_model!(model)
        return if model.is_a?(Sketchup::Model)

        raise ArgumentError, 'model must be a SketchUp::Model'
      end
      private_class_method :validate_model!

      def validate_params!(params_mm)
        unless params_mm.is_a?(Hash)
          raise ArgumentError, 'params_mm must be a Hash of millimeter values'
        end

        InsertUpperCabinet.__send__(:validate_params!, params_mm)
      end
      private_class_method :validate_params!

      def normalize_scope(value)
        unless value.is_a?(String) || value.is_a?(Symbol)
          raise ArgumentError, 'scope must be a String or Symbol'
        end

        normalized = value.to_s.strip.downcase
        return normalized if VALID_SCOPES.include?(normalized)

        raise ArgumentError, 'scope must be "instance" or "all"'
      end
      private_class_method :normalize_scope

      def selected_cabinet_instance(model)
        selection = model.selection
        unless selection&.count == 1
          return Result.new(error_code: :no_selection)
        end

        instance = selection.first
        unless instance.is_a?(Sketchup::ComponentInstance)
          return Result.new(error_code: :no_selection)
        end

        definition = instance.definition
        unless cabinet_definition?(definition)
          return Result.new(error_code: :not_cabinet)
        end

        Result.new(instance: instance, definition: definition)
      end
      private_class_method :selected_cabinet_instance

      def cabinet_definition?(definition)
        return false unless definition&.valid?

        dict = definition.attribute_dictionary(DICTIONARY_NAME)
        return false unless dict

        type = dict[TYPE_KEY]
        return false if type && type != TYPE_VALUE

        params_json = dict[PARAMS_JSON_KEY]
        params_json.is_a?(String) && !params_json.empty?
      end
      private_class_method :cabinet_definition?

      def build_definition_key(params)
        json = AICabinets::Ops::ParamsSchema.canonical_json(params, cabinet_type: TYPE_VALUE)
        digest = Digest::SHA256.hexdigest(json)
        [digest, json]
      end
      private_class_method :build_definition_key

      def ensure_definition_for_scope(instance, scope)
        case scope
        when 'instance'
          instance.make_unique
          instance.definition
        when 'all'
          instance.definition
        else
          raise ArgumentError, "Unsupported scope: #{scope}"
        end
      end
      private_class_method :ensure_definition_for_scope

      def rebuild_definition!(definition, params)
        remove_owned_entities(definition.entities)
        AICabinets::Generator::UpperCabinet.build!(parent: definition, params_mm: params)
      end
      private_class_method :rebuild_definition!

      def remove_owned_entities(entities)
        entities.to_a.each do |entity|
          next unless cabinet_owned_entity?(entity)

          entity.erase! if entity.valid?
        end
      end
      private_class_method :remove_owned_entities

      def cabinet_owned_entity?(entity)
        return false unless entity&.valid?
        return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        layer = entity.respond_to?(:layer) ? entity.layer : nil
        return false unless layer
        return false if layer.respond_to?(:valid?) && !layer.valid?

        cabinet_owned_tag?(layer)
      end
      private_class_method :cabinet_owned_entity?

      def cabinet_owned_tag?(layer)
        layer_name = layer_name_for(layer)
        category = tag_category_for(layer)

        return false if wrapper_tag_name?(layer_name, category)

        return true if layer_name.start_with?(OWNED_TAG_PREFIX)
        return true unless category.empty?

        false
      end
      private_class_method :cabinet_owned_tag?

      def wrapper_tag_name?(name, category)
        return true if name == WRAPPER_TAG_NAME
        return true if name == AICabinets::Tags::CABINET_TAG_NAME &&
                       category == AICabinets::Tags::CABINET_TAG_NAME
        return true if name == AICabinets::Tags::CABINET_TAG_COLLISION_NAME &&
                       category == AICabinets::Tags::CABINET_TAG_NAME

        false
      end
      private_class_method :wrapper_tag_name?

      def layer_name_for(layer)
        return '' unless layer.respond_to?(:name)

        name = layer.name
        name.is_a?(String) ? name : name.to_s
      end
      private_class_method :layer_name_for

      def tag_category_for(layer)
        return '' unless layer.respond_to?(:get_attribute)

        value = layer.get_attribute(
          AICabinets::Tags::TAG_DICTIONARY,
          AICabinets::Tags::TAG_CATEGORY_KEY
        )
        return value if value.is_a?(String)

        value.to_s
      rescue StandardError
        ''
      end
      private_class_method :tag_category_for

      def assign_definition_attributes(definition, def_key, params_json)
        definition.set_attribute(DICTIONARY_NAME, SCHEMA_VERSION_KEY, SCHEMA_VERSION)
        definition.set_attribute(DICTIONARY_NAME, TYPE_KEY, TYPE_VALUE)
        definition.set_attribute(DICTIONARY_NAME, DEF_KEY, def_key)
        definition.set_attribute(DICTIONARY_NAME, PARAMS_JSON_KEY, params_json)
      end
      private_class_method :assign_definition_attributes

      def ensure_instance_selected(model, instance)
        selection = model.selection
        return unless selection

        selection.clear
        selection.add(instance) if instance&.valid?
      end
      private_class_method :ensure_instance_selected

      def build_selection_error(code)
        case code
        when :no_selection
          { ok: false, error: { code: 'no_selection', message: 'Select one AI Cabinets upper cabinet to edit.' } }
        when :not_cabinet
          { ok: false, error: { code: 'not_cabinet', message: 'The selected object is not an AI Cabinets upper cabinet.' } }
        else
          { ok: false, error: { code: 'unknown_error', message: 'Unable to edit the selected cabinet due to an unexpected error.' } }
        end
      end
      private_class_method :build_selection_error
    end
  end
end
