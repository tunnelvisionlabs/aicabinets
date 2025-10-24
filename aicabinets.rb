# frozen_string_literal: true

if defined?(Sketchup)
  require 'sketchup.rb'
  require 'extensions.rb'

  module AICabinets
    EXTENSION_NAME = 'AI Cabinets'.freeze
    EXTENSION_DESCRIPTION = 'Generate cabinets from code in SketchUp.'.freeze
    EXTENSION_CREATOR = 'tunnelvisionlabs'.freeze
    EXTENSION_LOADER = 'aicabinets/loader'.freeze
  end

  Sketchup.require('aicabinets/version')

  unless file_loaded?(__FILE__)
    extension = SketchupExtension.new(
      AICabinets::EXTENSION_NAME,
      AICabinets::EXTENSION_LOADER
    )
    extension.description = AICabinets::EXTENSION_DESCRIPTION
    extension.version = AICabinets::VERSION
    extension.creator = AICabinets::EXTENSION_CREATOR

    Sketchup.register_extension(extension, true)

    if Sketchup.respond_to?(:is_extension_enabled?) && Sketchup.is_extension_enabled?(extension)
      Sketchup.require(AICabinets::EXTENSION_LOADER)
    end

    file_loaded(__FILE__)
  end
end
