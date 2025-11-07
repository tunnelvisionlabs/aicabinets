# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/ops/insert_base_cabinet')
Sketchup.require('aicabinets/ops/edit_base_cabinet')

class TC_EditInPlace < TestUp::TestCase
  BASE_PARAMS_MM = {
    width_mm: 762.0,
    depth_mm: 610.0,
    height_mm: 762.0,
    panel_thickness_mm: 19.0,
    toe_kick_height_mm: 102.0,
    toe_kick_depth_mm: 76.0,
    toe_kick_thickness_mm: 19.0,
    back_thickness_mm: 6.0,
    top_thickness_mm: 19.0,
    bottom_thickness_mm: 19.0,
    shelf_count: 1,
    shelf_thickness_mm: 19.0
  }.freeze

  WIDTH_DELTA_MM = 89.0

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_edit_updates_owned_entities_in_place
    model = Sketchup.active_model
    instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: ORIGIN,
      params_mm: BASE_PARAMS_MM
    )
    definition = instance.definition

    before_owned = owned_entities(definition)
    refute_empty(before_owned, 'Expected initial cabinet to create owned entities')

    model.selection.clear
    model.selection.add(instance)

    updated_params = BASE_PARAMS_MM.merge(width_mm: BASE_PARAMS_MM[:width_mm] + WIDTH_DELTA_MM)
    result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated_params,
      scope: 'instance'
    )
    assert(result[:ok], "Expected edit operation to succeed: #{result.inspect}")

    after_owned = owned_entities(definition)
    assert_equal(before_owned.length, after_owned.length,
                 'Edit should update existing parts in place instead of duplicating them')

    model.selection.clear
    model.selection.add(instance)

    second_result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
      model: model,
      params_mm: updated_params,
      scope: 'instance'
    )
    assert(second_result[:ok], "Expected idempotent edit to succeed: #{second_result.inspect}")

    second_owned = owned_entities(definition)
    assert_equal(after_owned.length, second_owned.length,
                 'Repeated edits with identical params should remain idempotent')
  end

  private

  def owned_entities(definition)
    definition.entities.select { |entity| owned_entity?(entity) }
  end

  def owned_entity?(entity)
    return false unless entity&.valid?
    return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    layer = entity.respond_to?(:layer) ? entity.layer : nil
    return false unless layer
    return false if layer.respond_to?(:valid?) && !layer.valid?

    owned_tag?(layer)
  end

  def owned_tag?(layer)
    name = layer_name(layer)
    category = tag_category(layer)

    wrapper_names = [
      AICabinets::Ops::EditBaseCabinet::WRAPPER_TAG_NAME,
      AICabinets::Tags::CABINET_TAG_NAME,
      AICabinets::Tags::CABINET_TAG_COLLISION_NAME
    ]

    return false if wrapper_names.include?(name) &&
                    category == AICabinets::Tags::CABINET_TAG_NAME

    return true if name.start_with?('AICabinets/')
    return true unless category.empty?

    false
  end

  def layer_name(layer)
    return '' unless layer.respond_to?(:name)

    name = layer.name
    name.is_a?(String) ? name : name.to_s
  end

  def tag_category(layer)
    return '' unless layer.respond_to?(:get_attribute)

    value = layer.get_attribute(
      AICabinets::Tags::TAG_DICTIONARY,
      AICabinets::Tags::TAG_CATEGORY_KEY
    )
    return value if value.is_a?(String)

    value.to_s
  rescue StandardError
    ''
  end
end
