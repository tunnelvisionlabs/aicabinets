# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/tags')

class TC_TagStructure < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_ensure_structure_creates_folder_and_tag
    skip('SketchUp release does not support tag folders') unless defined?(Sketchup::LayerFolder)

    model = Sketchup.active_model

    tag = AICabinets::Tags.ensure_structure!(model)

    layers = model.layers
    folder = find_folder(layers, AICabinets::Tags::CABINET_FOLDER_NAME)

    refute_nil(folder, 'Expected AICabinets folder to be created')
    assert_kind_of(Sketchup::LayerFolder, folder)

    assert(tag&.valid?, 'Expected ensure_structure! to return a valid tag')
    assert_equal(AICabinets::Tags::CABINET_TAG_NAME, tag.name)
    assert_same(folder, tag.folder)

    folder_layers = layers_in_folder(folder)
    refute_nil(folder_layers['Cabinet'], 'Cabinet tag should live inside the AICabinets folder')
    refute(folder_layers.key?('AICabinets/Cabinet'), 'Slash-named tags should not remain in the folder')

    legacy = layers[AICabinets::Tags::LEGACY_CABINET_TAG_NAME]
    assert_nil(legacy, 'Legacy slash-named tag should not remain after ensuring structure')
  end

  def test_ensure_structure_migrates_legacy_tag_preserving_visibility
    skip('SketchUp release does not support tag folders') unless defined?(Sketchup::LayerFolder)

    model = Sketchup.active_model
    layers = model.layers

    legacy = layers.add(AICabinets::Tags::LEGACY_CABINET_TAG_NAME)
    legacy.visible = false

    tag = AICabinets::Tags.ensure_structure!(model)

    assert_equal(AICabinets::Tags::CABINET_TAG_NAME, tag.name)
    assert_equal(false, tag.visible?, 'Migrated tag should preserve legacy visibility state')

    folder = find_folder(layers, AICabinets::Tags::CABINET_FOLDER_NAME)
    refute_nil(folder, 'Expected migration to create the AICabinets folder')
    assert_same(folder, tag.folder)

    folder_layers = layers_in_folder(folder)
    assert(folder_layers.key?('Cabinet'), 'Migrated tag should be stored inside the folder without the slash prefix')

    legacy_after = layers[AICabinets::Tags::LEGACY_CABINET_TAG_NAME]
    assert_nil(legacy_after, 'Legacy slash-named tag should no longer be present')
  end

  def test_ensure_structure_handles_user_cabinet_tag_collision
    skip('SketchUp release does not support tag folders') unless defined?(Sketchup::LayerFolder)

    model = Sketchup.active_model
    layers = model.layers

    user_tag = layers.add('Cabinet')
    user_tag.visible = true

    tag = AICabinets::Tags.ensure_structure!(model)

    refute_same(user_tag, tag, 'Extension should not repurpose user-owned Cabinet tag')
    assert_equal('Cabinet', user_tag.name, 'User-owned tag should remain untouched')

    assert_equal(AICabinets::Tags::CABINET_TAG_COLLISION_NAME, tag.name)

    folder = find_folder(layers, AICabinets::Tags::CABINET_FOLDER_NAME)
    refute_nil(folder, 'Expected folder to exist after handling collision')
    assert_same(folder, tag.folder)

    folder_layers = layers_in_folder(folder)
    assert(folder_layers.key?(AICabinets::Tags::CABINET_TAG_COLLISION_NAME),
           'Collision tag should be stored within the AICabinets folder')
  end

  def test_ensure_structure_migrates_other_owned_tags
    skip('SketchUp release does not support tag folders') unless defined?(Sketchup::LayerFolder)

    model = Sketchup.active_model
    layers = model.layers

    layers.add('AICabinets/Sides')
    fronts = layers.add('AICabinets/Fronts')
    fronts.visible = false

    tag = AICabinets::Tags.ensure_structure!(model)

    folder = find_folder(layers, AICabinets::Tags::CABINET_FOLDER_NAME)
    refute_nil(folder, 'Expected folder to exist after migrating owned tags')

    folder_layers = layers_in_folder(folder)
    assert(folder_layers.key?('Cabinet'), 'Cabinet tag should exist in folder after migration')

    migrated_sides = folder_layers['Sides']
    refute_nil(migrated_sides, 'Sides tag should be placed within the folder')
    assert_equal('Sides', migrated_sides.name)

    migrated_fronts = folder_layers['Fronts']
    refute_nil(migrated_fronts, 'Fronts tag should be placed within the folder')
    assert_equal(false, migrated_fronts.visible?, 'Tag visibility should be preserved during migration')

    assert_nil(layers['AICabinets/Sides'], 'Legacy sides tag should be renamed')
    assert_nil(layers['AICabinets/Fronts'], 'Legacy fronts tag should be renamed')
  end

  private

  def find_folder(layers, name)
    return unless layers.respond_to?(:folders)

    layers.folders.find do |folder|
      folder.respond_to?(:display_name) && folder.display_name.to_s == name
    end
  end

  def layers_in_folder(folder)
    return {} unless folder.respond_to?(:layers)

    folder.layers.each_with_object({}) do |tag, hash|
      hash[tag.name.to_s] = tag
    end
  end
end
