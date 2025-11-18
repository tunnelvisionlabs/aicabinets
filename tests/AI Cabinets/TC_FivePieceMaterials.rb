# frozen_string_literal: true

require 'testup/testcase'
require 'base64'
require_relative 'suite_helper'

Sketchup.require('aicabinets/appearance')
Sketchup.require('aicabinets/geometry/five_piece')
Sketchup.require('aicabinets/geometry/five_piece_panel')
Sketchup.require('aicabinets/params/five_piece')

class TC_FivePieceMaterials < TestUp::TestCase
  TEXTURE_DATA = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8//8/AwAI/AL+gnHe3wAAAABJRU5ErkJggg=='.freeze

  def setup
    AICabinetsTestHelper.clean_model!
  end

  def teardown
    AICabinetsTestHelper.clean_model!
  end

  def test_applies_materials_and_orientation_defaults
    params = base_params.merge(
      frame_material_id: textured_material('FrameTexture').name,
      panel_material_id: textured_material('PanelTexture').name
    )

    definition = Sketchup.active_model.definitions.add('Five Piece Material AC1')

    build_frame_and_panel(definition, params)

    stiles = frame_faces_by_role(definition, AICabinets::Geometry::FivePiece::GROUP_ROLE_STILE)
    rails = frame_faces_by_role(definition, AICabinets::Geometry::FivePiece::GROUP_ROLE_RAIL)
    panel = panel_front_faces(definition)

    refute_empty(stiles)
    refute_empty(rails)
    refute_empty(panel)

    stiles.each { |face| assert_equal('FrameTexture', face.material.name) }
    rails.each { |face| assert_equal('FrameTexture', face.material.name) }
    panel.each { |face| assert_equal('PanelTexture', face.material.name) }

    assert_vertical_grain(stiles.first)
    assert_horizontal_grain(rails.first)
    assert_vertical_grain(panel.first)
  end

  def test_panel_respects_horizontal_grain_override
    params = base_params.merge(
      panel_material_id: textured_material('PanelOverride').name,
      panel_grain: 'horizontal'
    )

    definition = Sketchup.active_model.definitions.add('Five Piece Material AC4')

    build_frame_and_panel(definition, params)

    panel = panel_front_faces(definition)
    refute_empty(panel)

    assert_horizontal_grain(panel.first)
  end

  def test_regeneration_reapplies_persisted_materials
    params = base_params.merge(
      frame_material_id: textured_material('FramePersist').name,
      panel_material_id: textured_material('PanelPersist').name
    )

    definition = Sketchup.active_model.definitions.add('Five Piece Material AC5')
    AICabinets::Params::FivePiece.write!(definition, params: params, scope: :definition)

    build_frame_and_panel(definition, params)

    reloaded = AICabinets::Params::FivePiece.read(definition)
    assert_equal('FramePersist', reloaded[:frame_material_id])
    assert_equal('PanelPersist', reloaded[:panel_material_id])

    AICabinets::Geometry::FivePiece.build_frame!(
      target: definition,
      params: reloaded,
      open_w_mm: 640.0,
      open_h_mm: 780.0
    )

    stiles = frame_faces_by_role(definition, AICabinets::Geometry::FivePiece::GROUP_ROLE_STILE)
    panel = panel_front_faces(definition)

    stiles.each { |face| assert_equal('FramePersist', face.material.name) }
    panel.each { |face| assert_equal('PanelPersist', face.material.name) }
  end

  def test_material_application_is_idempotent
    params = base_params.merge(
      frame_material_id: textured_material('FrameStable').name,
      panel_material_id: textured_material('PanelStable').name
    )

    definition = Sketchup.active_model.definitions.add('Five Piece Material AC7')

    build_frame_and_panel(definition, params)

    initial_materials = definition.model.materials.map(&:name)

    result = AICabinets::Appearance.apply_five_piece_materials!(
      definition: definition,
      params: params
    )

    assert_kind_of(Hash, result)
    assert_equal(initial_materials.sort, definition.model.materials.map(&:name).sort)
  end

  def test_color_only_materials_apply_without_uv_assertion
    params = base_params.merge(panel_material_id: color_only_material('PlainPanel').name)
    definition = Sketchup.active_model.definitions.add('Five Piece Material AC6')

    result = build_frame_and_panel(definition, params)

    assert(result)

    faces = panel_front_faces(definition)
    refute_empty(faces)
    faces.each { |face| assert_equal('PlainPanel', face.material.name) }
  end

  private

  def base_params
    AICabinets::Params::FivePiece.defaults.merge(
      door_thickness_mm: 19.0,
      groove_width_mm: 18.0
    )
  end

  def build_frame_and_panel(definition, params)
    AICabinets::Geometry::FivePiece.build_frame!(
      target: definition,
      params: params,
      open_w_mm: 620.0,
      open_h_mm: 740.0
    )

    AICabinets::Geometry::FivePiecePanel.build_panel!(
      target: definition,
      params: params,
      open_w_mm: 620.0,
      open_h_mm: 740.0
    )
  end

  def front_faces_for(groups)
    groups.flat_map do |group|
      group.entities.grep(Sketchup::Face).select do |face|
        normal = face.normal.clone
        normal.normalize!
        normal.dot(Geom::Vector3d.new(0, 1, 0)) >= 0.9
      end
    end
  end

  def frame_faces_by_role(definition, role)
    groups = definition.entities.grep(Sketchup::Group).select do |group|
      dictionary = group.attribute_dictionary(AICabinets::Geometry::FivePiece::GROUP_DICTIONARY)
      dictionary && dictionary[AICabinets::Geometry::FivePiece::GROUP_ROLE_KEY] == role
    end

    front_faces_for(groups)
  end

  def panel_front_faces(definition)
    groups = definition.entities.grep(Sketchup::Group).select do |group|
      dictionary = group.attribute_dictionary(AICabinets::Geometry::FivePiece::PANEL_DICTIONARY)
      dictionary && dictionary[AICabinets::Geometry::FivePiece::PANEL_ROLE_KEY] ==
        AICabinets::Geometry::FivePiece::PANEL_ROLE_VALUE
    end

    front_faces_for(groups)
  end

  def textured_material(name)
    materials = Sketchup.active_model.materials
    existing = materials[name]
    return existing if existing&.texture

    path = File.join(Sketchup.temp_dir, "#{name}.png")
    File.binwrite(path, Base64.decode64(TEXTURE_DATA))

    material = materials.add(name)
    material.texture = path
    material
  end

  def color_only_material(name)
    materials = Sketchup.active_model.materials
    existing = materials[name]
    return existing if existing

    material = materials.add(name)
    material.color = Sketchup::Color.new(120, 120, 120)
    material
  end

  def uv_delta(face, origin, target)
    helper = face.get_UVHelper(true, false, face.material)
    uv_origin = helper.get_front_UVQ(origin)
    uv_target = helper.get_front_UVQ(target)
    [uv_target.x - uv_origin.x, uv_target.y - uv_origin.y]
  end

  def assert_vertical_grain(face)
    skip('Color-only material; UV mapping not applicable') unless face.material&.texture

    bbox = face.bounds
    y = (bbox.min.y + bbox.max.y) / 2.0
    origin = Geom::Point3d.new(bbox.min.x, y, bbox.min.z)
    target = Geom::Point3d.new(bbox.min.x, y, bbox.max.z)

    du, dv = uv_delta(face, origin, target)
    assert(dv.abs >= (du.abs * 4.0), 'Vertical grain expected to vary V across +Z')
  end

  def assert_horizontal_grain(face)
    skip('Color-only material; UV mapping not applicable') unless face.material&.texture

    bbox = face.bounds
    y = (bbox.min.y + bbox.max.y) / 2.0
    origin = Geom::Point3d.new(bbox.min.x, y, bbox.min.z)
    target = Geom::Point3d.new(bbox.max.x, y, bbox.min.z)

    du, dv = uv_delta(face, origin, target)
    assert(du.abs >= (dv.abs * 4.0), 'Horizontal grain expected to vary U across +X')
  end
end
