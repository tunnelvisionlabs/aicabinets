# frozen_string_literal: true

Sketchup.require('aicabinets/rows/reveal')

module AICabinets
  module Rows
    module Regeneration
      module_function

      def handle_row_change(model:, row:)
        return unless model.is_a?(Sketchup::Model)
        return unless row.is_a?(Hash)

        row_id = row['row_id'] || row[:row_id]
        return unless row_id

        Reveal.apply!(row_id: row_id, model: model, operation: false)
        :ok
      end
    end
  end
end
