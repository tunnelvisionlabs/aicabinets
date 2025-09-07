# Example of a cabinet with drawers.

require_relative '../lib/cabinet'

AICabinets.create_frameless_cabinet(
  height: 720.mm,
  depth: 350.mm,
  drawer_depth: 300.mm,
  cabinets: [
    {
      width: 600.mm,
      drawers: [
        { height: 100.mm },
        { height: 140.mm }
      ],
      doors: :double
    },
    {
      width: 600.mm,
      drawer_origin: :bottom,
      drawers: [
        { height: 200.mm, depth: 250.mm }
      ],
      doors: :left
    }
  ]
)
