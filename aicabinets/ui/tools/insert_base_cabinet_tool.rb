# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/ui/icons')
Sketchup.require('aicabinets/ui/tools/placement_tool')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

module AICabinets
  module UI
    module Tools
      # Placement tool specialized for inserting a base cabinet. Provides a
      # preview sized to cabinet parameters and performs insertion in a single
      # undoable operation when the user clicks a point in the model.
      class InsertBaseCabinetTool < PlacementTool
        CURSOR_HOT_X = 2
        CURSOR_HOT_Y = 2

        def initialize(params_mm, callbacks: {}, placer: nil)
          raise ArgumentError, 'params_mm must be a Hash' unless params_mm.is_a?(Hash)

          @params_mm = deep_freeze(params_mm.dup)
          @placer = placer || method(:default_place)
          super(callbacks: callbacks)
        end

        def self.preview_bounds_mm(params_mm)
          width = numeric_param(params_mm, :width_mm)
          depth = numeric_param(params_mm, :depth_mm)
          height = numeric_param(params_mm, :height_mm)

          {
            min: [0.0, 0.0, 0.0],
            max: [width, depth, height]
          }
        end

        def self.cursor_spec
          path = AICabinets::UI::Icons.cursor_icon_path('insert_base_cabinet')
          return nil unless path

          { path: path, hotspot_x: CURSOR_HOT_X, hotspot_y: CURSOR_HOT_Y }
        end

        private

        def perform_place(model:, point3d:)
          @placer.call(model: model, point3d: point3d, params_mm: @params_mm)
        end

        def preview_corners_mm
          bounds = self.class.preview_bounds_mm(@params_mm)
          max = bounds[:max]

          width = max[0]
          depth = max[1]
          height = max[2]

          [
            [0.0, 0.0, 0.0],
            [width, 0.0, 0.0],
            [width, depth, 0.0],
            [0.0, depth, 0.0],
            [0.0, 0.0, height],
            [width, 0.0, height],
            [width, depth, height],
            [0.0, depth, height]
          ]
        end

        def default_place(model:, point3d:, params_mm:)
          AICabinets::Ops::InsertBaseCabinet.place_at_point!(
            model: model,
            point3d: point3d,
            params_mm: params_mm
          )
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

        def self.numeric_param(params, key)
          value = params[key]
          value = params[key.to_s] if value.nil?
          value = value.to_f if value.respond_to?(:to_f)
          raise ArgumentError, "Missing numeric parameter: #{key}" unless value.finite?

          value
        end
        private_class_method :numeric_param
      end
    end
  end
end
