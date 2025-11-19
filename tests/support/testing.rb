# frozen_string_literal: true

module AICabinets
  module Testing
    module_function

    def mm_tol
      0.5
    end

    def mm_tol=(value)
      @mm_tol = value
    end

    def tolerance
      @mm_tol || mm_tol
    end
  end
end
