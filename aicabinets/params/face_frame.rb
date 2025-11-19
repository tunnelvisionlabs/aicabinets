# frozen_string_literal: true

require 'aicabinets/face_frame'

module AICabinets
  module Params
    module FaceFrame
      module_function

      def defaults_mm
        AICabinets::FaceFrame.defaults_mm
      end

      def normalize(raw, defaults: defaults_mm)
        AICabinets::FaceFrame.normalize(raw, defaults:)
      end

      def validate(face_frame, opening_mm: nil)
        AICabinets::FaceFrame.validate(face_frame, opening_mm: opening_mm)
      end
    end
  end
end
