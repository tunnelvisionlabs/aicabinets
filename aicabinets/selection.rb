# frozen_string_literal: true

module AICabinets
  module Selection
    Result = Struct.new(:status, :instance, :message, keyword_init: true) do
      def valid?
        status == :ok
      end
    end

    module_function

    def require_editable_cabinet(model: nil)
      return invalid_result(:no_model, no_selection_message) unless defined?(Sketchup)

      model ||= Sketchup.active_model

      selection = model_selection(model)
      return invalid_result(:no_selection, no_selection_message) unless selection&.count&.positive?
      return invalid_result(:multiple_selection, multiple_selection_message) unless selection.count == 1

      entity = selection.first
      return invalid_result(:invalid_kind, wrong_kind_message) unless entity.is_a?(Sketchup::ComponentInstance)
      if entity.respond_to?(:locked?) && entity.locked?
        return invalid_result(:locked_entity, locked_entity_message)
      end

      definition = entity.definition
      dictionary = cabinet_metadata_dictionary(definition)
      return invalid_result(:invalid_kind, wrong_kind_message) unless dictionary

      params_json = dictionary[AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY]
      unless params_json.is_a?(String) && !params_json.empty?
        return invalid_result(:invalid_kind, wrong_kind_message)
      end

      Result.new(status: :ok, instance: entity)
    end

    def model_selection(model)
      return unless model.is_a?(Sketchup::Model)

      model.selection
    end
    private_class_method :model_selection

    def cabinet_metadata_dictionary(definition)
      return unless definition.is_a?(Sketchup::ComponentDefinition)
      return unless defined?(AICabinets::Ops::InsertBaseCabinet)

      dictionary_name = AICabinets::Ops::InsertBaseCabinet::DICTIONARY_NAME
      definition.attribute_dictionary(dictionary_name)
    end
    private_class_method :cabinet_metadata_dictionary

    def invalid_result(status, message)
      Result.new(status:, message:)
    end
    private_class_method :invalid_result

    def no_selection_message
      'No cabinet selected. Select exactly one AI Cabinets cabinet to edit.'
    end
    private_class_method :no_selection_message

    def multiple_selection_message
      'Multiple items selected. Select exactly one AI Cabinets cabinet to edit.'
    end
    private_class_method :multiple_selection_message

    def wrong_kind_message
      'The selected item isn’t an AI Cabinets cabinet. Select a cabinet’s top-level component or group.'
    end
    private_class_method :wrong_kind_message

    def locked_entity_message
      'The selected cabinet is locked. Unlock it before editing.'
    end
    private_class_method :locked_entity_message
  end
end
