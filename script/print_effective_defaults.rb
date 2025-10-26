#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'json'
require 'aicabinets/defaults'

effective = AICabinets::Defaults.load_effective_mm

puts(JSON.pretty_generate(effective))
