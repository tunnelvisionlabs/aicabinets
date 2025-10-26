# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/defaults'

class DefaultsLoaderTest < Minitest::Test
  def setup
    @original_path = AICabinets::Defaults.const_get(:DEFAULTS_PATH)
  end

  def teardown
    override_defaults_path(@original_path)
  end

  def test_load_mm_returns_canonical_defaults
    result = AICabinets::Defaults.load_mm

    expected_order = %i[
      width_mm
      depth_mm
      height_mm
      panel_thickness_mm
      toe_kick_height_mm
      toe_kick_depth_mm
      front
      shelves
      partitions
    ]

    assert_equal(expected_order, result.keys)

    partitions = result[:partitions]
    assert_instance_of(Hash, partitions)
    assert_equal(%i[mode count positions_mm panel_thickness_mm], partitions.keys)
    assert_equal([], partitions[:positions_mm])
  end

  def test_load_mm_missing_file_uses_fallback_and_warns
    override_defaults_path(File.join(Dir.mktmpdir, 'missing.json'))

    _, err = capture_io do
      result = AICabinets::Defaults.load_mm
      assert_equal(600.0, result[:width_mm])
    end

    assert_includes(err, 'defaults file not found')
  end

  def test_load_mm_invalid_values_are_replaced
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'defaults.json')
      File.write(
        path,
        JSON.generate(
          'width_mm' => 'abc',
          'depth_mm' => 575,
          'height_mm' => -10,
          'panel_thickness_mm' => '18.0',
          'toe_kick_height_mm' => nil,
          'toe_kick_depth_mm' => 'fifty',
          'front' => 'invalid',
          'shelves' => -1,
          'unknown_key' => true,
          'partitions' => {
            'mode' => 'unsupported',
            'count' => 'not a number',
            'positions_mm' => ['a', -5],
            'panel_thickness_mm' => '-2',
            'extra' => 123
          }
        )
      )

      override_defaults_path(path)

      _, err = capture_io do
        result = AICabinets::Defaults.load_mm

        assert_equal(600.0, result[:width_mm])
        assert_equal(575.0, result[:depth_mm])
        assert_equal(720.0, result[:height_mm])
        assert_equal(18.0, result[:panel_thickness_mm])
        assert_equal(100.0, result[:toe_kick_height_mm])
        assert_equal(50.0, result[:toe_kick_depth_mm])
        assert_equal('doors_double', result[:front])
        assert_equal(2, result[:shelves])

        partitions = result[:partitions]
        assert_equal('none', partitions[:mode])
        assert_equal(0, partitions[:count])
        assert_equal([], partitions[:positions_mm])
        assert_nil(partitions[:panel_thickness_mm])
      end

      assert_includes(err, 'defaults width_mm must be a non-negative number')
      assert_includes(err, 'defaults height_mm cannot be negative')
      assert_includes(err, 'defaults front must be one of')
      assert_includes(err, 'ignoring unknown defaults key')
      assert_includes(err, 'ignoring unknown defaults.partitions key')
      assert_includes(err, 'defaults partitions.mode must be one of')
    end
  end

  private

  def override_defaults_path(path)
    AICabinets::Defaults.send(:remove_const, :DEFAULTS_PATH)
    AICabinets::Defaults.const_set(:DEFAULTS_PATH, path)
  end
end
