# frozen_string_literal: true

module AICabinets
  if defined?(Sketchup)
    Sketchup.require('aicabinets/features')
    Sketchup.require('aicabinets/validation_error')
    Sketchup.require('aicabinets/params/five_piece')
    Sketchup.require('aicabinets/version')
    Sketchup.require('aicabinets/ops/units')
    Sketchup.require('aicabinets/selection')
    Sketchup.require('aicabinets/tags')
    Sketchup.require('aicabinets/rows')
    Sketchup.require('aicabinets/generator/carcass')
    Sketchup.require('aicabinets/ops/insert_base_cabinet')
    Sketchup.require('aicabinets/ops/edit_base_cabinet')
    Sketchup.require('aicabinets/ui/localization')
    Sketchup.require('aicabinets/ui/icons')
    Sketchup.require('aicabinets/ops/defaults')
    Sketchup.require('aicabinets/ui/dialogs/insert_base_cabinet_dialog')
    Sketchup.require('aicabinets/ui/tools/insert_base_cabinet_tool')
    Sketchup.require('aicabinets/ui/rows')
    Sketchup.require('aicabinets/ui/rows/manager_dialog')
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
