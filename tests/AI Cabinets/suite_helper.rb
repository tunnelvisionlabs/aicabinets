# frozen_string_literal: true

# TestUp helpers shared across the AI Cabinets suite.
module AICabinetsTestHelper
  TOL = 1e-3.inch

  # Wraps the given block in a single undoable SketchUp operation.
  #
  # @param operation_name [String]
  # @yieldparam model [Sketchup::Model]
  # @raise [ArgumentError] if nested operations are attempted
  def with_undo(operation_name = 'AI Cabinets Test')
    raise ArgumentError, 'with_undo does not support nested operations' if @operation_open

    model = Sketchup.active_model
    raise 'No active model available' unless model

    started = false
    @operation_open = true
    begin
      model.start_operation(operation_name, true)
      started = true
      result = yield(model)
      model.commit_operation
      result
    rescue Exception => exception
      model.abort_operation if started
      raise exception
    ensure
      @operation_open = false
    end
  end

  # Resets the active model to a blank state and clears selection.
  def clean_model!
    with_undo('Reset Model') do |model|
      model.selection.clear
      model.active_entities.clear!
      model.definitions.purge_unused

      tags_or_layers = if model.respond_to?(:tags)
                         candidate = model.tags
                         candidate.respond_to?(:purge_unused) ? candidate : model.layers
                       else
                         model.layers
                       end
      tags_or_layers.purge_unused

      model.materials.purge_unused

      styles = model.styles
      if styles.respond_to?(:purge_unused)
        styles.purge_unused
      elsif styles.respond_to?(:remove_unused)
        # Older SketchUp releases exposed remove_unused instead of purge_unused.
        styles.remove_unused
      end
      nil
    end
  end

  # Uses the shared tolerance to compare numeric values.
  # The helper keeps tolerance centralized so geometry checks stay consistent.
  #
  # @param test_case [TestUp::TestCase]
  # @param expected [Numeric]
  # @param actual [Numeric]
  # @param tolerance [Numeric]
  def assert_within_tolerance(test_case, expected, actual, tolerance = TOL)
    test_case.assert_in_delta(expected, actual, tolerance)
  end

  # Returns the local bounding box for the provided definition or instance.
  #
  # @param definition_or_instance [Sketchup::ComponentDefinition,
  #   Sketchup::ComponentInstance, Sketchup::Group]
  # @return [Geom::BoundingBox]
  def bbox_local_of(definition_or_instance)
    case definition_or_instance
    when Sketchup::ComponentDefinition
      definition_or_instance.bounds
    when Sketchup::ComponentInstance, Sketchup::Group
      definition_or_instance.definition.bounds
    else
      parent =
        definition_or_instance.respond_to?(:parent) ? definition_or_instance.parent : nil
      if parent.is_a?(Sketchup::ComponentDefinition)
        parent.bounds
      else
        raise ArgumentError, 'bbox_local_of expects a definition or instance'
      end
    end
  end

  # Normalizes a numeric value or SketchUp Length to millimeters.
  #
  # @param value_or_length [Numeric, Length]
  # @return [Float]
  def mm(value_or_length)
    case value_or_length
    when Sketchup::Length
      value_or_length.to_mm
    when Numeric
      value_or_length.to_f
    else
      raise ArgumentError, 'mm expects a Numeric or Length value'
    end
  end

  # Collects all raw edges and faces within the provided entities collection,
  # recursing into nested groups and component instances.
  #
  # @param entities [Sketchup::Entities]
  # @param visited [Hash]
  # @return [Array<Sketchup::Drawingelement>]
  def collect_raw_geometry(entities, visited = {})
    geometry = []
    entities.each do |entity|
      next unless entity.valid?

      case entity
      when Sketchup::Edge, Sketchup::Face
        geometry << entity
      when Sketchup::Group
        geometry.concat(collect_raw_geometry(entity.entities, visited))
      when Sketchup::ComponentInstance
        definition = entity.definition
        next unless definition&.valid?

        key = definition.object_id
        next if visited[key]

        visited[key] = true
        geometry.concat(collect_raw_geometry(definition.entities, visited))
      end
    end
    geometry
  end

  # Determines whether the entity resides on the model's default tag.
  #
  # @param entity [Sketchup::Entity]
  # @return [Boolean]
  def default_tag?(entity)
    model = entity.respond_to?(:model) ? entity.model : nil
    return true unless model

    default_collection =
      if model.respond_to?(:tags)
        model.tags
      else
        model.layers
      end

    default_tag =
      if default_collection.respond_to?(:default)
        default_collection.default
      else
        default_collection[0]
      end

    entity.layer == default_tag
  end

  module_function :with_undo, :clean_model!, :assert_within_tolerance,
                  :bbox_local_of, :mm, :collect_raw_geometry, :default_tag?
end
