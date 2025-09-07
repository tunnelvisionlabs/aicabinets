# Example of a cabinet with a rail-and-stile (shaker) door.

require_relative '../lib/cabinet'

AICabinets.create_frameless_cabinet(
  height: 720.mm,
  depth: 350.mm,
  door_style: :rail_and_stile,
  bevel_angle: 18.degrees,
  cabinets: [
    {
      width: 600.mm,
      doors: :double
    }
  ]
)
