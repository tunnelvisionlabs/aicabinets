# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Rules
    module FivePiece
      module_function

      Decision = Struct.new(
        :action,
        :effective_rail_mm,
        :reason,
        :messages,
        :panel_h_mm,
        keyword_init: true
      )

      def evaluate_drawer_front(open_outside_w_mm:, open_outside_h_mm:, params: {})
        requested = params[:drawer_rail_width_mm]
        requested ||= params[:rail_width_mm]
        requested ||= params[:stile_width_mm]

        minimum_rail_mm = positive_value(params[:min_drawer_rail_width_mm]) || 0.0
        effective_rail_mm = [positive_value(requested) || 0.0, minimum_rail_mm].max

        min_panel_opening_mm = positive_value(params[:min_panel_opening_mm]) || 0.0
        panel_h_mm = open_outside_h_mm.to_f - (2.0 * effective_rail_mm)

        decision =
          if panel_h_mm < min_panel_opening_mm
            Decision.new(
              action: :slab,
              effective_rail_mm: effective_rail_mm,
              reason: :too_short_for_panel,
              messages: [format('Front is too short for five-piece; switching to slab (panel opening %.2f mm < %.2f mm).',
                                 panel_h_mm, min_panel_opening_mm)],
              panel_h_mm: panel_h_mm
            )
          elsif requested.to_f < minimum_rail_mm
            Decision.new(
              action: :five_piece,
              effective_rail_mm: effective_rail_mm,
              reason: :clamped_rail,
              messages: [format('Requested drawer rail width will be clamped to %.2f mm.', effective_rail_mm)],
              panel_h_mm: panel_h_mm
            )
          else
            Decision.new(
              action: :five_piece,
              effective_rail_mm: effective_rail_mm,
              reason: :ok,
              messages: [],
              panel_h_mm: panel_h_mm
            )
          end

        decision
      end

      def positive_value(value)
        return nil unless value.is_a?(Numeric)

        value > 0 ? value.to_f : nil
      end
      private_class_method :positive_value
    end
  end
end

