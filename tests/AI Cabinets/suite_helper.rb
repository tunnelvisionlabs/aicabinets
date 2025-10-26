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
                         model.tags
                       else
                         model.layers
                       end
      tags_or_layers.purge_unused

      model.materials.purge_unused
      model.styles.purge_unused
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
  module_function :with_undo, :clean_model!, :assert_within_tolerance
end
