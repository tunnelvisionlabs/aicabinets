# frozen_string_literal: true

require 'sketchup.rb'

Sketchup.require('aicabinets/geometry/five_piece')
Sketchup.require('aicabinets/ops/materials')
Sketchup.require('aicabinets/params/five_piece')

module AICabinets
  module Appearance
    module_function

    FRONT_AXIS = Geom::Vector3d.new(0, 1, 0).freeze
    ORIENTATION_TOLERANCE = 0.9

    def apply_five_piece_materials!(definition:, params:)
      definition = ensure_definition(definition)
      model = definition.model
      raise ArgumentError, 'Definition has no owning model' unless model

      validated = AICabinets::Params::FivePiece.validate!(params: params)

      frame_material = resolve_material(
        model: model,
        id: validated[:frame_material_id],
        fallback_name: AICabinets::Ops::Materials::DEFAULT_DOOR_FRAME_MATERIAL_NAME
      )
      panel_material = resolve_material(
        model: model,
        id: validated[:panel_material_id],
        fallback_name: AICabinets::Ops::Materials::DEFAULT_DOOR_MATERIAL_NAME
      )

      applied = { frame: false, panel: false }

      frame_faces = frame_front_faces(definition)
      if frame_material
        applied[:frame] = true if frame_faces[:stiles].any? || frame_faces[:rails].any?
        apply_material(frame_faces[:stiles], frame_material, orientation: :vertical)
        apply_material(frame_faces[:rails], frame_material, orientation: :horizontal)
      end

      panel_faces = panel_front_faces(definition)
      if panel_material && panel_faces.any?
        grain = normalize_grain(validated[:panel_grain])
        apply_material(panel_faces, panel_material, orientation: grain)
        applied[:panel] = true
      end

      { applied: applied, warnings: [] }
    end

    def resolve_material(model:, id:, fallback_name:)
      raise ArgumentError, 'model must be a Sketchup::Model' unless model.is_a?(Sketchup::Model)

      materials = model.materials
      material_id = id.to_s

      unless material_id.empty?
        material = materials[material_id] || materials.add(material_id)
        return material if material
      end

      fallback = fallback_name.to_s
      return nil if fallback.empty?

      materials[fallback] || materials.add(fallback)
    rescue StandardError
      nil
    end

    def orient_front_face!(face:, orientation:, scale_mm: nil)
      return unless face&.valid?
      material = face.material
      texture = material&.texture
      return unless material
      return unless texture

      origin, u_point, v_point = mapping_points(face.bounds, orientation)

      u_point.x = origin.x + ((u_point.x - origin.x) * scale_factor(scale_mm))
      v_point.z = origin.z + ((v_point.z - origin.z) * scale_factor(scale_mm))

      face.position_material(material, u_point, v_point, origin, true)
    rescue StandardError
      nil
    end

    def mapping_points(bounds, _orientation)
      y = (bounds.min.y + bounds.max.y) / 2.0
      origin = Geom::Point3d.new(bounds.min.x, y, bounds.min.z)
      u_point = Geom::Point3d.new(bounds.max.x, y, bounds.min.z)
      v_point = Geom::Point3d.new(bounds.min.x, y, bounds.max.z)
      [origin, u_point, v_point]
    end
    private_class_method :mapping_points

    def scale_factor(scale_mm)
      return 1.0 unless scale_mm.is_a?(Numeric) && scale_mm.positive?

      scale_mm.to_f
    end
    private_class_method :scale_factor

    def apply_material(faces, material, orientation: :vertical)
      faces.each do |face|
        next unless face&.valid?

        face.material = material
        orient_front_face!(face: face, orientation: orientation)
      end
      assign_group_materials(faces, material)
    end
    private_class_method :apply_material

    def assign_group_materials(faces, material)
      groups = faces.map(&:parent).grep(Sketchup::Group)
      groups.each do |group|
        group.material = material if group.respond_to?(:material=)
      end
    end
    private_class_method :assign_group_materials

    def frame_front_faces(definition)
      groups = definition.entities.grep(Sketchup::Group)

      stiles = groups.select do |group|
        dictionary = group.attribute_dictionary(AICabinets::Geometry::FivePiece::GROUP_DICTIONARY)
        dictionary && dictionary[AICabinets::Geometry::FivePiece::GROUP_ROLE_KEY] ==
          AICabinets::Geometry::FivePiece::GROUP_ROLE_STILE
      end

      rails = groups.select do |group|
        dictionary = group.attribute_dictionary(AICabinets::Geometry::FivePiece::GROUP_DICTIONARY)
        dictionary && dictionary[AICabinets::Geometry::FivePiece::GROUP_ROLE_KEY] ==
          AICabinets::Geometry::FivePiece::GROUP_ROLE_RAIL
      end

      {
        stiles: front_faces_for_groups(stiles),
        rails: front_faces_for_groups(rails)
      }
    end
    private_class_method :frame_front_faces

    def panel_front_faces(definition)
      groups = definition.entities.grep(Sketchup::Group).select do |group|
        dictionary = group.attribute_dictionary(AICabinets::Geometry::FivePiece::PANEL_DICTIONARY)
        dictionary &&
          dictionary[AICabinets::Geometry::FivePiece::PANEL_ROLE_KEY] ==
            AICabinets::Geometry::FivePiece::PANEL_ROLE_VALUE
      end

      front_faces_for_groups(groups)
    end
    private_class_method :panel_front_faces

    def front_faces_for_groups(groups)
      groups.flat_map do |group|
        group.entities.grep(Sketchup::Face).select { |face| front_face?(face) }
      end
    end
    private_class_method :front_faces_for_groups

    def front_face?(face)
      return false unless face&.valid?

      normal = face.normal.clone
      normal.normalize!
      normal.dot(FRONT_AXIS) >= ORIENTATION_TOLERANCE
    rescue StandardError
      false
    end
    private_class_method :front_face?

    def ensure_definition(definition)
      raise ArgumentError, 'ComponentDefinition is required' unless definition
      raise ArgumentError, 'ComponentDefinition is no longer valid' unless definition.valid?

      definition
    end
    private_class_method :ensure_definition

    def normalize_grain(value)
      grain = value.respond_to?(:to_sym) ? value.to_sym : :vertical
      grain == :horizontal ? :horizontal : :vertical
    end
    private_class_method :normalize_grain
  end
end
