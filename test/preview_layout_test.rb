# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require 'aicabinets/params_sanitizer'
require 'lib/aicabinets/preview/layout'

class PreviewLayoutTest < Minitest::Test
  def test_vertical_orientation_with_horizontal_nested
    params = {
      partition_mode: 'vertical',
      partitions: {
        count: 1,
        orientation: 'vertical',
        bays: [
          {
            mode: 'subpartitions',
            subpartitions: {
              count: 2,
              bays: []
            }
          },
          {
            mode: 'fronts_shelves'
          }
        ]
      }
    }

    sanitized, = AICabinets::ParamsSanitizer.sanitize(params)
    layout = AICabinets::Preview::Layout.regions(sanitized)

    assert_equal('vertical', layout[:orientation])
    sub = layout[:bays].first[:subpartitions]
    refute_nil(sub)
    assert_equal('horizontal', sub[:orientation])
    assert_equal(3, sub[:bays].length)
  end

  def test_horizontal_orientation_swaps_nested_orientation
    params = {
      partition_mode: 'horizontal',
      partitions: {
        count: 2,
        bays: [
          {
            mode: 'subpartitions',
            subpartitions: {
              count: 1,
              bays: []
            }
          }
        ]
      }
    }

    sanitized, = AICabinets::ParamsSanitizer.sanitize(params)
    layout = AICabinets::Preview::Layout.regions(sanitized)

    assert_equal('horizontal', layout[:orientation])
    nested = layout[:bays].first[:subpartitions]
    assert_equal('vertical', nested[:orientation])
  end
end
