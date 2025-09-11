# Example of a cabinet with drawers.

require_relative '../lib/cabinet'

AICabinets.create_frameless_cabinet(
  height: 720.mm,
  depth: 350.mm,
  drawer_slide: :salice_progressa_plus_standard_us,
  cabinets: [
    {
      width: 600.mm,
      drawers: [
        { pitch: 3 },
        { pitch: 4 }
      ],
      doors: :double
    },
    {
      width: 600.mm,
      drawer_origin: :bottom,
      drawers: [
        { pitch: 6 }
      ],
      drawer_bottom_clearance: 20.mm,
      drawer_top_clearance: 10.mm,
      doors: :left
    }
  ]
)
