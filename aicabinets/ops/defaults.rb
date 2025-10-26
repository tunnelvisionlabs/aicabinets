# frozen_string_literal: true

require 'aicabinets/defaults'

module AICabinets
  module Ops
    module Defaults
      module_function

      def load_insert_base_cabinet
        deep_copy(AICabinets::Defaults.load_mm)
      end

      def deep_copy(object)
        case object
        when Hash
          object.each_with_object({}) { |(key, value), memo| memo[key] = deep_copy(value) }
        when Array
          object.map { |value| deep_copy(value) }
        else
          object
        end
      end
      private_class_method :deep_copy
    end
  end
end
