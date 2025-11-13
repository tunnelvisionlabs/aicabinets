# frozen_string_literal: true

module AICabinets
  # Raised when parameter validation fails. Carries a set of user-presentable
  # messages explaining the failure(s).
  class ValidationError < StandardError
    attr_reader :messages

    def initialize(messages)
      @messages = Array(messages).flatten.compact
      super(build_message(@messages))
    end

    private

    def build_message(messages)
      return 'Validation failed' if messages.empty?

      messages.join('; ')
    end
  end
end
