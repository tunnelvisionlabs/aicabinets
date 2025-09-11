# Example usage of the AICabinets library.
# Creates two frameless cabinets side by side, demonstrating top, bottom,
# and back insets.

require_relative '../lib/cabinet'

# Build two cabinets using the data structure input.
AICabinets.create_frameless_cabinet(
  height: 720.mm,
  depth: 350.mm,
  panel_thickness: 19.mm,
  back_thickness: 6.mm,
  top_inset: 20.mm,
  bottom_inset: 20.mm,
  back_inset: 10.mm,
  door_thickness: 19.mm,
  door_reveal: 2.mm,
  cabinets: [
    {
      width: 600.mm,
      shelf_count: 2,
      doors: :left,
      hole_columns: [
        { distance: 37.mm, first_hole: 38.mm, count: 20 },
        { distance: 37.mm, from: :rear, first_hole: 38.mm, count: 20 }
      ]
    },
    {
      width: 800.mm,
      shelf_count: 3,
      doors: :double,
      hole_columns: [
        { distance: 37.mm, first_hole: 38.mm, count: 20 },
        { distance: 37.mm, from: :rear, first_hole: 38.mm, count: 20 }
      ]
    }
  ]
)

