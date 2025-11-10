# Layout Preview Fit & Scale Policy

## Goals

- Preserve the millimeter dimensions defined in the `LayoutModel` while presenting the layout inside an HtmlDialog pane that can resize arbitrarily.
- Provide predictable padding that prevents bays from touching the dialog chrome on extreme aspect ratios.
- Keep strokes legible regardless of scale so bays remain distinguishable in both small and large dialogs.

## Coordinate System & ViewBox

- The renderer treats **one SVG user unit as one millimeter**. The root `<svg>` sets `viewBox="0 0 outer.w_mm outer.h_mm"` so values from the model map directly to SVG coordinates.
- `preserveAspectRatio="xMidYMid meet"` ensures the SVG letterboxes inside the host when the dialog aspect ratio differs from the cabinet aspect ratio.
- Because the viewBox matches the physical dimensions, exported values remain in millimeters and can be compared back to `LayoutModel` values without conversion.

```text
 viewBox width  = layout.outer.w_mm
 viewBox height = layout.outer.h_mm
 panes that are wider/taller than the layout receive letterboxing from SVG
```

## Inner Padding Transform

- The layout reserves a configurable padding fraction (`padding_frac`, default `0.05`) so bays do not abut the SVG edges.
- Padding is implemented with a matrix transform on a wrapper `<g>` element. The transform keeps the raw `rect` attributes in millimeters while shifting the rendered positions inward.
- Matrix form:
  - `scale = max(0.01, 1 - padding_frac * 2)`
  - `translateX = outer.w_mm * padding_frac`
  - `translateY = outer.h_mm * padding_frac`
  - Applied as `matrix(scale 0 0 scale translateX translateY)`
- Padding is clamped to 0.48 to avoid negative scales when callers provide extreme fractions.

```text
Raw model values (mm) ─┐
                       │ matrix(scale, translate)
Rendered positions ────┘       → consistent mm values on the DOM
```

## Stable Stroke Strategy

- Every `rect` sets `vector-effect: non-scaling-stroke`, preventing stroke widths from shrinking or bloating as the SVG scales to fit the container.
- Stroke widths are expressed with CSS custom properties so dialogs can theme them without altering JavaScript.
- The renderer assigns defaults, but HtmlDialog hosts may override the variables.

| CSS Variable | Purpose | Default |
| --- | --- | --- |
| `--lp-stroke-px` | Base outline width for outer shell and bays. | `1.5px` |
| `--lp-hover-stroke-px` | Hover width for bays. | `calc(var(--lp-stroke-px) * 1.5)` |
| `--lp-active-color` | Hover/active tint for bays. | `#1f7aec` |
| `--lp-bay-fill` | Fill color for bays. | `rgba(255, 255, 255, 0.78)` |
| `--lp-bay-hover-fill` | Hover fill for bays. | `rgba(31, 122, 236, 0.15)` |

## Hover Styling

- CSS targets `[data-role="bay"]:hover > rect` to adjust stroke width and tint without JavaScript.
- Because the root container uses `role="img"` and each bay exposes `aria-label="Bay N"`, accessibility hints remain available even if hover is not possible (e.g., keyboard navigation).
- Hover is supplemented by an opacity change so the interactive affordance is visible to low-vision users.

## Integration Notes

- Include `renderer.css`, `renderer.js`, and a container element sized via CSS (`width: 100%; height: 100%`).
- Call `LayoutPreview.render(container, layoutModel, { padding_frac, stroke_px, active_tint })` to inject the SVG. The return value exposes `update(model)` and `destroy()` for dynamic content.
- When testing inside SketchUp, load `console_bridge.js` so dialog console errors stream through the TestUp harness.
