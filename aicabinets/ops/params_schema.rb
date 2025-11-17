# frozen_string_literal: true

require 'digest'
require 'json'

module AICabinets
  module Ops
    module ParamsSchema
      module_function

      DICTIONARY_NAME = 'AICabinets'
      PARAMS_JSON_KEY = 'params_json_mm'
      CURRENT_VERSION = 2
      DEFAULT_CABINET_TYPE = 'base'
      def parse_json(json)
        return nil unless json.is_a?(String) && !json.empty?

        JSON.parse(json)
      rescue JSON::ParserError
        nil
      end

      def canonical_hash(params, cabinet_type: nil)
        upgraded = upgrade_to_v2(params, cabinet_type: cabinet_type)
        canonicalize(upgraded)
      end

      def canonical_json(params, cabinet_type: nil)
        JSON.generate(canonical_hash(params, cabinet_type: cabinet_type))
      end

      def digest(params, cabinet_type: nil)
        Digest::SHA256.hexdigest(canonical_json(params, cabinet_type: cabinet_type))
      end

      def digest_from_json(json, cabinet_type: nil)
        parsed = parse_json(json)
        return nil unless parsed.is_a?(Hash)

        digest(parsed, cabinet_type: cabinet_type)
      end

      def upgrade_to_v2(params, cabinet_type: nil)
        normalized = deep_copy(params || {})
        normalized = stringify_keys(normalized)

        normalized['cabinet_type'] = resolve_cabinet_type(normalized, cabinet_type)
        normalized['schema_version'] = CURRENT_VERSION
        normalized['overlay_mm'] = normalize_length_value(normalized, 'overlay_mm', 0.0)

        ensure_style_block!(normalized)
      end

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, element), memo|
            memo[key.to_s] = stringify_keys(element)
          end
        when Array
          value.map { |element| stringify_keys(element) }
        else
          value
        end
      end
      private_class_method :stringify_keys

      def canonicalize(value)
        case value
        when Hash
          value.keys.sort.map do |key|
            [key.to_s, canonicalize(value[key])]
          end.to_h
        when Array
          value.map { |element| canonicalize(element) }
        else
          value
        end
      end
      private_class_method :canonicalize

      def deep_copy(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, element), memo| memo[key] = deep_copy(element) }
        when Array
          value.map { |element| deep_copy(element) }
        else
          value
        end
      end
      private_class_method :deep_copy

      def resolve_cabinet_type(container, override)
        return override.to_s.strip unless override.to_s.strip.empty?

        stored = container['cabinet_type']
        return stored.to_s unless stored.nil? || stored.to_s.strip.empty?

        DEFAULT_CABINET_TYPE
      end
      private_class_method :resolve_cabinet_type

      def normalize_length_value(container, key, default)
        return container[key] if container.key?(key)

        default
      end
      private_class_method :normalize_length_value

      def ensure_style_block!(container)
        style_key = container['cabinet_type'] || DEFAULT_CABINET_TYPE
        raw_style = container[style_key]
        container[style_key] = normalize_style(raw_style)

        container
      end
      private_class_method :ensure_style_block!

      def normalize_style(raw_style)
        case raw_style
        when Hash
          stringify_keys(raw_style)
        when nil
          {}
        else
          { 'legacy_value' => raw_style }
        end
      end
      private_class_method :normalize_style
    end
  end
end
