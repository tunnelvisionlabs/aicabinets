# frozen_string_literal: true

require 'json'
require 'digest'
require 'sketchup.rb'

require 'aicabinets/version'
require 'aicabinets/defaults'
require 'aicabinets/params_sanitizer'
require 'aicabinets/face_frame'
require 'aicabinets/solver/front_layout'

Sketchup.require('aicabinets/generator/carcass')
Sketchup.require('aicabinets/ops/tags')
Sketchup.require('aicabinets/tags')

module AICabinets
  module Ops
    module InsertBaseCabinet
      module_function

      OPERATION_NAME = 'AI Cabinets — Insert Base Cabinet'
      DICTIONARY_NAME = 'AICabinets'
      SCHEMA_VERSION = AICabinets::PARAMS_SCHEMA_VERSION
      SCHEMA_VERSION_KEY = 'schema_version'
      TYPE_KEY = 'type'
      TYPE_VALUE = 'base'
      LEGACY_TYPE_VALUES = [TYPE_VALUE, 'base_cabinet'].freeze
      DEF_KEY = 'def_key'
      LEGACY_FINGERPRINT_KEY = 'fingerprint'
      PARAMS_JSON_KEY = 'params_json_mm'
      WRAPPER_TAG_NAME = AICabinets::Tags::LEGACY_CABINET_TAG_NAME

      PREFERRED_WRAPPER_TAG_NAME = AICabinets::Tags::CABINET_TAG_NAME
      CABINET_TAG_COLLISION_NAME = AICabinets::Tags::CABINET_TAG_COLLISION_NAME

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

      FRONT_OPTIONS = %w[empty doors_left doors_right doors_double].freeze

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
          if params_mm[key] <= 0
            raise ArgumentError, "Parameter #{key} must be greater than 0 mm"
          end
        end

        NON_NEGATIVE_KEYS.each do |key|
          if params_mm[key] < 0
            raise ArgumentError, "Parameter #{key} must be at least 0 mm"
          end
        end

        if params_mm[:panel_thickness_mm] >= params_mm[:width_mm]
          raise ArgumentError, 'panel_thickness_mm must be less than width_mm'
        end

        if params_mm[:toe_kick_height_mm] >= params_mm[:height_mm]
          raise ArgumentError, 'toe_kick_height_mm must be less than height_mm'
        end

        if params_mm[:toe_kick_depth_mm] >= params_mm[:depth_mm]
          raise ArgumentError, 'toe_kick_depth_mm must be less than depth_mm'
        end

        copy = deep_copy(params_mm)

        defaults = AICabinets::Defaults.load_effective_mm
        AICabinets::ParamsSanitizer.sanitize!(copy, global_defaults: defaults)

        face_frame_defaults = defaults[:face_frame] || defaults['face_frame'] || AICabinets::FaceFrame.defaults_mm
        face_frame_raw = copy[:face_frame] || copy['face_frame']
        face_frame, face_frame_errors = AICabinets::FaceFrame.normalize(face_frame_raw, defaults: face_frame_defaults)
        face_frame_errors = face_frame_errors.map { |error| format_face_frame_error(error) }.compact

        copy[:face_frame] = face_frame
        copy.delete('face_frame')
        copy[:schema_version] = SCHEMA_VERSION

        opening_mm = opening_from_params(copy)
        validation_result = AICabinets::FaceFrame.validate(face_frame, opening_mm: opening_mm)
        unless validation_result[:ok]
          face_frame_errors.concat(validation_result[:errors].map { |error| format_face_frame_error(error) })
        end

        face_frame_errors.compact!
        face_frame_errors.uniq!
        raise ArgumentError, face_frame_errors.join('; ') if face_frame_errors.any?

        thickness_value =
          if params_mm.key?(:toe_kick_thickness_mm)
            value = params_mm[:toe_kick_thickness_mm]
            unless value.is_a?(Numeric) && value.finite?
              raise ArgumentError, 'toe_kick_thickness_mm must be a finite number in millimeters'
            end
            value.to_f
          else
            params_mm[:panel_thickness_mm].to_f
          end
        copy[:toe_kick_thickness_mm] = thickness_value

        if copy.key?(:front)
          front_value = copy[:front]
          front_string =
            case front_value
            when NilClass
              nil
            when Symbol
              front_value.to_s
            else
              String(front_value)
            end

          if front_string && !FRONT_OPTIONS.include?(front_string)
            raise ArgumentError, 'front must be one of: empty, doors_left, doors_right, doors_double'
          end

          copy[:front] = front_string if front_string
        end

        opening_mm = opening_from_params(copy)
        layout_result = AICabinets::Solver::FrontLayout.solve(opening_mm: opening_mm, params: copy)
        copy[:front_layout] = layout_result[:front_layout]
        if layout_result[:warnings].any?
          copy[:front_layout_warnings] = layout_result[:warnings]
        else
          copy.delete(:front_layout_warnings)
        end

        copy
      end
      private_class_method :validate_params!

      def format_face_frame_error(error)
        return error.to_s if error.is_a?(String)
        return String(error) unless error.is_a?(Hash)

        field = error[:field] || error['field']
        message = error[:message] || error['message']
        return String(message) unless field && !field.to_s.empty?

        "#{field}: #{message}"
      end
      private_class_method :format_face_frame_error

      def opening_from_params(params)
        return {} unless params.is_a?(Hash)

        face_frame = params[:face_frame]
        return {} unless face_frame.is_a?(Hash)

        {
          x: face_frame[:stile_left_mm].to_f,
          z: face_frame[:rail_bottom_mm].to_f,
          w: params[:width_mm].to_f - face_frame[:stile_left_mm].to_f - face_frame[:stile_right_mm].to_f,
          h: params[:height_mm].to_f - face_frame[:rail_top_mm].to_f - face_frame[:rail_bottom_mm].to_f
        }
      end
      private_class_method :opening_from_params

      def build_definition_key(params)
        canonical = canonicalize(params)
        json = JSON.generate(canonical)
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
          next if type && !LEGACY_TYPE_VALUES.include?(type)

          stored_def_key = dict[DEF_KEY]
          legacy_fingerprint = dict[LEGACY_FINGERPRINT_KEY]
          next unless stored_def_key == def_key || legacy_fingerprint == def_key

          return definition
        end

        nil
      end
      private_class_method :find_definition

      def create_definition(model, params, def_key, params_json)
        definitions = model.definitions
        definition = definitions.add('AI Cabinets Base Cabinet')
        assign_definition_attributes(definition, def_key, params_json)
        AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params)
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
        definition.set_attribute(DICTIONARY_NAME, LEGACY_FINGERPRINT_KEY, def_key)
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
