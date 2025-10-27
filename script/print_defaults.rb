#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'json'
require 'aicabinets/defaults'

defaults = AICabinets::Defaults.load_mm

puts(JSON.pretty_generate(defaults))
