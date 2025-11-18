# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/tags')
Sketchup.require('aicabinets/generator/fronts')

module AICabinets
  module Metadata
    module_function

    DICTIONARY_NAME = 'AICabinets'.freeze
    SCHEMA_VERSION = 1

    STILE_NAMES = ['Door-Stile-L', 'Door-Stile-R'].freeze
    RAIL_NAMES = ['Door-Rail-Bottom', 'Door-Rail-Top'].freeze
    PANEL_NAME = 'Door-Panel'.freeze

    def write_five_piece!(definition:, params:, parts:)
      normalized_definition = normalize_definition(definition)
      return { applied: false, warnings: ['Invalid definition'] } unless normalized_definition

      joint_type = string_param(params, :joint_type)
      panel_type = string_param(params, :panel_style)

      return { applied: false, warnings: ['Missing joint_type or panel_style'] } unless joint_type && panel_type

      parts ||= {}
      stiles = Array(parts[:stiles]).compact
      rails = Array(parts[:rails]).compact
      panel = parts[:panel]

      return { applied: false, warnings: ['No five-piece parts provided'] } if stiles.empty? && rails.empty? && panel.nil?

      model = normalized_definition.model
      tag = AICabinets::Tags.ensure_fronts!(model: model) if model

      apply_metadata(stiles, part_type: 'stile', joint_type: joint_type, panel_type: panel_type, names: STILE_NAMES, tag: tag)
      apply_metadata(rails, part_type: 'rail', joint_type: joint_type, panel_type: panel_type, names: RAIL_NAMES, tag: tag)
      apply_metadata(Array(panel).compact, part_type: 'panel', joint_type: joint_type, panel_type: panel_type, names: [PANEL_NAME], tag: tag)

      { applied: true, warnings: [] }
    rescue StandardError => error
      { applied: false, warnings: [error.message] }
    end

    def string_param(params, key)
      return unless params.respond_to?(:[])

      value = params[key]
      value = params[key.to_s] if value.nil? && key.respond_to?(:to_s)
      return unless value

      value.to_s
    end
    private_class_method :string_param

    def normalize_definition(target)
      definition_class = Sketchup.const_defined?(:ComponentDefinition) ? Sketchup::ComponentDefinition : nil
      instance_class = Sketchup.const_defined?(:ComponentInstance) ? Sketchup::ComponentInstance : nil

      case target
      when definition_class
        target.valid? ? target : nil
      when instance_class
        return nil unless target.valid?

        target.make_unique if target.respond_to?(:make_unique)
        target.definition if target.respond_to?(:definition)
      else
        nil
      end
    end
    private_class_method :normalize_definition

    def apply_metadata(groups, part_type:, joint_type:, panel_type:, names:, tag:)
      groups.each_with_index do |group, index|
        next unless group&.valid?

        definition = group_definition(group)
        next unless definition

        name = names[index] || names.last || default_name_for(part_type)
        apply_names(group, definition, name)
        assign_tag(group, tag)

        dictionary = definition.attribute_dictionary(DICTIONARY_NAME, true)
        dictionary['part_type'] = part_type
        dictionary['joint_type'] = joint_type
        dictionary['panel_type'] = panel_type
        dictionary['schema_version'] = SCHEMA_VERSION
      end
    end
    private_class_method :apply_metadata

    def group_definition(group)
      definition = group.respond_to?(:definition) ? group.definition : nil
      return unless definition&.valid?

      definition
    end
    private_class_method :group_definition

    def default_name_for(part_type)
      "Door-#{part_type.capitalize}"
    end
    private_class_method :default_name_for

    def apply_names(group, definition, name)
      assign_name(group, name)
      assign_name(definition, name)
    end
    private_class_method :apply_names

    def assign_name(entity, name)
      return unless entity.respond_to?(:name=)

      entity.name = name
    rescue StandardError
      nil
    end
    private_class_method :assign_name

    def assign_tag(group, tag)
      return unless group.respond_to?(:layer=)
      return unless tag

      group.layer = tag
    rescue StandardError
      nil
    end
    private_class_method :assign_tag
  end
end
