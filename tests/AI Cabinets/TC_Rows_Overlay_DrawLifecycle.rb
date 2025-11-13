# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/rows')
Sketchup.require('aicabinets/ops/insert_base_cabinet')

class TC_Rows_Overlay_DrawLifecycle < TestUp::TestCase
  BASE_PARAMS_MM = {
    width_mm: 762.0,
    depth_mm: 609.6,
    height_mm: 914.4,
    panel_thickness_mm: 18.0,
    toe_kick_height_mm: 101.6,
    toe_kick_depth_mm: 76.2,
    bay_count: 1,
    partitions_enabled: false,
    fronts_enabled: false
  }.freeze

  def setup
    AICabinetsTestHelper.clean_model!
    AICabinets::Rows::Highlight.reset!
    AICabinets::Rows::Highlight.test_clear_override!
  end

  def teardown
    AICabinets::Rows::Highlight.test_clear_override!
    AICabinets::Rows::Highlight.reset!
    AICabinetsTestHelper.clean_model!
  end

  def test_overlay_registers_and_clears
    model = Sketchup.active_model
    first, second = place_cabinets(model, count: 2)

    select_instances(model, [first, second])
    row_id = AICabinets::Rows.create_from_selection(model: model)
    assert_kind_of(String, row_id)

    provider = FakeProvider.new
    AICabinets::Rows::Highlight.test_override_provider(
      strategy: :overlay,
      factory: ->(_model) { provider }
    )

    result = AICabinets::Rows.highlight(model: model, row_id: row_id, enabled: true)
    assert_kind_of(Hash, result)
    assert_equal(:overlay, result[:strategy])
    assert_equal(row_id, AICabinets::Rows::Highlight.active_row_id(model: model))

    assert_equal(1, provider.show_calls, 'Expected provider to receive one show call')
    refute_nil(provider.last_geometry, 'Expected geometry to be passed to provider')
    refute_empty(provider.last_geometry.polyline, 'Expected polyline to contain row points')

    result = AICabinets::Rows.highlight(model: model, row_id: row_id, enabled: false)
    assert_kind_of(Hash, result)
    assert_equal(:overlay, result[:strategy])
    assert_nil(AICabinets::Rows::Highlight.active_row_id(model: model))
    assert_equal(1, provider.hide_calls, 'Expected provider to receive one hide call')
  end

  private

  def place_cabinets(model, count: 1)
    instances = []

    count.times do |index|
      offset_mm = index * (BASE_PARAMS_MM[:width_mm] + 5.0)
      point = ::Geom::Point3d.new(offset_mm.mm, 0, 0)
      instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
        model: model,
        point3d: point,
        params_mm: BASE_PARAMS_MM
      )
      instances << instance
    end

    instances
  end

  def select_instances(model, entities)
    selection = model.selection
    selection.clear
    entities.each { |entity| selection.add(entity) }
  end

  class FakeProvider
    attr_reader :show_calls, :hide_calls, :last_geometry

    def initialize
      @show_calls = 0
      @hide_calls = 0
      @last_geometry = nil
    end

    def show(geometry)
      @show_calls += 1
      @last_geometry = geometry
    end

    def hide
      @hide_calls += 1
    end

    def valid?
      true
    end

    def invalid?
      false
    end
  end
end
