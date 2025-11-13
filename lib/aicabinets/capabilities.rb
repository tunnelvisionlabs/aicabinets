# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Capabilities
    module_function

    def solid_booleans?
      return false unless defined?(Sketchup)

      group_class = Sketchup.const_defined?(:Group) ? Sketchup::Group : nil
      return false unless group_class

      group_class.instance_methods.include?(:subtract)
    rescue StandardError
      false
    end
  end
end
