# Layout Preview Tests

## Overview

The layout preview stack ships with a cross-language test suite that exercises the layout model math, SVG renderer structure, and SketchUp integration harness. This document summarizes the coverage and explains how to run the tests locally.

- **Ruby/TestUp** verifies `AICabinets::Layout::Model` emits consistent outer bounds, bay rectangles, and tolerances for even, mixed, degenerate, and single-bay scenarios.
- **Node/Jest (JSDOM)** renders canonical fixtures through the preview renderer, asserts the expected SVG scaffold, and maintains a sanitized snapshot for the three-bay layout.
- **HtmlDialog integration (TestUp)** loads a minimal harness that wires `requestSelectBay` and `setActiveBay` across the SketchUp bridge, ensuring round-trip selection sync without console or dialog errors.

## Ruby layout model tests

1. Launch **TestUp** and open the suite at `tests/AI Cabinets/`.
2. Run `TC_LayoutModel`. The suite covers:
   - Even partitions with equal bay widths.
   - Mixed-width partitions with explicit positions.
   - Degenerate inputs with zero bays.
   - A single-bay cabinet that mirrors the outer bounds.
3. Tolerances derive from `AICabinets::Layout::Model::EPS_MM`. Failures typically indicate regression in bay accumulation or tolerance handling.

## Node renderer tests

1. Install dependencies:

   ```sh
   npm ci
   ```

2. Run the renderer tests:

   ```sh
   npm test
   ```

   The command executes Jest (`tests/js/renderer.test.js`) in a JSDOM environment. Assertions confirm:
   - The root `<svg>` uses the expected `viewBox` and `preserveAspectRatio` attributes.
   - Canonical fixtures emit the correct layer groups and bay rectangles (0 / 254 / 508 mm offsets).
   - A sanitized snapshot captures the SVG structure without volatile attributes.
3. To update the inline snapshot after intentional changes:

   ```sh
   npm test -- -u
   ```

## HtmlDialog integration harness

1. Launch **TestUp** and run `TC_LayoutPreviewIntegration`.
2. The test opens `aicabinets/html/layout_preview/integration_harness.html`, renders a canned three-bay layout, and performs the following checks:
   - Clicking a bay dispatches `window.sketchup.requestSelectBay` and records the requested ID on the Ruby side.
   - Invoking `setActiveBay` from Ruby updates `.is-active`, `.is-deemphasized`, and `aria-selected` states.
   - The dialog emits no `console.error`, `window.onerror`, or unhandled promise rejection events.
3. The harness relies on the shared console bridge (`ui/dialogs/console_bridge.js`) to surface errors into the TestUp assertion stream.

## Troubleshooting

- Ensure SketchUp exposes `UI::HtmlDialog` when running HtmlDialog tests; the suite skips when unavailable.
- Run `bundle exec rubocop --parallel --display-cop-names` after editing Ruby files to keep style consistent.
- Markdown changes (including this document) should pass `npx --yes markdownlint-cli@0.41.0 "**/*.md" --config .markdownlint.jsonc --ignore node_modules --ignore dist`.
