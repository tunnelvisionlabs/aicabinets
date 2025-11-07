# frozen_string_literal: true

require 'json'

module AICabinets
  module UI
    module DialogConsoleBridge
      module_function

      def register_dialog(dialog)
        return unless dialog

        buffers[dialog] ||= []
      end

      def unregister_dialog(dialog)
        buffers.delete(dialog)
      end

      def record_event(dialog, payload)
        return unless dialog

        event = parse_event(payload)
        return unless event

        buffers[dialog] ||= []
        buffers[dialog] << event
      end

      def drain_events(dialog)
        buffers.delete(dialog) || []
      end

      def peek_events(dialog)
        events = buffers[dialog]
        return [] unless events

        events.map { |event| event.dup }
      end

      def buffers
        @buffers ||= {}.compare_by_identity
      end

      def parse_event(payload)
        data = JSON.parse(payload.to_s)
        build_event_from(data)
      rescue JSON::ParserError => error
        {
          dialog_id: 'unknown',
          level: 'error',
          message: "Invalid console event payload: #{error.message}"
        }
      end

      def build_event_from(data)
        return unless data.is_a?(Hash)

        level = safe_string(data['level'])
        level = level ? level.downcase : 'error'

        event = {
          dialog_id: safe_string(data['dialogId']) || 'unknown',
          level: level,
          message: safe_string(data['message']) || '(no message)',
          stack: safe_string(data['stack']),
          url: safe_string(data['url']),
          line: safe_integer(data['line']),
          column: safe_integer(data['column']),
          timestamp: safe_string(data['timestamp']),
          details: normalize_details(data['details'])
        }

        event.delete_if { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end

      def safe_string(value)
        return if value.nil?

        value.to_s
      end

      def safe_integer(value)
        return if value.nil?

        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      def normalize_details(details)
        return unless details.is_a?(Hash)

        details.each_with_object({}) do |(key, value), normalized|
          normalized[key.to_s] = value
        end
      end
    end
  end
end
