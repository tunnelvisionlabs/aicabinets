# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Ops
    module Operations
      module_function

      DEPTH_KEY = :@aicabinets_operation_depth

      def install!(_model = Sketchup.active_model)
        install_hooks
      end

      def install_hooks
        return if @hooks_installed
        return unless defined?(Sketchup::Model)

        @hooks_installed = true

        Sketchup::Model.class_eval do
          alias_method :aicabinets_original_start_operation, :start_operation
          alias_method :aicabinets_original_commit_operation, :commit_operation
          alias_method :aicabinets_original_abort_operation, :abort_operation

          def start_operation(*args, &block)
            result = aicabinets_original_start_operation(*args, &block)
            if result
              AICabinets::Ops::Operations.increment_depth(self)
            end
            result
          end

          def commit_operation(*args, &block)
            result = aicabinets_original_commit_operation(*args, &block)
            AICabinets::Ops::Operations.decrement_depth(self)
            result
          end

          def abort_operation(*args, &block)
            result = aicabinets_original_abort_operation(*args, &block)
            AICabinets::Ops::Operations.decrement_depth(self)
            result
          end
        end
      end

      def operation_open?(model)
        depth(model).positive?
      end

      def depth(model)
        return 0 unless model

        Integer(model.instance_variable_get(DEPTH_KEY) || 0)
      end

      def increment_depth(model)
        return unless model

        current = depth(model) + 1
        model.instance_variable_set(DEPTH_KEY, current)
      end

      def decrement_depth(model)
        return unless model

        current = depth(model) - 1
        current = 0 if current.negative?
        model.instance_variable_set(DEPTH_KEY, current)
      end
    end
  end
end
