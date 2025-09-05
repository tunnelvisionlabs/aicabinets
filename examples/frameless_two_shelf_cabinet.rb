# Example usage of the AICabinets library.
# Creates a single frameless cabinet with two shelves.

require_relative '../lib/cabinet'

AICabinets.create_frameless_cabinet(
  width: 600.mm,
  height: 720.mm,
  depth: 350.mm,
  shelf_count: 2
)

