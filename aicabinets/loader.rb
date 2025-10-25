# frozen_string_literal: true

module AICabinets
  if defined?(Sketchup)
    Sketchup.require('aicabinets/version')
    Sketchup.require('aicabinets/ui/icons')
    Sketchup.require('aicabinets/ui/dialogs/insert_base_cabinet_dialog')
    Sketchup.require('aicabinets/ui/commands')
    Sketchup.require('aicabinets/ui/menu_and_toolbar')
  end

  module Loader
    module_function

    # Entry point invoked when the extension is loaded. Keeps load-time side
    # effects to the absolute minimum by only registering UI wiring.
    def bootstrap
      return unless defined?(Sketchup)

      AICabinets::UI.register_ui! if AICabinets::UI.respond_to?(:register_ui!)
      nil
    end
  end
end

AICabinets::Loader.bootstrap if defined?(Sketchup)
