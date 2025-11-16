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
      toe_kick_thickness_mm
      front
      partition_mode
      shelves
      partitions
      face_frame
      constraints
    ]

    assert_equal(expected_order, result.keys)

    partitions = result[:partitions]
    assert_instance_of(Hash, partitions)
    assert_equal(%i[mode count orientation positions_mm panel_thickness_mm bays], partitions.keys)
    assert_equal([], partitions[:positions_mm])

    face_frame = result[:face_frame]
    assert_equal(true, face_frame[:enabled])
    assert_equal(19.0, face_frame[:thickness_mm])
    assert_equal([{ kind: 'double_doors' }], face_frame[:layout])

    constraints = result[:constraints]
    assert_equal(140.0, constraints[:min_door_leaf_width_mm])
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
          'version' => 'abc',
          'cabinet_base' => {
            'width_mm' => 'abc',
            'depth_mm' => 575,
            'height_mm' => -10,
            'panel_thickness_mm' => '18.0',
            'toe_kick_height_mm' => nil,
            'toe_kick_depth_mm' => 'fifty',
            'toe_kick_thickness_mm' => 'paper',
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
          },
          'face_frame' => {
            'enabled' => 'yes',
            'thickness_mm' => 'abc',
            'overlay_mm' => 40,
            'layout' => 'invalid'
          },
          'unexpected_root' => true
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
        assert_equal(18.0, result[:toe_kick_thickness_mm])
        assert_equal('doors_double', result[:front])
        assert_equal(2, result[:shelves])

        partitions = result[:partitions]
        assert_equal('none', partitions[:mode])
        assert_equal(0, partitions[:count])
        assert_equal([], partitions[:positions_mm])
        assert_nil(partitions[:panel_thickness_mm])

        face_frame = result[:face_frame]
        assert_equal(19.0, face_frame[:thickness_mm])
        assert_equal(12.7, face_frame[:overlay_mm])
      end

      assert_includes(err, 'defaults version must be a non-negative integer')
      assert_includes(err, 'defaults cabinet_base.width_mm must be a non-negative number')
      assert_includes(err, 'defaults cabinet_base.height_mm cannot be negative')
      assert_includes(err, 'defaults cabinet_base.front must be one of')
      assert_includes(err, 'ignoring unknown defaults root key')
      assert_includes(err, 'ignoring unknown defaults.cabinet_base key')
      assert_includes(err, 'ignoring unknown defaults.cabinet_base.partitions key')
      assert_includes(err, 'defaults cabinet_base.partitions.mode must be one of')
      assert_includes(err, 'defaults face_frame.thickness_mm must be a number')
      assert_includes(err, 'defaults face_frame.overlay_mm must be between')
      assert_includes(err, 'defaults face_frame.layout must be an array')
    end
  end

  private

  def override_defaults_path(path)
    AICabinets::Defaults.send(:remove_const, :DEFAULTS_PATH)
    AICabinets::Defaults.const_set(:DEFAULTS_PATH, path)
  end
end
