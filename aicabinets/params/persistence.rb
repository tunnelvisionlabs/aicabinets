# frozen_string_literal: true

require 'json'

require 'aicabinets/version'
require 'aicabinets/defaults'
require 'aicabinets/params/face_frame'

module AICabinets
  module Params
    DICTIONARY_NAME = 'AICabinets'.freeze
    PARAMS_JSON_KEY = 'params_json_mm'.freeze

    module_function

    def read(definition)
      raise ArgumentError, 'definition must be a SketchUp ComponentDefinition' unless
        component_definition?(definition)

      params = read_params_hash(definition)
      migrated, = migrate!(params)
      defaults = AICabinets::Defaults.load_effective_mm
      merged = apply_defaults(migrated, defaults)
      merged[:schema_version] = AICabinets::PARAMS_SCHEMA_VERSION
      merged
    end

    def write!(definition, params)
      raise ArgumentError, 'definition must be a SketchUp ComponentDefinition' unless
        component_definition?(definition)
      raise ArgumentError, 'params must be a Hash' unless params.is_a?(Hash)

      normalized = deep_symbolize_keys(deep_copy(params))
      errors = validate_face_frame(normalized)
      raise ArgumentError, errors.join('; ') if errors.any?

      schema_version = normalized[:schema_version] || normalized['schema_version']
      if schema_version != AICabinets::PARAMS_SCHEMA_VERSION
        raise ArgumentError, "schema_version must be #{AICabinets::PARAMS_SCHEMA_VERSION}"
      end

      existing = deep_symbolize_keys(read_params_hash(definition))
      merged = deep_merge_hash(existing, normalized)
      merged[:schema_version] = schema_version

      json = JSON.generate(canonicalize(merged))
      dictionary = definition.attribute_dictionary(DICTIONARY_NAME, true)
      dictionary[PARAMS_JSON_KEY] = json
      nil
    end

    def migrate!(raw_params)
      warnings = []
      params = raw_params.is_a?(Hash) ? deep_copy(raw_params) : {}
      schema_version = extract_schema_version(params)

      migrate_from_0_to_1!(params, warnings) if schema_version < 1
      migrate_from_1_to_2!(params, warnings) if schema_version < 2
      migrate_from_2_to_current!(params, warnings) if schema_version < AICabinets::PARAMS_SCHEMA_VERSION

      [params, warnings]
    end

    def migrate_from_0_to_1!(params, warnings)
      warnings << 'schema_version missing; assuming v1' unless params.key?(:schema_version) || params.key?('schema_version')
      params[:schema_version] = 1
      params
    end
    private_class_method :migrate_from_0_to_1!

    def migrate_from_1_to_2!(params, _warnings)
      params[:schema_version] = 2
      params
    end
    private_class_method :migrate_from_1_to_2!

    def migrate_from_2_to_current!(params, warnings)
      defaults = Params::FaceFrame.defaults_mm
      face_frame_raw = params[:face_frame] || params['face_frame']
      face_frame, face_errors = Params::FaceFrame.normalize(face_frame_raw, defaults: defaults)
      warnings.concat(face_errors.map { |error| error[:message] }) if face_errors.any?
      params[:face_frame] = face_frame
      params.delete('face_frame')
      params[:schema_version] = AICabinets::PARAMS_SCHEMA_VERSION
      params
    end
    private_class_method :migrate_from_2_to_current!

    def apply_defaults(params, defaults)
      merged = deep_copy(params)
      base_defaults = defaults[:cabinet_base] || defaults['cabinet_base'] || {}
      base_defaults.each do |key, value|
        next if merged.key?(key) || merged.key?(key.to_s)

        merged[key.to_sym] = deep_copy(value)
      end

      if merged[:face_frame].nil?
        merged[:face_frame] = Params::FaceFrame.defaults_mm
      else
        face_frame_defaults = defaults[:face_frame] || defaults['face_frame'] || Params::FaceFrame.defaults_mm
        normalized, = Params::FaceFrame.normalize(merged[:face_frame], defaults: face_frame_defaults)
        merged[:face_frame] = normalized
      end

      merged
    end
    private_class_method :apply_defaults

    def validate_face_frame(params)
      face_frame = params[:face_frame] || params['face_frame']
      defaults = Params::FaceFrame.defaults_mm
      normalized, normalize_errors = Params::FaceFrame.normalize(face_frame, defaults: defaults)
      validation_result = Params::FaceFrame.validate(normalized)
      params[:face_frame] = normalized

      errors = []
      errors.concat(normalize_errors.map { |error| error[:message] })
      errors.concat(validation_result[:errors].map { |error| error[:message] }) unless validation_result[:ok]
      errors
    end
    private_class_method :validate_face_frame

    def read_params_hash(definition)
      dictionary = definition.attribute_dictionary(DICTIONARY_NAME)
      return {} unless dictionary

      json = dictionary[PARAMS_JSON_KEY]
      return {} unless json.is_a?(String) && !json.empty?

      JSON.parse(json, symbolize_names: true)
    rescue JSON::ParserError
      {}
    end
    private_class_method :read_params_hash

    def extract_schema_version(params)
      value = params[:schema_version] || params['schema_version']
      return value.to_i if value.respond_to?(:to_int)
      return value.to_i if value.is_a?(String) && value =~ /^\d+$/

      0
    end
    private_class_method :extract_schema_version

    def component_definition?(definition)
      return false unless defined?(Sketchup)

      definition.is_a?(Sketchup::ComponentDefinition)
    end
    private_class_method :component_definition?

    def deep_symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, element), memo|
          symbolized =
            case key
            when Symbol
              key
            else
              key.to_s.to_sym
            end
          memo[symbolized] = deep_symbolize_keys(element)
        end
      when Array
        value.map { |item| deep_symbolize_keys(item) }
      else
        value
      end
    end
    private_class_method :deep_symbolize_keys

    def deep_merge_hash(original, updates)
      base = original.is_a?(Hash) ? deep_copy(original) : {}
      return base unless updates.is_a?(Hash)

      updates.each do |key, value|
        if base.key?(key) && base[key].is_a?(Hash) && value.is_a?(Hash)
          base[key] = deep_merge_hash(base[key], value)
        else
          base[key] = deep_copy(value)
        end
      end

      base
    end
    private_class_method :deep_merge_hash

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
