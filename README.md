# AI Cabinets

This repository contains Ruby scripts for SketchUp that generate simple cabinetry models from code.

## Contents

- `lib/cabinet.rb` – library functions for creating cabinets. The generator builds a frameless carcass from two sides, a top (solid panel or pair of stringers), a bottom, and a back, and can optionally add shelves. Cabinets may also be partitioned with fixed panels so each section can have its own doors or drawers. Panels can be inset using `top_inset`, `bottom_inset`, and `back_inset` options. Use `top_type: :stringers` and `top_stringer_width` (default `100.mm`) to model stringers instead of a full top panel. Door overlays use `door_reveal` for the default gap to cabinet edges, `top_reveal` and `bottom_reveal` can override the edge clearances, and `door_gap` controls spacing between adjacent fronts.
- Panels are now created as SketchUp components rather than groups. A default `Birch Plywood` material is applied to cabinet parts, while doors default to `MDF`. Five-piece doors can specify separate materials for the frame (default `Maple`) and center panel, which defaults to the door material.
  When missing from the model, the generator defines `MDF` as a solid color (RGB 164,143,122), `Maple` as a solid color (RGB 224,200,160), and `Birch Plywood` as a solid color (RGB 222,206,170).
- `examples/frameless_two_shelf_cabinet.rb` – sample script that creates a frameless cabinet with two shelves.
- `examples/shaker_door_cabinet.rb` – demonstrates a rail-and-stile door with an 18° bevel.
- `examples/drawer_cabinet.rb` – shows how to add drawers to a cabinet, mix drawers with doors, and adjust drawer clearances.
- `examples/partitioned_cabinet.rb` – demonstrates dividing a cabinet interior with fixed partitions.

Copy the library and sample code into SketchUp's Ruby console or load them as scripts to build cabinet geometry automatically.

## SketchUp Extension Packaging

Place `aicabinets.rb` and the `aicabinets/` folder inside SketchUp's `Plugins` directory to load AI Cabinets as an extension. The registrar exposes metadata so the Extension Manager lists "AI Cabinets" with version information from `aicabinets/version.rb`. The loader currently performs no modeling or UI work, providing a clean foundation for future commands and dialogs.

To verify Ruby syntax locally, run:

```sh
ruby -c aicabinets.rb && find aicabinets -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
```

To package the extension for manual installation, run:

```sh
zip -r aicabinets-$(ruby -e "load 'aicabinets/version.rb'; puts AICabinets::VERSION").rbz aicabinets.rb aicabinets/
```
