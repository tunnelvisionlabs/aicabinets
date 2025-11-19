# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/ui/dialogs/fronts_dialog')
load File.expand_path('../../aicabinets/ui/dialogs/fronts_dialog.rb', __dir__)

class TC_FrontsDialogSelection < TestUp::TestCase
  FRONT_TAG_NAME = 'AICabinets/Fronts'.freeze

  def setup
    AICabinetsTestHelper.clean_model!
    reset_fronts_dialog_state
  end

  def teardown
    reset_fronts_dialog_state
    AICabinetsTestHelper.clean_model!
  end

  def test_single_front_selection_ready
    front = create_front_instance('Door (Left)')
    select_entity(front)

    payload = state_payload

    assert_equal('ready', payload[:mode])
    assert_equal('Door (Left)', payload[:target][:name])
  end

  def test_part_selection_lifts_to_front
    front = create_front_instance('Drawer Front')
    part = add_front_part(front.definition)
    select_entity(part)
    override_active_path([front])

    payload = state_payload

    assert_equal('ready', payload[:mode])
    assert_equal('Drawer Front', payload[:target][:name])
  ensure
    clear_active_path_override
  end

  def test_cabinet_single_front_auto_selects
    cabinet = create_cabinet_with_fronts(%w[Door])
    select_entity(cabinet)

    payload = state_payload

    assert_equal('ready', payload[:mode])
    assert_equal('Door', payload[:target][:name])
  end

  def test_cabinet_multiple_fronts_requests_choice
    cabinet = create_cabinet_with_fronts(%w[Left Right])
    select_entity(cabinet)

    payload = state_payload

    assert_equal('choose', payload[:mode])
    assert_equal(2, payload[:candidates].length)
    payload[:candidates].each do |candidate|
      refute_nil(candidate[:persistent_id])
      refute_empty(candidate[:name])
    end
  end

  def test_previously_chosen_front_is_reused
    cabinet = create_cabinet_with_fronts(%w[Left Right])
    select_entity(cabinet)
    payload = state_payload
    candidate = payload[:candidates].first

    remember_selection_signature
    set_target_persistent_id(candidate[:persistent_id])

    payload = state_payload

    assert_equal('ready', payload[:mode])
    assert_equal(candidate[:name], payload[:target][:name])
  end

  def test_message_when_selection_empty
    Sketchup.active_model.selection.clear

    payload = state_payload

    assert_equal('message', payload[:mode])
    refute_empty(payload[:text])
  end

  private

  def state_payload
    AICabinets::UI::Dialogs::FrontsDialog.send(:build_state_payload)
  end

  def select_entity(entity)
    model = Sketchup.active_model
    model.selection.clear
    model.selection.add(entity)
  end

  def create_front_instance(name)
    model = Sketchup.active_model
    definition = model.definitions.add(name)
    face = definition.entities.add_face(
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(500.mm, 0, 0),
      Geom::Point3d.new(500.mm, 0, 700.mm),
      Geom::Point3d.new(0, 0, 700.mm)
    )
    face.pushpull(19.mm)
    instance = model.entities.add_instance(definition, Geom::Transformation.new)
    instance.layer = ensure_front_tag(model)
    instance.name = name if instance.respond_to?(:name=)
    instance
  end

  def add_front_part(definition)
    group = definition.entities.add_group
    group.layer = ensure_front_tag(Sketchup.active_model)
    face = group.entities.add_face(
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(50.mm, 0, 0),
      Geom::Point3d.new(50.mm, 0, 700.mm),
      Geom::Point3d.new(0, 0, 700.mm)
    )
    face.pushpull(5.mm)
    group
  end

  def create_cabinet_with_fronts(names)
    model = Sketchup.active_model
    cabinet_def = model.definitions.add("Cabinet #{names.join('-')}")

    names.each_with_index do |name, index|
      front_def = model.definitions.add("Front #{name}")
      face = front_def.entities.add_face(
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(400.mm, 0, 0),
        Geom::Point3d.new(400.mm, 0, 700.mm),
        Geom::Point3d.new(0, 0, 700.mm)
      )
      face.pushpull(19.mm)
      front_instance = cabinet_def.entities.add_instance(
        front_def,
        Geom::Transformation.translation([index * 450.mm, 0, 0])
      )
      front_instance.layer = ensure_front_tag(model)
      front_instance.name = name if front_instance.respond_to?(:name=)
    end

    model.entities.add_instance(cabinet_def, Geom::Transformation.new)
  end

  def ensure_front_tag(model)
    layers = model.layers
    layers.add(FRONT_TAG_NAME)
  end

  def override_active_path(path)
    AICabinets::UI::Dialogs::FrontsDialog.instance_variable_set(:@active_path_override, Array(path))
  end

  def clear_active_path_override
    AICabinets::UI::Dialogs::FrontsDialog.instance_variable_set(:@active_path_override, nil)
  end

  def remember_selection_signature
    signature = AICabinets::UI::Dialogs::FrontsDialog.send(
      :selection_signature,
      Sketchup.active_model.selection
    )
    AICabinets::UI::Dialogs::FrontsDialog.instance_variable_set(:@target_selection_signature, signature)
  end

  def set_target_persistent_id(persistent_id)
    AICabinets::UI::Dialogs::FrontsDialog.instance_variable_set(:@target_persistent_id, persistent_id)
  end

  def reset_fronts_dialog_state
    AICabinets::UI::Dialogs::FrontsDialog.instance_variable_set(:@target_persistent_id, nil)
    AICabinets::UI::Dialogs::FrontsDialog.instance_variable_set(:@target_selection_signature, nil)
    clear_active_path_override
  end
end
