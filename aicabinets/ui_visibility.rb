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
      length = sanitize_bay_count(bay_count)
      return 0 if length.zero?

      numeric = sanitize_integer(index) || 0

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

      mode = value.to_s.strip.downcase
      return nil if mode.empty?

      VALID_MODES.include?(mode) ? mode : nil
    rescue StandardError
      nil
    end
    private_class_method :normalize_mode

    def self.sanitize_bay_count(value)
      number = sanitize_integer(value)
      return 0 if number.nil? || number.negative?

      number
    end
    private_class_method :sanitize_bay_count

    def self.sanitize_integer(value)
      case value
      when Integer
        value
      when Numeric
        value.finite? ? value.round : nil
      when String
        text = value.strip
        return nil unless /\A[+-]?\d+\z/.match?(text)

        text.to_i
      else
        nil
      end
    rescue StandardError
      nil
    end
    private_class_method :sanitize_integer
  end
end
