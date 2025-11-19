# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/loader')

class TC_Commands < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
    stub_dialog!
    AICabinets::UI.register_ui!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
    restore_dialog!
  end

  def test_face_frame_commands_registered
    commands = AICabinets::UI.commands

    insert_command = commands[:face_frame_insert]
    edit_command = commands[:face_frame_edit]

    assert_kind_of(UI::Command, insert_command)
    assert_kind_of(UI::Command, edit_command)

    toolbar_commands = AICabinets::UI.send(:toolbar_added_commands)
    assert_includes(toolbar_commands, insert_command)
    assert_includes(toolbar_commands, edit_command)
  end

  def test_edit_validation_matches_selection
    model = Sketchup.active_model
    selection = model.selection
    selection.clear

    assert_equal(false, AICabinets::Commands::FaceFrame.valid_selection?(model: model))

    instance = build_cabinet_instance(model)
    selection.add(instance)

    assert(AICabinets::Commands::FaceFrame.valid_selection?(model: model))
  end

  def test_execute_insert_enables_face_frame_defaults
    dialog = stub_dialog!
    dialog.reset!

    AICabinets::Commands::FaceFrame.execute_insert

    assert_equal(:insert, dialog.last_action)
    payload = dialog.last_payload
    assert_kind_of(Hash, payload)
    assert_equal(true, payload[:face_frame][:enabled])
  end

  def test_execute_edit_shows_message_for_invalid_selection
    messages = []
    UI.singleton_class.alias_method(:__face_frame_messagebox, :messagebox)
    UI.define_singleton_method(:messagebox) do |message, *_args|
      messages << message
      true
    end

    AICabinets::Commands::FaceFrame.execute_edit

    refute_empty(messages)
  ensure
    UI.singleton_class.alias_method(:messagebox, :__face_frame_messagebox)
    UI.singleton_class.remove_method(:__face_frame_messagebox)
  end

  def test_execute_edit_opens_dialog_when_selection_valid
    dialog = stub_dialog!
    dialog.reset!

    model = Sketchup.active_model
    instance = build_cabinet_instance(model)
    model.selection.add(instance)

    AICabinets::Commands::FaceFrame.execute_edit(model: model)

    assert_equal(:edit, dialog.last_action)
    assert_same(instance, dialog.last_instance)
  end

  private

  def build_cabinet_instance(model)
    definition = model.definitions.add('Cabinet')
    dictionary = definition.attribute_dictionary(AICabinets::Ops::InsertBaseCabinet::DICTIONARY_NAME, true)
    dictionary[AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY] = '{}'
    transformation = Geom::Transformation.new
    model.active_entities.add_instance(definition, transformation)
  end

  def stub_dialog!
    return @dialog_stub if defined?(@dialog_stub) && @dialog_stub

    @original_dialog = nil
    if defined?(AICabinets::UI::Dialogs::FaceFrameOptions)
      @original_dialog = AICabinets::UI::Dialogs::FaceFrameOptions
    else
      AICabinets::UI::Dialogs.const_set(:FaceFrameOptions, Module.new)
    end

    dialog = AICabinets::UI::Dialogs::FaceFrameOptions
    dialog.define_singleton_method(:reset!) do
      @last_action = nil
      @last_payload = nil
      @last_instance = nil
    end
    dialog.define_singleton_method(:last_action) { @last_action }
    dialog.define_singleton_method(:last_payload) { @last_payload }
    dialog.define_singleton_method(:last_instance) { @last_instance }
    dialog.define_singleton_method(:show_for_insert) do |defaults:|
      @last_action = :insert
      @last_payload = defaults
    end
    dialog.define_singleton_method(:show_for_edit) do |instance:|
      @last_action = :edit
      @last_instance = instance
    end
    dialog.reset!

    @dialog_stub = dialog
  end

  def restore_dialog!
    return unless defined?(AICabinets::UI::Dialogs::FaceFrameOptions)

    if @original_dialog
      AICabinets::UI::Dialogs.const_set(:FaceFrameOptions, @original_dialog)
    else
      AICabinets::UI::Dialogs.send(:remove_const, :FaceFrameOptions)
    end
    @dialog_stub = nil
    @original_dialog = nil
  end
end
