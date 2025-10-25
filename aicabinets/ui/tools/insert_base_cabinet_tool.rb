# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/ops/insert_base_cabinet')

module AICabinets
  module UI
    module Tools
      # SketchUp tool responsible for placing a base cabinet component at a
      # picked point. The tool performs a single placement action and then
      # deactivates itself so the user immediately returns to the previous tool.
      class InsertBaseCabinetTool
        def initialize(params_mm)
          raise ArgumentError, 'params_mm must be a Hash' unless params_mm.is_a?(Hash)

          @params_mm = deep_freeze(params_mm.dup)
          @input_point = nil
          @placing = false
        end

        def activate(view)
          @input_point = Sketchup::InputPoint.new
          view.invalidate if view
        end

        def deactivate(_view)
          @input_point = nil
        end

        def onCancel(_reason, _view)
          exit_tool
        end

        def onLButtonDown(_flags, x, y, view)
          return if @placing

          model = Sketchup.active_model
          unless model.is_a?(Sketchup::Model)
            warn('AI Cabinets: No active model to insert cabinet into.')
            exit_tool
            return
          end

          input_point = pick_point(view, x, y)
          unless input_point&.valid?
            warn('AI Cabinets: Unable to determine pick point for cabinet placement.')
            exit_tool
            return
          end

          @placing = true

          instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
            model: model,
            point3d: input_point.position,
            params_mm: @params_mm
          )

          exit_tool

          instance
        ensure
          @placing = false
        end

        private

        def pick_point(view, x, y)
          return unless view && @input_point

          @input_point.pick(view, x, y)
          @input_point
        rescue StandardError => e
          warn("AI Cabinets: Error while picking point: #{e.message}")
          nil
        end

        def exit_tool
          Sketchup.active_model.select_tool(nil) if defined?(Sketchup) && Sketchup.active_model
        end

        def deep_freeze(object)
          case object
          when Hash
            object.each_with_object({}) do |(key, value), result|
              result[key] = deep_freeze(value)
            end.freeze
          when Array
            object.map { |value| deep_freeze(value) }.freeze
          else
            object.freeze
          end
        end
      end
    end
  end
end
