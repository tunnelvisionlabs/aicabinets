#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'json'
require 'aicabinets/version'
require 'aicabinets/defaults'

effective = AICabinets::Defaults.load_effective_mm
payload = {
  schema_version: AICabinets::PARAMS_SCHEMA_VERSION,
  cabinet_base: effective[:cabinet_base] || effective['cabinet_base'],
  face_frame: effective[:face_frame] || effective['face_frame'],
  constraints: effective[:constraints] || effective['constraints']
}

puts(JSON.pretty_generate(payload))
