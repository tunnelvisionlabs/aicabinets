#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(root)

test_files = Dir[File.join(root, 'test', 'unit', 'test_*.rb')].sort
abort('No unit tests found under test/unit') if test_files.empty?

test_files.each do |file|
  require file
end
