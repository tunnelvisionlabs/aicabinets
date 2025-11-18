# frozen_string_literal: true

require 'testup/testcase'

require_relative 'suite_helper'

Sketchup.require('aicabinets/ui/dialogs/insert_base_cabinet_dialog')

class TC_FaceFrameDialogHandlers < TestUp::TestCase
  def setup
    AICabinetsTestHelper.clean_model!
    set_model_units!(:architectural)
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_face_frame_lengths_parse_via_to_l
    raw = base_payload
    raw[:face_frame] = {
      enabled: true,
      thickness_mm: "1'",
      stile_left_mm: "1 1/2\"",
      stile_right_mm: '38mm',
      rail_top_mm: '1 ft 2 in',
      rail_bottom_mm: '25.4',
      mid_stile_mm: '0',
      mid_rail_mm: '0',
      reveal_mm: '1/8"',
      overlay_mm: '1/2"',
      layout: [{ kind: 'double_doors' }]
    }

    params = build_params(raw)
    face_frame = params[:face_frame]

    assert_in_delta(304.8, face_frame[:thickness_mm], 0.1)
    assert_in_delta(38.1, face_frame[:stile_left_mm], 0.1)
    assert_in_delta(38.0, face_frame[:stile_right_mm], 0.1)
    assert_equal([{ kind: 'double_doors' }], face_frame[:layout])
  end

  def test_face_frame_validation_maps_field
    raw = base_payload
    raw[:face_frame] = {
      enabled: true,
      thickness_mm: '10',
      stile_left_mm: '10',
      stile_right_mm: '10',
      rail_top_mm: '10',
      rail_bottom_mm: '10',
      mid_stile_mm: '0',
      mid_rail_mm: '0',
      reveal_mm: '-1',
      overlay_mm: '10',
      layout: [{ kind: 'double_doors' }]
    }

    error = assert_raises(AICabinets::UI::Dialogs::InsertBaseCabinet::PayloadError) do
      build_params(raw)
    end

    assert_equal('face_frame.reveal_mm', error.field)
  end

  private

  def build_params(raw)
    AICabinets::UI::Dialogs::InsertBaseCabinet.__send__(:build_typed_params, raw)
  end

  def base_payload
    {
      width_mm: 800.0,
      depth_mm: 600.0,
      height_mm: 720.0,
      panel_thickness_mm: 19.0,
      toe_kick_height_mm: 90.0,
      toe_kick_depth_mm: 70.0,
      front: 'doors_double',
      shelves: 0,
      partition_mode: 'none',
      partitions: { mode: 'none', count: 0, positions_mm: [], bays: [] }
    }
  end

  def set_model_units!(format)
    model = Sketchup.active_model
    options = model.options['UnitsOptions']
    return unless options

    case format
    when :architectural
      options['LengthUnit'] = 1
      options['LengthFormat'] = 3
    end
  end
end
