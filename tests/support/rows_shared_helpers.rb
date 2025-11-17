# frozen_string_literal: true

# Shared helpers for placing base cabinets and managing SketchUp selection in
# Rows-focused tests. Consolidating the helpers keeps the consolidated test
# cases lean and ensures each scenario interacts with the model the same way.
module RowsSharedTestHelpers
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

  def base_params_mm
    BASE_PARAMS_MM
  end

  def place_cabinets(model, count: 1, offset_mm: 0.0, params_mm: BASE_PARAMS_MM)
    instances = []

    count.times do |index|
      origin_offset = offset_mm + index * (params_mm[:width_mm] + 5.0)
      point = Geom::Point3d.new(origin_offset.mm, 0, 0)
      instance = AICabinets::Ops::InsertBaseCabinet.place_at_point!(
        model: model,
        point3d: point,
        params_mm: params_mm
      )
      instances << instance
    end

    instances
  end

  def select_instances(model, entities)
    selection = model.selection
    selection.clear
    Array(entities).each { |entity| selection.add(entity) }
    selection
  end
end
