# frozen_string_literal: true

module AICabinets
  module UI
    # Localization helpers centralizing user-visible strings so they can be
    # extracted for translation. The helpers fall back to English copies when
    # SketchUp's translation facilities are unavailable (e.g., in tests).
    module Localization
      module_function

      STRINGS = {
        placement_prompt: 'Click to place cabinet (FLB carcass anchor). Esc to cancel.',
        placement_cancelled: 'Cabinet placement cancelled.',
        placement_tip: 'Tip: Use Move (M) with Ctrl/Option to copy the new cabinet.',
        placement_failed: 'Unable to place cabinet at the picked location.',
        placement_indicator: 'Placing cabinet… click in model.',
        placement_activation_failed: 'Unable to activate cabinet placement.',
        placement_invalid_point: 'Pick a point in the model to place the cabinet.'
      }.freeze

      # Returns the localized string for the provided key.
      #
      # @param key [Symbol]
      # @return [String]
      def string(key)
        fallback = STRINGS[key] || key.to_s
        if defined?(Sketchup) && Sketchup.respond_to?(:GetString)
          Sketchup::GetString(fallback)
        else
          fallback
        end
      end
    end
  end
end
