# frozen_string_literal: true

# TestUp helpers shared across the AI Cabinets suite.
require 'json'
require 'delegate'
require 'fileutils'
module AICabinetsTestHelper
  TOL = 1e-3.inch

  DICTIONARY_NAME = 'AICabinets'
  DEF_KEY_NAME = 'def_key'
  LEGACY_DEF_KEY_NAME = 'fingerprint'
  PARAMS_JSON_KEY = 'params_json_mm'
  CONSOLE_STDOUT_ENV = 'AI_CABINETS_RUBY_CONSOLE_LOG'
  CONSOLE_STDERR_ENV = 'AI_CABINETS_RUBY_CONSOLE_ERR_LOG'

  def self.capture_ruby_console_output
    return unless defined?(TestUp::TESTUP_CONSOLE)

    stdout_target = ENV[CONSOLE_STDOUT_ENV]
    stderr_target = ENV[CONSOLE_STDERR_ENV]
    return unless stdout_target || stderr_target

    loggers = {
      stdout: prepare_console_log(stdout_target),
      stderr: prepare_console_log(stderr_target)
    }

    $stdout = ConsoleTee.new(TestUp::TESTUP_CONSOLE, loggers[:stdout]) if loggers[:stdout]
    $stderr = ConsoleTee.new(TestUp::TESTUP_CONSOLE, loggers[:stderr]) if loggers[:stderr]
  rescue StandardError => error
    warn("[AICabinets] Failed to configure Ruby console capture: #{error.message}")
  end

  def self.prepare_console_log(target_path)
    return unless target_path && !target_path.strip.empty?

    FileUtils.mkdir_p(File.dirname(target_path))
    io = File.open(target_path, 'w', encoding: Encoding::UTF_8)
    io.sync = true if io.respond_to?(:sync=)
    at_exit do
      begin
        io.flush
        io.close unless io.closed?
      rescue StandardError
        # ignore cleanup failures
      end
    end
    io
  end

  class ConsoleTee < SimpleDelegator
    def initialize(primary, secondary)
      super(primary)
      @secondary = secondary
    end

    def write(*args)
      result = __getobj__.write(*args)
      @secondary.write(*args)
      result
    end

    def puts(*args)
      result = __getobj__.puts(*args)
      @secondary.puts(*args)
      result
    end

    def print(*args)
      result = __getobj__.print(*args)
      @secondary.print(*args)
      result
    end

    def flush
      __getobj__.flush if __getobj__.respond_to?(:flush)
      @secondary.flush if @secondary.respond_to?(:flush)
      nil
    end

    def sync=(value)
      __getobj__.sync = value if __getobj__.respond_to?(:sync=)
      @secondary.sync = value if @secondary.respond_to?(:sync=)
      value
    end

    def sync
      __getobj__.respond_to?(:sync) ? __getobj__.sync : nil
    end
  end

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

  # Returns the persistent definition key for comparisons.
  #
  # @param definition_or_instance [Sketchup::ComponentDefinition,
  #   Sketchup::ComponentInstance]
  # @return [String, Integer]
  def def_key_of(definition_or_instance)
    definition =
      case definition_or_instance
      when Sketchup::ComponentDefinition
        definition_or_instance
      when Sketchup::ComponentInstance
        definition_or_instance.definition
      else
        raise ArgumentError, 'def_key_of expects a definition or instance'
      end

    raise ArgumentError, 'Definition is no longer valid' unless definition&.valid?

    dictionary = definition.attribute_dictionary(DICTIONARY_NAME)
    if dictionary
      key = dictionary[DEF_KEY_NAME]
      key = dictionary[LEGACY_DEF_KEY_NAME] if key.to_s.empty?
      return key unless key.to_s.empty?
    end

    if definition.respond_to?(:persistent_id)
      persistent_id = definition.persistent_id
      return "pid:#{persistent_id}" if persistent_id.to_i.positive?
    end

    if definition.respond_to?(:entityID)
      entity_id = definition.entityID
      return "entity:#{entity_id}" if entity_id.to_i.positive?
    end

    "object:#{definition.object_id}"
  end

  # Extracts params JSON stored on the definition dictionary.
  #
  # @param definition_or_instance [Sketchup::ComponentDefinition,
  #   Sketchup::ComponentInstance]
  # @return [Hash]
  def params_mm_from_definition(definition_or_instance)
    definition =
      case definition_or_instance
      when Sketchup::ComponentDefinition
        definition_or_instance
      when Sketchup::ComponentInstance
        definition_or_instance.definition
      else
        raise ArgumentError, 'params_mm_from_definition expects a definition or instance'
      end

    raise ArgumentError, 'Definition is no longer valid' unless definition&.valid?

    dictionary = definition.attribute_dictionary(DICTIONARY_NAME)
    return {} unless dictionary

    json = dictionary[PARAMS_JSON_KEY]
    return {} unless json.is_a?(String) && !json.empty?

    JSON.parse(json, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end

  # Compares two transformations with tolerance.
  #
  # @param a [Geom::Transformation]
  # @param b [Geom::Transformation]
  # @param tolerance [Numeric]
  # @return [Boolean]
  def transforms_approx_equal?(a, b, tolerance = TOL)
    return false unless a.is_a?(Geom::Transformation) && b.is_a?(Geom::Transformation)

    tol = tolerance.respond_to?(:to_f) ? tolerance.to_f : Float(tolerance)

    values_a = a.to_a
    values_b = b.to_a
    values_a.length == values_b.length &&
      values_a.zip(values_b).all? { |expected, actual| (expected - actual).abs <= tol }
  end

  # Normalizes a numeric value or SketchUp Length to millimeters.
  # Numeric inputs are treated as already expressed in millimeters.
  #
  # @param value_or_length [Numeric, Length]
  # @return [Float]
  def mm(value_or_length)
    length_class =
      if defined?(Sketchup::Length)
        Sketchup::Length
      elsif defined?(Length)
        Length
      end

    if length_class && value_or_length.is_a?(length_class)
      value_or_length.to_mm
    elsif value_or_length.is_a?(Numeric)
      value_or_length.to_f
    else
      raise ArgumentError, 'mm expects a Numeric or Length value'
    end
  end

  # Converts a numeric value expressed in SketchUp's model units (inches) or a
  # Length object to millimeters. This is used when geometry APIs return
  # distances rather than parameterized millimeter values.
  #
  # @param value_or_length [Numeric, Length]
  # @return [Float]
  def mm_from_length(value_or_length)
    length_class =
      if defined?(Sketchup::Length)
        Sketchup::Length
      elsif defined?(Length)
        Length
      end

    if length_class && value_or_length.is_a?(length_class)
      value_or_length.to_mm
    elsif length_class
      length_class.new(value_or_length).to_mm
    else
      value_or_length.to_f * 25.4
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

    default_candidates = []

    if default_collection.respond_to?(:default)
      default = default_collection.default
      default_candidates << default if default
    end

    collection_length =
      if default_collection.respond_to?(:length)
        default_collection.length
      elsif default_collection.respond_to?(:size)
        default_collection.size
      end

    if default_collection.respond_to?(:[]) && collection_length.to_i.positive?
      default_candidates << default_collection[0]
    end

    layers_collection =
      if model.respond_to?(:layers)
        model.layers
      end

    if layers_collection
      if layers_collection.respond_to?(:default)
        default_layer = layers_collection.default
        default_candidates << default_layer if default_layer
      end

      layers_length =
        if layers_collection.respond_to?(:length)
          layers_collection.length
        elsif layers_collection.respond_to?(:size)
          layers_collection.size
        end

      if layers_collection.respond_to?(:[]) && layers_length.to_i.positive?
        default_candidates << layers_collection[0]
      end
    end

    default_candidates.compact!
    default_candidates.uniq!

    return true if default_candidates.empty?

    default_candidates.any? { |candidate| candidate && entity.layer == candidate }
  end

  module_function :with_undo, :clean_model!, :assert_within_tolerance,
                  :bbox_local_of, :def_key_of, :params_mm_from_definition,
                  :transforms_approx_equal?, :mm, :mm_from_length,
                  :collect_raw_geometry, :default_tag?
end

AICabinetsTestHelper.capture_ruby_console_output
