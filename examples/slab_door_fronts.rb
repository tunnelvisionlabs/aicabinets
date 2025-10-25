# Demonstrates slab door front options for the base cabinet generator.
# Run this script from SketchUp's Ruby console after loading the extension.

require 'sketchup.rb'

Sketchup.require('aicabinets/ops/insert_base_cabinet')

model = Sketchup.active_model
model.start_operation('AI Cabinets — Slab Door Demo', true)

begin
  base_params = {
    width_mm: 600.0,
    depth_mm: 600.0,
    height_mm: 720.0,
    panel_thickness_mm: 18.0,
    toe_kick_height_mm: 100.0,
    toe_kick_depth_mm: 50.0
  }

  fronts = %w[doors_left doors_right doors_double]
  spacing = 700.mm

  fronts.each_with_index do |front, index|
    point = Geom::Point3d.new(index * spacing, 0, 0)
    params = base_params.merge(front: front)
    AICabinets::Ops::InsertBaseCabinet.place_at_point!(
      model: model,
      point3d: point,
      params_mm: params
    )
  end
ensure
  model.commit_operation
end
