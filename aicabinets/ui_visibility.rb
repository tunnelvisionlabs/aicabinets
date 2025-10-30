# frozen_string_literal: true

module AICabinets
  module UiVisibility
    VALID_MODES = %w[none even positions].freeze

    def flags_for(params)
      partitions = extract_partitions(params)
      mode = normalize_mode(partitions[:mode])
      show_global = mode.nil? || mode == 'none'

      {
        show_bays: !show_global,
        show_global_front_layout: show_global,
        show_global_shelves: show_global
      }
    end

    def clamp_selected_index(index, bay_count)
      length =
        begin
          Integer(bay_count)
        rescue ArgumentError, TypeError
          nil
        end
      length = 0 if length.nil? || length.negative?
      return 0 if length.zero?

      numeric =
        begin
          Integer(index)
        rescue ArgumentError, TypeError
          0
        end

      [[numeric, 0].max, length - 1].min
    end

    module_function :flags_for, :clamp_selected_index

    def self.extract_partitions(params)
      return {} unless params.is_a?(Hash)

      container = params[:partitions] || params['partitions']
      return {} unless container.is_a?(Hash)

      container.each_with_object({}) do |(key, value), memo|
        memo[key.is_a?(String) ? key.to_sym : key] = value
      end
    end
    private_class_method :extract_partitions

    def self.normalize_mode(value)
      return nil if value.nil?

      mode =
        case value
        when Symbol
          value.to_s
        else
          value.to_s
        end
      mode = mode.strip.downcase
      return nil if mode.empty?

      return mode if VALID_MODES.include?(mode)

      nil
    rescue StandardError
      nil
    end
    private_class_method :normalize_mode
  end
end
