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

Place `aicabinets.rb` and the `aicabinets/` folder inside SketchUp's `Plugins` directory to load AI Cabinets as an extension. The registrar exposes metadata so the Extension Manager lists "AI Cabinets" with version information from `aicabinets/version.rb`. The loader registers UI commands and toolbars without creating geometry at load time, keeping startup cost minimal while exposing extension entry points.

To verify Ruby syntax locally, run:

```sh
ruby -c aicabinets.rb && find aicabinets -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
```

To package the extension for manual installation, run:

```sh
zip -r aicabinets-$(ruby -e "load 'aicabinets/version.rb'; puts AICabinets::VERSION").rbz aicabinets.rb aicabinets/
```

## Install (SketchUp 2026, unsigned RBZ)

1. Open **Extension Manager** from the **Extensions** menu or its toolbar icon.
2. Click **Install Extension…**, choose the downloaded `aicabinets-<VERSION>.rbz`, and confirm SketchUp’s warning for third-party packages. [SketchUp Help: Manually Installing Extensions](https://help.sketchup.com/en/sketchup/installing-extensions)
3. If SketchUp 2026 blocks the load because the extension is **Unsigned**, open **Extension Manager → Settings (gear)** and review the **Loading Policy**, selecting the mode that matches your security posture. SketchUp documents the three modes—**Identified Extensions Only**, **Approve Unidentified Extensions**, and **Unrestricted**—in its [Loading Policy Preferences](https://help.sketchup.com/en/sketchup/loading-policy-preferences) guide. Changes may require restarting SketchUp before the unsigned extension loads.
4. Only install RBZ files from sources you trust. **Unrestricted** allows all extensions and is the least secure option.
5. Enable the extension in Extension Manager if it did not auto-activate after installation.

## Extension UI

After installing the extension, launch its placeholder action from **Extensions → AI Cabinets → Insert Base Cabinet…** or by showing the **AI Cabinets** toolbar. Both entry points share the same command, which currently opens a simple placeholder message while the full cabinet insertion dialog is under development.

## Partition Options

Generated base cabinets accept a `partitions` payload to divide the interior into bays.

- `mode` determines how partitions are created:
  - `none` omits partitions.
  - `even` spaces `count` partitions so the resulting `count + 1` bays have nearly equal clear widths.
  - `positions` places partitions at explicit offsets measured in millimeters from the cabinet’s left outside face to each partition’s left face.
- Partitions use the carcass panel thickness (or an explicit `panel_thickness_mm` value when provided) and span the interior height (top of the bottom panel to the underside of the top or stringers) and depth (front face to the back panel).
- Invalid or overlapping requests are ignored, and the generator logs warnings when positions are clamped to the cabinet interior or discarded because they violate minimum bay widths.
