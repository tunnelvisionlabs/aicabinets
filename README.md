# AI Cabinets

This repository contains Ruby scripts for SketchUp that generate simple cabinetry models from code.

## Contents

- `lib/cabinet.rb` – library functions for creating cabinets. The generator builds a frameless carcass from two sides, a top, a bottom, and a back, and can optionally add shelves.
- `examples/frameless_two_shelf_cabinet.rb` – sample script that creates a frameless cabinet with two shelves.
- `examples/shaker_door_cabinet.rb` – demonstrates a rail-and-stile door with an 18° bevel.
- `examples/drawer_cabinet.rb` – shows how to add drawers to a cabinet, mix drawers with doors, and adjust drawer clearances.

Copy the library and sample code into SketchUp's Ruby console or load them as scripts to build cabinet geometry automatically.
