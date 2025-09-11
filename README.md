# AI Cabinets

This repository contains Ruby scripts for SketchUp that generate simple cabinetry models from code.

## Contents

 - `lib/cabinet.rb` – library functions for creating cabinets. The generator builds a frameless carcass from two sides, a top (solid panel or pair of stringers), a bottom, and a back, and can optionally add shelves. Cabinets may also be partitioned with fixed panels so each section can have its own doors or drawers. Panels can be inset using `top_inset`, `bottom_inset`, and `back_inset` options. Use `top_type: :stringers` and `top_stringer_width` (default `100.mm`) to model stringers instead of a full top panel. Door overlays use `door_reveal` for the default gap to cabinet edges, `top_reveal` and `bottom_reveal` can override the edge clearances, and `door_gap` controls spacing between adjacent fronts.
- `examples/frameless_two_shelf_cabinet.rb` – sample script that creates a frameless cabinet with two shelves.
- `examples/shaker_door_cabinet.rb` – demonstrates a rail-and-stile door with an 18° bevel.
- `examples/drawer_cabinet.rb` – shows how to add drawers to a cabinet, mix drawers with doors, and adjust drawer clearances.
- `examples/partitioned_cabinet.rb` – demonstrates dividing a cabinet interior with fixed partitions.

Copy the library and sample code into SketchUp's Ruby console or load them as scripts to build cabinet geometry automatically.

## API

The library exposes the `AICabinets` module with helpers for creating cabinet geometry.

### `create_frameless_cabinet(config)`

`AICabinets.create_frameless_cabinet(config)` builds a row of frameless cabinets from a configuration hash. Global options such as `height`, `depth`, `panel_thickness`, `back_thickness`, and `shelf_count` establish defaults for all cabinets. Each entry in the `cabinets` array describes an individual cabinet and may override these defaults.

The configuration hash is defined below using [JSON Schema](https://json-schema.org/), enabling automated validation and generation of configuration data.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "height": { "type": "number" },
    "depth": { "type": "number" },
    "panel_thickness": { "type": "number" },
    "back_thickness": { "type": "number" },
    "shelf_count": { "type": "integer" },
    "cabinets": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "width": { "type": "number" },
          "shelf_count": { "type": "integer" },
          "hole_columns": { "type": "integer" },
          "door_type": { "enum": ["overlay", "inset"] },
          "door_style": { "enum": ["slab", "rail_and_stile"] },
          "door_reveal": { "type": "number" },
          "top_reveal": { "type": "number" },
          "bottom_reveal": { "type": "number" },
          "door_gap": { "type": "number" },
          "drawers": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "front_height": { "type": "number" },
                "box_thickness": { "type": "number" },
                "clearance": { "type": "number" },
                "joinery": { "enum": ["dovetail", "butt", "rabbet"] },
                "slide": { "enum": ["side", "undermount"] }
              },
              "required": ["front_height"]
            }
          },
          "partitions": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "offset": { "type": "number" }
              },
              "required": ["offset"]
            }
          },
          "top_type": { "enum": ["panel", "stringers"] },
          "top_stringer_width": { "type": "number" }
        },
        "required": ["width"]
      }
    }
  },
  "required": ["cabinets"]
}
```

Machine algorithms can generate a matching Ruby hash and invoke:

```ruby
AICabinets.create_frameless_cabinet(config)
```

Utility helpers like `select_slide_depth`, `align_to_hole_top`, and `drill_hole_columns` are also available for hardware layout and hole placement.

