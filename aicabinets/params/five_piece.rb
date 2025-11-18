# frozen_string_literal: true

unless defined?(AICabinets::ValidationError)
  if defined?(Sketchup)
    Sketchup.require('aicabinets/validation_error')
  else
    require File.expand_path('../validation_error', __dir__)
  end
end

module AICabinets
  module Params
    module FivePiece
      module_function

      DICTIONARY_NAME = 'AICabinets'.freeze
      STORAGE_PREFIX = 'five_piece:'.freeze
      DOOR_TYPE = 'five_piece'.freeze
      JOINT_TYPES = %w[cope_stick miter].freeze
      PANEL_STYLES = %w[flat raised reverse_raised].freeze
      MIN_STILE_WIDTH_BY_JOINT_MM = {
        'cope_stick' => 50.0,
        'miter' => 55.0
      }.freeze
      MIN_CLEARANCE_PER_SIDE_MM = 0.0
      MAX_CLEARANCE_PER_SIDE_MM = 6.0
      GROOVE_DEPTH_BUFFER_MM = 12.0

      DEFAULTS = {
        door_type: DOOR_TYPE,
        joint_type: 'cope_stick',
        inside_profile_id: 'square_inside',
        stile_width_mm: 57.0,
        rail_width_mm: nil,
        panel_style: 'flat',
        panel_thickness_mm: 9.5,
        groove_depth_mm: 11.0,
        groove_width_mm: nil,
        panel_clearance_per_side_mm: 3.0,
        panel_cove_radius_mm: 12.0,
        door_thickness_mm: 19.0,
        frame_material_id: nil,
        panel_material_id: nil
      }.freeze

      NUMERIC_KEYS = %i[
        stile_width_mm
        rail_width_mm
        panel_cove_radius_mm
        panel_thickness_mm
        groove_depth_mm
        groove_width_mm
        panel_clearance_per_side_mm
        door_thickness_mm
      ].freeze

      STRING_KEYS = %i[
        door_type
        joint_type
        inside_profile_id
        panel_style
        frame_material_id
        panel_material_id
      ].freeze

      KEY_ALIASES = {
        stile_width: :stile_width_mm,
        rail_width: :rail_width_mm,
        panel_thickness: :panel_thickness_mm,
        groove_depth: :groove_depth_mm,
        groove_width: :groove_width_mm,
        panel_clearance_per_side: :panel_clearance_per_side_mm
      }.freeze

      RECOGNIZED_KEYS = DEFAULTS.keys.freeze

      def defaults
        params = duplicate_defaults
        finalize_fallbacks!(params)
        params
      end

      def coerce(raw: {})
        params = duplicate_defaults
        unknown = {}
        hash = raw.is_a?(Hash) ? raw : {}

        hash.each do |key, value|
          normalized = normalize_key(key)
          if normalized
            params[normalized] = coerce_value(normalized, value)
          else
            unknown_key = normalize_unknown_key(key)
            unknown[unknown_key] = value
          end
        end

        finalize_fallbacks!(params)
        params.merge!(unknown)
        params
      end

      def validate!(params: {})
        coerced = coerce(raw: params)
        errors = []

        unless coerced[:door_type] == DOOR_TYPE
          errors << 'door_type must be "five_piece" when storing five-piece door params'
        end

        joint_type = coerced[:joint_type]
        unless JOINT_TYPES.include?(joint_type)
          errors << "joint_type must be one of: #{JOINT_TYPES.join(', ')}"
        end

        panel_style = coerced[:panel_style]
        unless PANEL_STYLES.include?(panel_style.to_s)
          errors << "panel_style must be one of: #{PANEL_STYLES.join(', ')}"
        end

        inside_profile_id = coerced[:inside_profile_id]
        if inside_profile_id.nil? || inside_profile_id.to_s.empty?
          errors << 'inside_profile_id must be provided'
        end

        validate_numeric!(coerced, errors)
        validate_clearances!(coerced, errors)
        validate_stile_dimensions!(coerced, joint_type, errors)
        validate_panel_vs_groove!(coerced, errors)
        validate_materials!(coerced, errors)

        raise AICabinets::ValidationError, errors unless errors.empty?

        coerced
      end

      def read(definition)
        definition = ensure_definition(definition)
        dictionary = definition.attribute_dictionary(DICTIONARY_NAME)
        return defaults unless dictionary

        raw = {}
        dictionary.each_pair do |key, value|
          next unless key.respond_to?(:to_s)

          key_string = key.to_s
          next unless key_string.start_with?(STORAGE_PREFIX)

          param_key = key_string.delete_prefix(STORAGE_PREFIX).to_sym
          raw[param_key] = value
        end

        coerce(raw: raw)
      end

      def write!(definition_or_instance, params:, scope: :definition)
        sanitized = validate!(params: params)
        definition =
          case scope
          when :definition
            ensure_definition(definition_or_instance)
          when :instance
            ensure_unique_definition(definition_or_instance)
          else
            raise ArgumentError, "Unsupported scope: #{scope.inspect}"
          end

        sanitized.each do |key, value|
          storage_key = storage_key_for(key)
          if value.nil?
            definition.delete_attribute(DICTIONARY_NAME, storage_key)
          else
            definition.set_attribute(DICTIONARY_NAME, storage_key, prepare_value_for_storage(value))
          end
        end

        sanitized
      end

      def storage_key_for(param_key)
        "#{STORAGE_PREFIX}#{param_key}"
      end
      private :storage_key_for

      def prepare_value_for_storage(value)
        value.is_a?(Numeric) ? value.to_f : value
      end
      private :prepare_value_for_storage

      def duplicate_defaults
        DEFAULTS.each_with_object({}) do |(key, value), memo|
          memo[key] = duplicate_value(value)
        end
      end
      private :duplicate_defaults

      def duplicate_value(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), memo| memo[k] = duplicate_value(v) }
        when Array
          value.map { |item| duplicate_value(item) }
        else
          value
        end
      end
      private :duplicate_value

      def normalize_key(key)
        return nil unless key.respond_to?(:to_s)

        key_string = key.to_s
        return nil if key_string.empty?

        symbol = key_string.to_sym
        normalized = KEY_ALIASES.fetch(symbol, symbol)
        return normalized if RECOGNIZED_KEYS.include?(normalized)

        underscored = underscore_key(key_string)
        normalized = KEY_ALIASES.fetch(underscored, underscored)
        return normalized if RECOGNIZED_KEYS.include?(normalized)

        nil
      end
      private :normalize_key

      def normalize_unknown_key(key)
        key.respond_to?(:to_sym) ? key.to_sym : key
      end
      private :normalize_unknown_key

      def underscore_key(string)
        return string.to_sym if string !~ /[A-Z]/

        underscored = string.gsub(/([A-Z]+)/) { "_#{Regexp.last_match(1).downcase}" }
        underscored.sub(/^_/, '').to_sym
      end
      private :underscore_key

      def coerce_value(key, value)
        if NUMERIC_KEYS.include?(key)
          coerce_numeric(value)
        elsif STRING_KEYS.include?(key)
          coerce_string(value)
        else
          value
        end
      end
      private :coerce_value

      def coerce_numeric(value)
        case value
        when nil
          nil
        when Numeric
          value.to_f
        when String
          stripped = value.strip
          return nil if stripped.empty?

          Float(stripped)
        else
          value
        end
      rescue ArgumentError, TypeError
        value
      end
      private :coerce_numeric

      def coerce_string(value)
        case value
        when nil
          nil
        when String
          stripped = value.strip
          stripped.empty? ? nil : stripped
        else
          value.to_s
        end
      end
      private :coerce_string

      def finalize_fallbacks!(params)
        params[:door_type] ||= DOOR_TYPE
        params[:joint_type] ||= DEFAULTS[:joint_type]
        params[:panel_clearance_per_side_mm] ||= DEFAULTS[:panel_clearance_per_side_mm]

        if params[:rail_width_mm].nil?
          params[:rail_width_mm] = params[:stile_width_mm]
        end

        params
      end
      private :finalize_fallbacks!

      def validate_numeric!(params, errors)
        [:stile_width_mm, :panel_thickness_mm, :groove_depth_mm, :panel_clearance_per_side_mm, :rail_width_mm].each do |key|
          value = params[key]
          unless value.is_a?(Numeric)
            errors << "#{key} must be a numeric value in millimeters"
            next
          end

          if value <= 0 && key != :panel_clearance_per_side_mm
            errors << "#{key} must be greater than zero"
          end

          if key == :rail_width_mm && value < params[:stile_width_mm].to_f * 0.5
            errors << 'rail_width_mm must be at least half of stile_width_mm'
          end
        end

        clearance = params[:panel_clearance_per_side_mm]
        if clearance.is_a?(Numeric)
          if clearance < MIN_CLEARANCE_PER_SIDE_MM
            errors << "panel_clearance_per_side_mm cannot be negative"
          elsif clearance > MAX_CLEARANCE_PER_SIDE_MM
            errors << "panel_clearance_per_side_mm exceeds the supported range"
          end
        end

        groove_width = params[:groove_width_mm]
        if !groove_width.nil? && !groove_width.is_a?(Numeric)
          errors << 'groove_width_mm must be numeric when provided'
        elsif groove_width.is_a?(Numeric) && groove_width <= 0
          errors << 'groove_width_mm must be greater than zero when provided'
        end
      end
      private :validate_numeric!

      def validate_clearances!(params, errors)
        panel_thickness = params[:panel_thickness_mm]
        clearance = params[:panel_clearance_per_side_mm]

        return unless panel_thickness.is_a?(Numeric) && clearance.is_a?(Numeric)

        if panel_thickness <= clearance
          errors << 'panel_thickness_mm must exceed panel_clearance_per_side_mm'
        end
      end
      private :validate_clearances!

      def validate_stile_dimensions!(params, joint_type, errors)
        stile_width = params[:stile_width_mm]
        groove_depth = params[:groove_depth_mm]

        return unless stile_width.is_a?(Numeric) && groove_depth.is_a?(Numeric) && JOINT_TYPES.include?(joint_type)

        joint_min = MIN_STILE_WIDTH_BY_JOINT_MM.fetch(joint_type)
        groove_min = (groove_depth * 2.0) + GROOVE_DEPTH_BUFFER_MM
        min_width = [joint_min, groove_min].max

        if stile_width < min_width
          errors << format('stile_width_mm %.2f is too small; requires at least %.2f for joint_type %s with groove_depth_mm %.2f',
                           stile_width, min_width, joint_type, groove_depth)
        end
      end
      private :validate_stile_dimensions!

      def validate_panel_vs_groove!(params, errors)
        panel_thickness = params[:panel_thickness_mm]
        clearance = params[:panel_clearance_per_side_mm]
        groove_width = params[:groove_width_mm]

        if groove_width.is_a?(Numeric) && panel_thickness.is_a?(Numeric) && clearance.is_a?(Numeric)
          required_width = panel_thickness + (clearance * 2.0)
          if groove_width < required_width
            errors << format('panel_thickness_mm %.2f with clearance %.2f per side requires groove_width_mm at least %.2f (found %.2f)',
                             panel_thickness, clearance, required_width, groove_width)
          end
        end
      end
      private :validate_panel_vs_groove!

      def validate_materials!(params, errors)
        [:frame_material_id, :panel_material_id].each do |key|
          value = params[key]
          next if value.nil?

          unless value.is_a?(String) && !value.empty?
            errors << "#{key} must be a non-empty String when provided"
          end
        end
      end
      private :validate_materials!

      def ensure_definition(target)
        definition_class = sketchup_class(:ComponentDefinition)
        unless definition_class && target.is_a?(definition_class)
          raise ArgumentError, 'Expected a SketchUp ComponentDefinition'
        end

        unless target.valid?
          raise ArgumentError, 'ComponentDefinition is no longer valid'
        end

        target
      end
      private :ensure_definition

      def ensure_unique_definition(instance)
        instance_class = sketchup_class(:ComponentInstance)
        unless instance_class && instance.is_a?(instance_class)
          raise ArgumentError, 'Expected a SketchUp ComponentInstance for scope: :instance'
        end

        unless instance.valid?
          raise ArgumentError, 'ComponentInstance is no longer valid'
        end

        definition = instance.definition
        raise ArgumentError, 'ComponentInstance has no definition' unless definition

        siblings = definition.instances.select { |other| other.valid? && other != instance }
        if siblings.any? && instance.respond_to?(:make_unique)
          instance.make_unique
          definition = instance.definition
        end

        ensure_definition(definition)
      end
      private :ensure_unique_definition

      def sketchup_class(name)
        return nil unless defined?(Sketchup)

        Sketchup.const_get(name)
      rescue NameError
        nil
      end
      private :sketchup_class
    end
  end
end
