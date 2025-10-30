# frozen_string_literal: true

require 'minitest/autorun'

module Sketchup
  class Length
    def initialize(value)
      @value = value.to_f
    end

    def to_f
      @value
    end
  end

  def self.require(path)
    Kernel.require(path)
  end
end

class Numeric
  def mm
    Sketchup::Length.new(self)
  end
end

$LOADED_FEATURES << 'sketchup.rb'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/defaults'
require 'aicabinets/params_sanitizer'
require 'aicabinets/generator/carcass'

class ParameterSetTest < Minitest::Test
  BASE_PARAMS = {
    width_mm: 900.0,
    depth_mm: 600.0,
    height_mm: 720.0,
    panel_thickness_mm: 19.0,
    toe_kick_height_mm: 0.0,
    toe_kick_depth_mm: 0.0,
    toe_kick_thickness_mm: 19.0,
    back_thickness_mm: 6.0,
    top_thickness_mm: 19.0,
    bottom_thickness_mm: 19.0,
    door_reveal_mm: 2.0,
    door_gap_mm: 2.0,
    top_reveal_mm: 3.0,
    bottom_reveal_mm: 4.0,
    front: 'empty',
    shelves: 0,
    partitions: {
      mode: 'none',
      count: 0,
      bays: [{ shelf_count: 0, door_mode: 'none' }]
    }
  }.freeze

  def setup
    defaults = AICabinets::Defaults.load_effective_mm
    @defaults = defaults
  end

  def test_bay_settings_follow_partition_overrides
    params = sanitized_params(
      partitions: {
        mode: 'even',
        count: 2,
        bays: [
          { shelf_count: 2, door_mode: 'doors_left' },
          { shelf_count: 1, door_mode: 'doors_double' },
          { shelf_count: 0, door_mode: 'none' }
        ]
      }
    )

    parameter_set = build_parameter_set(params)

    assert_equal([2, 1, 0], parameter_set.bay_settings.map(&:shelf_count))
    assert_equal([
                   :doors_left,
                   :doors_double,
                   nil
                 ], parameter_set.bay_settings.map(&:door_mode))

    first = parameter_set.bay_setting_at(0)
    second = parameter_set.bay_setting_at(1)
    third = parameter_set.bay_setting_at(2)

    assert_equal(2, first.shelf_count)
    assert_equal(:doors_left, first.door_mode)
    assert_equal(1, second.shelf_count)
    assert_equal(:doors_double, second.door_mode)
    assert_equal(0, third.shelf_count)
    assert_nil(third.door_mode)
  end

  def test_bay_setting_at_out_of_range_returns_template
    params = sanitized_params(
      partitions: {
        mode: 'none',
        count: 0,
        bays: []
      },
      shelves: 3,
      front: 'doors_double'
    )

    parameter_set = build_parameter_set(params)

    setting = parameter_set.bay_setting_at(5)
    assert_equal(3, setting.shelf_count)
    assert_equal(:doors_double, setting.door_mode)
  end

  private

  def sanitized_params(overrides = {})
    params = Marshal.load(Marshal.dump(BASE_PARAMS))
    overrides.each do |key, value|
      if key == :partitions
        params[:partitions] = Marshal.load(Marshal.dump(value))
      else
        params[key] = value
      end
    end

    AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: @defaults)
    params
  end

  def build_parameter_set(params_mm)
    parent = Object.new
    def parent.is_a?(klass)
      klass == Sketchup::Entities || super
    end

    AICabinets::Generator::Carcass::Builder::ParameterSet.new(params_mm)
  end
end
