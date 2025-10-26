#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/defaults'

path = AICabinets::Defaults.const_get(:OVERRIDES_PATH)

default_message = "AI Cabinets: overrides file not found; nothing to reset."

if File.exist?(path)
  File.delete(path)
  puts("AI Cabinets: deleted overrides file at #{path}.")
else
  puts(default_message)
end
