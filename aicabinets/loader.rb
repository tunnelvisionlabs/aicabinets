# frozen_string_literal: true

module AICabinets
  Sketchup.require('aicabinets/version') if defined?(Sketchup)

  module Loader
    module_function

    # Placeholder entry point for future extension bootstrapping.
    def bootstrap
      # Intentionally left blank to keep load time near zero.
      nil
    end
  end
end
