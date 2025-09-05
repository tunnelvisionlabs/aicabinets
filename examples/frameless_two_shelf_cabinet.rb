# Example usage of the AICabinets library.
# Creates two frameless cabinets side by side.

require_relative '../lib/cabinet'

# Build two cabinets using the data structure input.
AICabinets.create_frameless_cabinet(
  height: 720.mm,
  depth: 350.mm,
  panel_thickness: 19.mm,
  back_thickness: 6.mm,
  cabinets: [
    {
      width: 600.mm,
      shelf_count: 2,
      hole_columns: [
        { distance: 37.mm, first_hole: 38.mm, count: 20 },
        { distance: 37.mm, from: :rear, first_hole: 38.mm, count: 20 }
      ]
    },
    {
      width: 800.mm,
      shelf_count: 3,
      hole_columns: [
        { distance: 37.mm, first_hole: 38.mm, count: 20 },
        { distance: 37.mm, from: :rear, first_hole: 38.mm, count: 20 }
      ]
    }
  ]
)

