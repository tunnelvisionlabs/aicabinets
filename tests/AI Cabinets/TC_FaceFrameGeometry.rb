# frozen_string_literal: true

require 'testup/testcase'
require_relative 'suite_helper'

Sketchup.require('aicabinets/generator/carcass')

class TC_FaceFrameGeometry < TestUp::TestCase
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

  def test_primary_members_basic_sizing
    params_mm = face_frame_params_mm(
      thickness_mm: 19.0,
      stile_left_mm: 38.0,
      stile_right_mm: 38.0,
      rail_top_mm: 38.0,
      rail_bottom_mm: 38.0
    )

    _, result = build_carcass_definition(params_mm)

    face_frame = result.instances[:face_frame]
    refute_nil(face_frame, 'Expected face frame group to be present')
    assert_equal('Face Frame', face_frame.name)
    assert_equal('AICabinets/Fronts', face_frame.layer.name)

    members = members_by_name(face_frame)
    %w[Stile\ Left Stile\ Right Rail\ Top Rail\ Bottom].each do |part|
      assert(members.key?(part), "Expected member #{part}")
    end

    tol_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)

    left = members['Stile Left']
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, mm(left.bounds.min.x), tol_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, 38.0, span_x_mm(left), tol_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, 762.0, span_z_mm(left), tol_mm)

    right = members['Stile Right']
    AICabinetsTestHelper.assert_within_tolerance(self, 762.0 - 38.0, mm(right.bounds.min.x), tol_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, 38.0, span_x_mm(right), tol_mm)

    top = members['Rail Top']
    AICabinetsTestHelper.assert_within_tolerance(self, 724.0, mm(top.bounds.min.z), tol_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, 38.0, span_z_mm(top), tol_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, 762.0, span_x_mm(top), tol_mm)

    bottom = members['Rail Bottom']
    AICabinetsTestHelper.assert_within_tolerance(self, 0.0, mm(bottom.bounds.min.z), tol_mm)
    AICabinetsTestHelper.assert_within_tolerance(self, 38.0, span_z_mm(bottom), tol_mm)

    members.values.each do |member|
      AICabinetsTestHelper.assert_within_tolerance(self, -19.0, mm(member.bounds.min.y), tol_mm)
      AICabinetsTestHelper.assert_within_tolerance(self, 0.0, mm(member.bounds.max.y), tol_mm)
    end
  end

  def test_mid_members_present_and_spaced
    params_mm = face_frame_params_mm(
      mid_stile_mm: 30.0,
      mid_rail_mm: 25.0,
      layout: [{ kind: 'drawer_stack', drawers: 3 }]
    )

    _, result = build_carcass_definition(params_mm)

    face_frame = result.instances[:face_frame]
    members = members_by_name(face_frame)

    mid_stile = members['Mid Stile']
    refute_nil(mid_stile, 'Expected mid stile when mid_stile_mm > 0')

    mid_rails = members.select { |name, _| name.start_with?('Mid Rail') }
    assert_equal(2, mid_rails.length, 'Expected drawers - 1 mid rails')

    tol_mm = AICabinetsTestHelper.mm(AICabinetsTestHelper::TOL)
    opening_width_mm = params_mm[:width_mm] - params_mm[:face_frame][:stile_left_mm] - params_mm[:face_frame][:stile_right_mm]
    expected_mid_x = params_mm[:face_frame][:stile_left_mm] + ((opening_width_mm - 30.0) / 2.0)
    AICabinetsTestHelper.assert_within_tolerance(self, expected_mid_x, mm(mid_stile.bounds.min.x), tol_mm)

    centers = mid_rails.values.map { |member| mm(member.bounds.center.z) }.sort
    spacing = centers.each_cons(2).map { |first, second| second - first }
    expected_spacing = (params_mm[:height_mm] - params_mm[:face_frame][:rail_top_mm] -
                        params_mm[:face_frame][:rail_bottom_mm]) / 3.0
    spacing.each do |gap|
      assert_in_delta(expected_spacing, gap, expected_spacing * 0.05,
                      'Mid rails should be evenly spaced')
    end
  end

  def test_face_frame_removed_on_undo
    params_mm = face_frame_params_mm
    definition = nil
    face_frame = nil

    AICabinetsTestHelper.with_undo('Build Face Frame') do |_model|
      definition, result = build_carcass_definition(params_mm)
      face_frame = result.instances[:face_frame]
      face_frame
    end

    assert(face_frame&.valid?, 'Expected face frame to exist after build')

    Sketchup.undo

    refute(face_frame&.valid?, 'Expected face frame to be removed after undo')
    refute(face_frame_present?(definition), 'Definition should not retain face frame after undo')
  end

  private

  def build_carcass_definition(params_mm)
    model = Sketchup.active_model
    name = next_definition_name
    definition = model.definitions.add(name)
    result = AICabinets::Generator.build_base_carcass!(parent: definition, params_mm: params_mm)
    [definition, result]
  end

  def face_frame_params_mm(overrides = {})
    frame = {
      enabled: true,
      thickness_mm: 19.0,
      stile_left_mm: 38.0,
      stile_right_mm: 38.0,
      rail_top_mm: 38.0,
      rail_bottom_mm: 38.0,
      mid_stile_mm: 0.0,
      mid_rail_mm: 0.0,
      layout: [{ kind: 'double_doors' }]
    }.merge(overrides)

    BASIC_PARAMS_MM.merge(face_frame: frame)
  end

  def members_by_name(face_frame)
    groups = face_frame.entities.grep(Sketchup::Group)
    groups.each_with_object({}) do |group, memo|
      memo[group.name] = group
    end
  end

  def mm(length)
    AICabinetsTestHelper.mm_from_length(length)
  end

  def span_x_mm(entity)
    mm(entity.bounds.max.x) - mm(entity.bounds.min.x)
  end

  def span_z_mm(entity)
    mm(entity.bounds.max.z) - mm(entity.bounds.min.z)
  end

  def next_definition_name
    sequence = self.class.instance_variable_get(:@definition_sequence) || 0
    sequence += 1
    self.class.instance_variable_set(:@definition_sequence, sequence)
    "Face Frame Geometry #{sequence}"
  end

  def face_frame_present?(definition)
    return false unless definition&.valid?

    definition.entities.grep(Sketchup::Group).any? { |group| group.name == 'Face Frame' }
  end
end
