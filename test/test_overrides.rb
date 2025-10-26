# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/defaults'

class OverridesTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('aicabinets-overrides-test-')
    @original_user_dir = AICabinets::Defaults.const_get(:USER_DIR)
    @original_overrides_path = AICabinets::Defaults.const_get(:OVERRIDES_PATH)
    @original_temp_path = AICabinets::Defaults.const_get(:OVERRIDES_TEMP_PATH)
    override_overrides_paths(@tmpdir)
  end

  def teardown
    override_overrides_paths(@original_user_dir, @original_overrides_path, @original_temp_path)
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_load_effective_mm_without_overrides_matches_defaults
    defaults = AICabinets::Defaults.load_mm
    effective = AICabinets::Defaults.load_effective_mm

    assert_equal(defaults, effective)
    assert_equal(defaults.keys, effective.keys)
  end

  def test_save_overrides_mm_writes_atomic_file
    params = AICabinets::Defaults.load_mm
    params[:width_mm] = 543.21098
    params[:partitions] = {
      mode: 'positions',
      count: 2,
      positions_mm: [100.0, 250.1234],
      panel_thickness_mm: nil
    }

    rename_calls = []
    singleton = class << File; self; end
    singleton.alias_method :__original_rename, :rename
    singleton.define_method(:rename) do |src, dest|
      rename_calls << [src, dest]
      __original_rename(src, dest)
    end

    begin
      result = AICabinets::Defaults.save_overrides_mm(params)
      assert(result)
    ensure
      singleton.remove_method(:rename)
      singleton.alias_method :rename, :__original_rename
      singleton.remove_method(:__original_rename)
    end

    overrides_path = AICabinets::Defaults.const_get(:OVERRIDES_PATH)
    temp_path = AICabinets::Defaults.const_get(:OVERRIDES_TEMP_PATH)

    assert(File.exist?(overrides_path))
    refute(File.exist?(temp_path))

    assert_equal([[temp_path, overrides_path]], rename_calls)
    assert_equal(File.dirname(overrides_path), File.dirname(rename_calls.first.first))

    data = JSON.parse(File.read(overrides_path))
    cabinet_base = data.fetch('cabinet_base')

    expected_keys = %w[
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

    assert_equal(expected_keys, cabinet_base.keys)
    assert_in_delta(543.211, cabinet_base['width_mm'], 0.001)

    partitions = cabinet_base.fetch('partitions')
    assert_equal(%w[mode count positions_mm panel_thickness_mm], partitions.keys)
    assert_equal('positions', partitions['mode'])
    assert_equal(2, partitions['count'])
    assert_equal([100.0, 250.123], partitions['positions_mm'])
    assert_nil(partitions['panel_thickness_mm'])
  end

  def test_load_effective_mm_merges_overrides
    overrides_path = AICabinets::Defaults.const_get(:OVERRIDES_PATH)

    File.write(
      overrides_path,
      JSON.pretty_generate(
        'cabinet_base' => {
          'width_mm' => 750,
          'shelves' => 4,
          'partitions' => {
            'mode' => 'positions',
            'count' => 2,
            'positions_mm' => [150, 300]
          }
        }
      )
    )

    effective = AICabinets::Defaults.load_effective_mm

    assert_equal(750.0, effective[:width_mm])
    assert_equal(4, effective[:shelves])

    partitions = effective[:partitions]
    assert_equal('positions', partitions[:mode])
    assert_equal(2, partitions[:count])
    assert_equal([150.0, 300.0], partitions[:positions_mm])
    assert_nil(partitions[:panel_thickness_mm])
    assert_equal(600.0, effective[:depth_mm])
  end

  def test_unknown_keys_warn_once_and_are_ignored
    overrides_path = AICabinets::Defaults.const_get(:OVERRIDES_PATH)

    File.write(
      overrides_path,
      JSON.pretty_generate(
        'cabinet_base' => {
          'width_mm' => 700,
          'mystery' => true,
          'partitions' => {
            'extra' => 10,
            'mode' => 'none'
          }
        },
        'unexpected' => 1
      )
    )

    _, err = capture_io do
      effective = AICabinets::Defaults.load_effective_mm
      assert_equal(700.0, effective[:width_mm])
      assert_equal('none', effective[:partitions][:mode])
      refute(effective[:partitions].key?(:extra))
    end

    assert_includes(err, 'ignoring unknown overrides root key(s)')
    assert_includes(err, 'ignoring unknown overrides key(s)')
    assert_includes(err, 'ignoring unknown overrides.partitions key(s)')
  end

  def test_corrupt_overrides_are_ignored
    overrides_path = AICabinets::Defaults.const_get(:OVERRIDES_PATH)
    File.write(overrides_path, '{ invalid json')

    _, err = capture_io do
      effective = AICabinets::Defaults.load_effective_mm
      assert_equal(600.0, effective[:width_mm])
    end

    assert_includes(err, 'overrides JSON parse error')

    File.write(overrides_path, JSON.pretty_generate('cabinet_base' => 'bad'))

    _, err = capture_io do
      effective = AICabinets::Defaults.load_effective_mm
      assert_equal(600.0, effective[:width_mm])
    end

    assert_includes(err, 'overrides cabinet_base must be an object')
  end

  def test_load_effective_mm_is_deterministic
    overrides_path = AICabinets::Defaults.const_get(:OVERRIDES_PATH)

    File.write(
      overrides_path,
      JSON.pretty_generate('cabinet_base' => { 'depth_mm' => 575.5 })
    )

    first = AICabinets::Defaults.load_effective_mm
    second = AICabinets::Defaults.load_effective_mm

    assert_equal(first, second)
    assert_equal(first.keys, second.keys)
  end

  private

  def override_overrides_paths(user_dir, overrides_path = nil, temp_path = nil)
    overrides_path ||= File.join(user_dir, 'overrides.json')
    temp_path ||= "#{overrides_path}.tmp"

    replace_const(:USER_DIR, user_dir)
    replace_const(:OVERRIDES_PATH, overrides_path)
    replace_const(:OVERRIDES_TEMP_PATH, temp_path)
  end

  def replace_const(name, value)
    AICabinets::Defaults.send(:remove_const, name)
    AICabinets::Defaults.const_set(name, value)
  end
end
