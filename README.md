# AI Cabinets

This repository contains Ruby scripts for SketchUp that generate simple cabinetry models from code.

## Contents

 - `lib/cabinet.rb` – library functions for creating cabinets. The generator builds a frameless carcass from two sides, a top (solid panel or pair of stringers), a bottom, and a back, and can optionally add shelves. Cabinets may also be partitioned with fixed panels so each section can have its own doors or drawers. Panels can be inset using `top_inset`, `bottom_inset`, and `back_inset` options. Use `top_type: :stringers` and `top_stringer_width` (default `100.mm`) to model stringers instead of a full top panel. Door overlays use `door_reveal` for the gap to cabinet edges and `door_gap` for spacing between adjacent fronts.
- `examples/frameless_two_shelf_cabinet.rb` – sample script that creates a frameless cabinet with two shelves.
- `examples/shaker_door_cabinet.rb` – demonstrates a rail-and-stile door with an 18° bevel.
- `examples/drawer_cabinet.rb` – shows how to add drawers to a cabinet, mix drawers with doors, and adjust drawer clearances.
- `examples/partitioned_cabinet.rb` – demonstrates dividing a cabinet interior with fixed partitions.

Copy the library and sample code into SketchUp's Ruby console or load them as scripts to build cabinet geometry automatically.
