#!/usr/bin/env ruby
# frozen_string_literal: true

PATTERN = /(\.mm\b)|(\.inch\b)|(Length\.new)/.freeze
ALLOWED = [
  %r{\Aaicabinets/generator/},
  %r{\Aaicabinets/ops/units\.rb\z}
].freeze
TARGET_ROOTS = [
  'aicabinets/',
  'lib/',
  'aicabinets.rb'
].freeze

files = `git ls-files`.split("\n")
violations = []

files.each do |file|
  next unless TARGET_ROOTS.any? { |root| file.start_with?(root) }
  next unless file.end_with?('.rb')
  next if ALLOWED.any? { |regex| file.match?(regex) }

  File.foreach(file).with_index do |line, idx|
    next unless line.match?(PATTERN)

    violations << "#{file}:#{idx + 1}:#{line.strip}"
  end
end

if violations.empty?
  puts 'No forbidden unit conversions found outside modeling layer.'
else
  warn 'Found forbidden unit conversions outside modeling layer:'
  violations.each { |violation| warn "  #{violation}" }
  exit 1
end
