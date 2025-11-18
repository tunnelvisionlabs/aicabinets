# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/metadata')
Sketchup.require('aicabinets/generator/fronts')

module AICabinets
  module BOM
    module_function

    DICTIONARY_NAME = AICabinets::Metadata::DICTIONARY_NAME
    FRONT_TAG_NAME = AICabinets::Generator::Fronts::FRONTS_TAG_NAME

    def parts_for(definition:)
      normalized = normalize_definition(definition)
      return [] unless normalized

      normalized.entities.grep(Sketchup::Group).filter_map do |group|
        next unless valid_part?(group)

        part_definition = group.definition
        dictionary = part_definition.attribute_dictionary(DICTIONARY_NAME)
        next unless dictionary

        part_type = dictionary['part_type']
        joint_type = dictionary['joint_type']
        panel_type = dictionary['panel_type']
        schema_version = dictionary['schema_version']
        next unless part_type && joint_type && panel_type && schema_version

        {
          part_type: part_type.to_sym,
          joint_type: joint_type.to_s,
          panel_type: panel_type.to_s
        }
      end
    end

    def normalize_definition(target)
      definition_class = Sketchup.const_defined?(:ComponentDefinition) ? Sketchup::ComponentDefinition : nil
      instance_class = Sketchup.const_defined?(:ComponentInstance) ? Sketchup::ComponentInstance : nil

      case target
      when definition_class
        target.valid? ? target : nil
      when instance_class
        return nil unless target.valid?

        target.definition if target.respond_to?(:definition)
      else
        nil
      end
    end
    private_class_method :normalize_definition

    def valid_part?(group)
      return false unless group&.valid?
      return false unless group.respond_to?(:layer)

      layer = group.layer
      return false unless layer.respond_to?(:name)
      return false unless layer.name == FRONT_TAG_NAME

      definition = group.definition if group.respond_to?(:definition)
      definition&.valid?
    rescue StandardError
      false
    end
    private_class_method :valid_part?
  end
end
