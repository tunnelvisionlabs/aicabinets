# Example usage of the AICabinets library.
# Creates a single frameless cabinet with two shelves.

require_relative '../lib/cabinet'

# Build a single cabinet using the data structure input.
AICabinets.create_frameless_cabinet(
  height: 720.mm,
  depth: 350.mm,
  panel_thickness: 19.mm,
  back_thickness: 6.mm,
  cabinets: [
    { width: 600.mm, shelf_count: 2 }
  ]
)

