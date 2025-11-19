# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__)) unless $LOAD_PATH.include?(File.expand_path('..', __dir__))
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__)) unless $LOAD_PATH.include?(File.expand_path('../../lib', __dir__))

require_relative '../../test/support/sketchup'

