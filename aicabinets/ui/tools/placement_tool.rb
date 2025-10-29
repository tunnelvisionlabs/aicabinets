# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/ops/units')
Sketchup.require('aicabinets/ui/localization')

module AICabinets
  module UI
    module Tools
      # Generic SketchUp tool providing placement affordances (status text,
      # cursor, inference tracking, and preview drawing). Subclasses override
      # the preview geometry and placement operation.
      class PlacementTool
        STATUS_PROMPT_KEY = :placement_prompt
        STATUS_CANCEL_KEY = :placement_cancelled
        STATUS_TIP_KEY = :placement_tip
        ESCAPE_KEY_CODE = 27

        def initialize(callbacks: {})
          @callbacks = (callbacks || {}).dup.freeze
          @input_point = nil
          @current_point = nil
          @placing = false
          @finished = false
          @preview_points = build_preview_points.freeze
        end

        def activate(view = nil)
          @input_point = Sketchup::InputPoint.new
          @finished = false
          set_status_text(status_text_for(status_prompt_key))
          view.invalidate if view
        end

        def deactivate(view = nil)
          @input_point = nil
          @current_point = nil
          view.invalidate if view
        end

        def resume(view)
          view.invalidate if view
        end

        def onCancel(_reason, _view)
          cancel_tool
        end

        def onKeyDown(key, _repeat, _flags, _view)
          return unless escape_key?(key)

          cancel_tool
          true
        end

        def onLButtonDown(_flags, x, y, view)
          return nil if @finished

          model = Sketchup.active_model
          unless model.is_a?(Sketchup::Model)
            notify_error(Localization.string(:placement_activation_failed))
            exit_tool(status_key: status_cancel_key)
            return nil
          end

          input_point = pick_point(view, x, y)
          unless input_point&.valid?
            set_status_text(status_text_for(:placement_invalid_point))
            return nil
          end

          result = place_instance(model, input_point.position)
          case result
          when :error
            exit_tool(status_key: status_cancel_key)
            nil
          when nil
            nil
          else
            notify_completed(result)
            exit_tool(status_key: status_tip_key)
            result
          end
        end

        def onMouseMove(_flags, x, y, view)
          return if @finished
          return unless view && @input_point

          updated = @input_point.pick(view, x, y)
          return unless updated

          if @input_point.valid?
            @current_point = @input_point.position
            view.invalidate
          end
        rescue StandardError => e
          warn("AI Cabinets: Error while tracking placement point: #{e.message}")
        end

        def cancel_from_ui
          cancel_tool
        end

        def draw(view)
          return unless view

          @input_point&.draw(view)
          draw_preview(view) if @current_point
        end

        def onSetCursor
          cursor_id = self.class.cursor_id
          return false unless cursor_id
          return false unless defined?(UI) && UI.respond_to?(:set_cursor)

          UI.set_cursor(cursor_id)
        end

        def self.cursor_id
          @cursor_id ||= begin
            spec = cursor_spec
            if spec && spec[:path] && defined?(UI) && UI.respond_to?(:create_cursor)
              UI.create_cursor(spec[:path], spec[:hotspot_x] || 0, spec[:hotspot_y] || 0)
            end
          rescue StandardError => e
            warn("AI Cabinets: Unable to create placement cursor: #{e.message}")
            nil
          end
        end

        def self.cursor_spec
          nil
        end

        private

        attr_reader :callbacks

        def status_prompt_key
          STATUS_PROMPT_KEY
        end

        def status_cancel_key
          STATUS_CANCEL_KEY
        end

        def status_tip_key
          STATUS_TIP_KEY
        end

        def status_text_for(key)
          Localization.string(key)
        end

        def cancel_tool
          return if finish?

          notify_cancelled
          exit_tool(status_key: status_cancel_key)
        end

        def place_instance(model, point3d)
          return :error if @placing

          @placing = true
          instance = perform_place(model: model, point3d: point3d)
          unless valid_instance?(instance)
            notify_error(Localization.string(:placement_failed))
            return :error
          end
          instance
        rescue StandardError => e
          warn("AI Cabinets: Placement failed: #{e.message}")
          notify_error(Localization.string(:placement_failed))
          :error
        ensure
          @placing = false
        end

        def perform_place(model:, point3d:)
          raise NotImplementedError, 'Subclasses must implement perform_place'
        end

        def valid_instance?(instance)
          instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
        end

        def notify_cancelled
          return if finish?

          @finished = true
          callbacks[:cancel]&.call
        end

        def notify_completed(instance)
          return if finish?

          @finished = true
          callbacks[:complete]&.call(instance)
        end

        def notify_error(message)
          return if finish?

          @finished = true
          callbacks[:error]&.call(message)
        end

        def finish?
          @finished
        end

        def exit_tool(status_key: nil, status_message: nil)
          set_status_text(status_message || status_text_for(status_key)) if status_key || status_message

          model = defined?(Sketchup) ? Sketchup.active_model : nil
          model.select_tool(nil) if model
        rescue StandardError => e
          warn("AI Cabinets: Unable to exit placement tool: #{e.message}")
        end

        def set_status_text(message)
          return unless message
          return unless defined?(Sketchup) && Sketchup.respond_to?(:set_status_text)

          Sketchup.set_status_text(message)
        rescue StandardError => e
          warn("AI Cabinets: Unable to update status text: #{e.message}")
        end

        def pick_point(view, x, y)
          return unless view && @input_point

          @input_point.pick(view, x, y)
          @input_point
        rescue StandardError => e
          warn("AI Cabinets: Error while picking point: #{e.message}")
          nil
        end

        def draw_preview(view)
          translated = translated_preview_points
          return unless translated && translated.length >= 8

          view.line_width = 2
          view.drawing_color = [24, 121, 216, 192]

          bottom = translated[0..3]
          top = translated[4..7]
          verticals = bottom.zip(top).flatten.compact

          view.line_stipple = '' if view.respond_to?(:line_stipple=)

          draw_with_overlay(view, GL_LINE_LOOP, bottom)
          draw_with_overlay(view, GL_LINE_LOOP, top)
          draw_with_overlay(view, GL_LINES, verticals)
        rescue StandardError => e
          warn("AI Cabinets: Unable to draw placement preview: #{e.message}")
        end

        def translated_preview_points
          return unless @current_point

          translation = Geom::Transformation.translation(@current_point.to_a)
          @preview_points.map { |pt| pt.transform(translation) }
        end

        def build_preview_points
          preview_corners_mm.map do |coords|
            x_mm, y_mm, z_mm = coords
            Ops::Units.point_mm(x_mm.to_f, y_mm.to_f, z_mm.to_f)
          end
        end

        def preview_corners_mm
          raise NotImplementedError, 'Subclasses must implement preview_corners_mm'
        end

        def escape_key?(key)
          return false if key.nil?

          key_value = key.to_i
          return true if key_value == ESCAPE_KEY_CODE

          defined?(Sketchup) && defined?(Sketchup::VK_ESCAPE) && key_value == Sketchup::VK_ESCAPE
        end

        def draw_with_overlay(view, mode, points)
          return unless view && points && !points.empty?

          view.draw(mode, points, false)
        rescue ArgumentError
          view.draw(mode, points)
        end

        module Localization
          module_function

          def string(key)
            AICabinets::UI::Localization.string(key)
          end
        end
      end
    end
  end
end
