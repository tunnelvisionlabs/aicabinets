# frozen_string_literal: true

require 'json'
require 'digest'
require 'sketchup.rb'

Sketchup.require('aicabinets/generator/carcass')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

module AICabinets
  module Ops
    module EditBaseCabinet
      module_function

      OPERATION_NAME = 'AI Cabinets — Edit Base Cabinet'
      VALID_SCOPES = %w[instance all].freeze

      DICTIONARY_NAME = InsertBaseCabinet::DICTIONARY_NAME
      SCHEMA_VERSION_KEY = InsertBaseCabinet::SCHEMA_VERSION_KEY
      SCHEMA_VERSION = InsertBaseCabinet::SCHEMA_VERSION
      TYPE_KEY = InsertBaseCabinet::TYPE_KEY
      TYPE_VALUE = InsertBaseCabinet::TYPE_VALUE
      LEGACY_TYPE_VALUES = InsertBaseCabinet::LEGACY_TYPE_VALUES
      DEF_KEY = InsertBaseCabinet::DEF_KEY
      LEGACY_FINGERPRINT_KEY = InsertBaseCabinet::LEGACY_FINGERPRINT_KEY
      PARAMS_JSON_KEY = InsertBaseCabinet::PARAMS_JSON_KEY

      Result = Struct.new(:instance, :error_code, keyword_init: true)
      private_constant :Result

      def apply_to_selection!(model:, params_mm:, scope: 'instance')
        validate_model!(model)

        scope_value = normalize_scope(scope)
        params = validate_params!(params_mm)

        selection_result = selected_cabinet_instance(model)
        unless selection_result.error_code.nil?
          return build_selection_error(selection_result.error_code)
        end

        instance = selection_result.instance
        definition = instance&.definition
        unless definition&.valid?
          return build_selection_error(:not_cabinet)
        end

        def_key, params_json = build_definition_key(params)
        if definition.get_attribute(DICTIONARY_NAME, DEF_KEY) == def_key &&
           definition.get_attribute(DICTIONARY_NAME, PARAMS_JSON_KEY) == params_json
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
        warn("AI Cabinets: Unexpected error while editing cabinet: #{e.message}")
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

        InsertBaseCabinet.__send__(:validate_params!, params_mm)
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

        Result.new(instance: instance)
      end
      private_class_method :selected_cabinet_instance

      def cabinet_definition?(definition)
        return false unless definition&.valid?

        dict = definition.attribute_dictionary(DICTIONARY_NAME)
        return false unless dict

        type = dict[TYPE_KEY]
        return false if type && !LEGACY_TYPE_VALUES.include?(type)

        params_json = dict[PARAMS_JSON_KEY]
        params_json.is_a?(String) && !params_json.empty?
      end
      private_class_method :cabinet_definition?

      def build_definition_key(params)
        canonical = canonicalize(params)
        json = JSON.generate(canonical)
        digest = Digest::SHA256.hexdigest(json)
        [digest, json]
      end
      private_class_method :build_definition_key

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
        entities = definition.entities
        if entities.respond_to?(:clear!)
          entities.clear!
        else
          entities.to_a.each do |entity|
            entity.erase! if entity.valid?
          end
        end
        AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params)
      end
      private_class_method :rebuild_definition!

      def assign_definition_attributes(definition, def_key, params_json)
        definition.set_attribute(DICTIONARY_NAME, SCHEMA_VERSION_KEY, SCHEMA_VERSION)
        definition.set_attribute(DICTIONARY_NAME, TYPE_KEY, TYPE_VALUE)
        definition.set_attribute(DICTIONARY_NAME, DEF_KEY, def_key)
        definition.set_attribute(DICTIONARY_NAME, LEGACY_FINGERPRINT_KEY, def_key)
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
          { ok: false, error: { code: 'no_selection', message: 'Select one AI Cabinets base cabinet to edit.' } }
        when :not_cabinet
          { ok: false, error: { code: 'not_cabinet', message: 'The selected object is not an AI Cabinets base cabinet.' } }
        else
          { ok: false, error: { code: 'no_selection', message: 'Select one AI Cabinets base cabinet to edit.' } }
        end
      end
      private_class_method :build_selection_error
    end
  end
end
