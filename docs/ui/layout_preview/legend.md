# Layout Preview Legend

The layout preview renders a schematic front elevation using the `LayoutModel` provided by the Ruby builder. Lines are drawn in millimeters with a top-left origin. This legend explains each overlay so reviewers can quickly confirm the preview matches the cabinet configuration.

## Partitions

- **Vertical partitions** appear in the `data-layer="partitions-v"` group as solid lines spanning the full cabinet height. Their `x` positions come directly from `partitions.positions_mm` (clamped to the outer width). If no explicit positions are provided, the preview falls back to evenly spaced divisions based on the partition count.
- **Horizontal partitions** appear in the `data-layer="partitions-h"` group as dashed lines spanning the full cabinet width. Positions are pulled from the same `positions_mm` array when the orientation is `horizontal`. When explicit values are absent the preview distributes the lines evenly across the cabinet height.

## Shelves

- Shelves render inside `data-layer="shelves"` as dashed lines inset from the bay edges. When explicit `y_mm` coordinates are provided they are honored; otherwise the preview computes schematic spacing using the bay height and shelf count. This fallback is documented as an approximation—the manufacturing data still determines exact shelf placement.

## Door Styles

Door overlays live in `data-layer="fronts"` with `data-front="door"`.

- `data-style="doors_left"` draws a short hinge tick on the **left** edge.
- `data-style="doors_right"` draws the hinge tick on the **right** edge.
- `data-style="doors_double"` draws a slim center gap line to indicate paired leaves.

Each overlay sits above the bay rectangle but has `pointer-events: none`, so bay selection and accessibility focus remain unchanged.
