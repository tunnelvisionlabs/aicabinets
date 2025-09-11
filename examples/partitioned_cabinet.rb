# Example of a cabinet divided into sections with fixed partitions.

require_relative '../lib/cabinet'

AICabinets.create_frameless_cabinet(
  height: 720.mm,
  depth: 350.mm,
  panel_thickness: 18.mm,
  cabinets: [
    {
      width: 536.mm,
      partitions: [
        { width: 100.mm, doors: :left },
        { drawers: [ { pitch: 3 } ] },
        { drawers: [ { pitch: 3 } ] },
        { width: 150.mm, doors: :right }
      ]
    }
  ]
)
