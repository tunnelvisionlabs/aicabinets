# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/generator/carcass')
Sketchup.require('aicabinets/metadata/naming')
Sketchup.require('aicabinets/metadata/tagging')

class TC_FaceFrameTagging < TestUp::TestCase
  BASIC_PARAMS_MM = {
    width_mm: 762.0,
    depth_mm: 600.0,
    height_mm: 762.0,
    panel_thickness_mm: 19.0,
    toe_kick_height_mm: 100.0,
    toe_kick_depth_mm: 75.0,
    toe_kick_thickness_mm: 19.0,
    back_thickness_mm: 6.0,
    top_thickness_mm: 19.0,
    bottom_thickness_mm: 19.0,
    partition_mode: 'none',
    front: :doors_double,
    door_reveal_mm: 2.0,
    door_gap_mm: 3.0
  }.freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_tag_created_and_applied_to_containers
    params_mm = face_frame_params_mm(
      mid_stile_mm: 30.0,
      mid_rail_mm: 25.0,
      layout: [{ kind: 'drawer_stack', drawers: 4 }]
    )

    _, result = build_carcass_definition(params_mm)
    face_frame = result.instances[:face_frame]

    refute_nil(face_frame, 'Expected face frame container to exist')
    assert_equal('Face Frame', face_frame.name)

    model = Sketchup.active_model
    fronts_tag = AICabinets::Metadata::Tagging.fronts_tag(model)
    refute_nil(fronts_tag, 'Fronts tag should be created on the model')
    assert_same(fronts_tag, face_frame.layer, 'Face frame container should be tagged')

    members = member_groups(face_frame)
    refute_empty(members, 'Expected members to be generated')

    members.each do |member|
      assert_same(fronts_tag, member.layer, 'Member containers should share the fronts tag')
      member.entities.grep(Sketchup::Face).each do |face|
        refute_same(fronts_tag, face.layer, 'Raw faces should remain on the default tag')
      end
      member.entities.grep(Sketchup::Edge).each do |edge|
        refute_same(fronts_tag, edge.layer, 'Raw edges should remain on the default tag')
      end
    end
  end

  def test_member_names_roles_and_mid_rail_ordering
    params_mm = face_frame_params_mm(
      mid_stile_mm: 25.0,
      mid_rail_mm: 20.0,
      layout: [{ kind: 'drawer_stack', drawers: 4 }]
    )

    _, result = build_carcass_definition(params_mm)
    face_frame = result.instances[:face_frame]
    refute_nil(face_frame, 'Face frame should be present when enabled')

    members = member_groups(face_frame)
    names = members.map(&:name).sort
    expected = [
      'Mid Rail 1',
      'Mid Rail 2',
      'Mid Rail 3',
      'Mid Stile',
      'Rail Bottom',
      'Rail Top',
      'Stile Left',
      'Stile Right'
    ].sort
    assert_equal(expected, names, 'Member names should match canonical labels')

    members.reject { |member| member.name.start_with?('Mid Rail') }.each do |member|
      refute_match(/\d/, member.name, 'Non-mid-rail members must not include digits')
    end

    mid_rails = members.select { |member| member.name.start_with?('Mid Rail') }
    sorted_mid_rails = mid_rails.sort_by { |member| member.bounds.min.z }
    sorted_mid_rails.each_with_index do |member, index|
      assert_equal("Mid Rail #{index + 1}", member.name,
                   'Mid rail numbering should progress bottom to top')
    end

    members.each do |member|
      role, index = metadata_for(member)
      refute_nil(role, 'Role attribute should be present')

      if member.name.start_with?('Mid Rail')
        assert_equal('mid_rail', role)
        assert_kind_of(Integer, index)
        assert(index.positive?, 'Mid rail indices should be positive integers')
      else
        refute_equal('mid_rail', role)
        assert_nil(index, 'Only mid rails store index metadata')
      end
    end

    face_role, face_index = metadata_for(face_frame)
    assert_equal(AICabinets::Metadata::Naming::FACE_FRAME_ROLE, face_role)
    assert_nil(face_index)
  end

  def test_regeneration_preserves_naming_and_tagging
    params_mm = face_frame_params_mm(
      mid_stile_mm: 30.0,
      mid_rail_mm: 25.0,
      layout: [{ kind: 'drawer_stack', drawers: 5 }]
    )

    definition, first_result = build_carcass_definition(params_mm)
    initial_signature = signature_for(first_result.instances[:face_frame])

    definition.entities.clear!

    _, rebuilt_result = build_carcass_definition(params_mm, definition: definition)
    rebuilt_signature = signature_for(rebuilt_result.instances[:face_frame])

    assert_equal(initial_signature, rebuilt_signature,
                 'Regeneration should produce the same names, indices, and tags')
  end

  private

  def build_carcass_definition(params_mm, definition: nil)
    model = Sketchup.active_model
    definition ||= model.definitions.add(next_definition_name)
    result = AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params_mm)
    [definition, result]
  end

  def face_frame_params_mm(overrides = {})
    frame_defaults = {
      enabled: true,
      thickness_mm: 19.0,
      stile_left_mm: 38.0,
      stile_right_mm: 38.0,
      rail_top_mm: 38.0,
      rail_bottom_mm: 38.0,
      mid_stile_mm: 0.0,
      mid_rail_mm: 0.0,
      layout: [{ kind: 'double_doors' }]
    }

    frame = frame_defaults.merge(overrides)
    BASIC_PARAMS_MM.merge(face_frame: frame)
  end

  def member_groups(face_frame)
    return [] unless face_frame&.valid?

    face_frame.entities.select do |entity|
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end
  end

  def metadata_for(entity)
    dictionary = entity.attribute_dictionary(AICabinets::Metadata::Naming::DICTIONARY_NAME)
    return [nil, nil] unless dictionary

    role = dictionary[AICabinets::Metadata::Naming::ROLE_KEY]
    index = dictionary[AICabinets::Metadata::Naming::INDEX_KEY]
    index = index.to_i if index && index.respond_to?(:to_i)
    [role, index]
  end

  def signature_for(face_frame)
    return {} unless face_frame&.valid?

    tag_name = face_frame.layer&.name
    members = member_groups(face_frame).map do |member|
      role, index = metadata_for(member)
      {
        name: member.name,
        role: role,
        index: index,
        tag: member.layer&.name
      }
    end.sort_by { |entry| [entry[:role].to_s, entry[:index].to_i, entry[:name]] }

    {
      container_name: face_frame.name,
      container_tag: tag_name,
      members: members
    }
  end

  def next_definition_name
    sequence = self.class.instance_variable_get(:@definition_sequence) || 0
    sequence += 1
    self.class.instance_variable_set(:@definition_sequence, sequence)
    "Face Frame Tagging #{sequence}"
  end
end
