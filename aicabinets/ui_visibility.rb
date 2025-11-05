# frozen_string_literal: true

module AICabinets
  module UiVisibility
    VALID_PARTITION_MODES = %w[none vertical horizontal].freeze

    def flags_for(params)
      mode = normalize_mode(fetch_partition_mode(params))
      show_global = mode == 'none'

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

    def self.fetch_partition_mode(params)
      return nil unless params.is_a?(Hash)

      params[:partition_mode] || params['partition_mode']
    end
    private_class_method :fetch_partition_mode

    def self.normalize_mode(value)
      return 'none' if value.nil?

      mode = value.to_s.strip.downcase
      return 'none' if mode.empty?

      VALID_PARTITION_MODES.include?(mode) ? mode : 'none'
    rescue StandardError
      'none'
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
