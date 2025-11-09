# frozen_string_literal: true

module AICabinets
  module Features
    module_function

    def layout_preview?
      store = feature_store
      return true unless store.key?(:layout_preview)

      !!store[:layout_preview]
    end

    def layout_preview=(value)
      normalized = normalize_boolean(value)
      if normalized.nil?
        feature_store.delete(:layout_preview)
      else
        feature_store[:layout_preview] = normalized
      end
    end

    def enable_layout_preview!
      feature_store[:layout_preview] = true
    end

    def disable_layout_preview!
      feature_store[:layout_preview] = false
    end

    def reset!
      feature_store.clear
    end

    def feature_store
      @feature_store ||= {}
    end
    private_class_method :feature_store

    def normalize_boolean(value)
      return nil if value.nil?

      case value
      when true, false
        value
      else
        !!value
      end
    end
    private_class_method :normalize_boolean
  end
end
