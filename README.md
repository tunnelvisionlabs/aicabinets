# AI Cabinets

This repository contains Ruby scripts for SketchUp that generate simple cabinetry models from code.

## Features

- [Rows](docs/rows.md) – Create and manage cabinet rows, reflow widths, and keep reveals uniform across fronts.

## Contents

- `lib/cabinet.rb` – library functions for creating cabinets. The generator builds a frameless carcass from two sides, a top (solid panel or pair of stringers), a bottom, and a back, and can optionally add shelves. Cabinets may also be partitioned with fixed panels so each section can have its own doors or drawers. Panels can be inset using `top_inset`, `bottom_inset`, and `back_inset` options. Use `top_type: :stringers` and `top_stringer_width` (default `100.mm`) to model stringers instead of a full top panel. Door overlays use `door_reveal` for the default gap to cabinet edges, `top_reveal` and `bottom_reveal` can override the edge clearances, and `door_gap` controls spacing between adjacent fronts.
- Panels are now created as SketchUp components rather than groups. A default `Birch Plywood` material is applied to cabinet parts, while doors default to `MDF`. Five-piece doors can specify separate materials for the frame (default `Maple`) and center panel, which defaults to the door material.
  When missing from the model, the generator defines `MDF` as a solid color (RGB 164,143,122), `Maple` as a solid color (RGB 224,200,160), and `Birch Plywood` as a solid color (RGB 222,206,170).
- `examples/frameless_two_shelf_cabinet.rb` – sample script that creates a frameless cabinet with two shelves.
- `examples/shaker_door_cabinet.rb` – demonstrates a rail-and-stile door with an 18° bevel.
- `examples/drawer_cabinet.rb` – shows how to add drawers to a cabinet, mix drawers with doors, and adjust drawer clearances.
- `examples/partitioned_cabinet.rb` – demonstrates dividing a cabinet interior with fixed partitions.
- `examples/slab_door_fronts.rb` – inserts three base cabinets showcasing the `:doors_left`, `:doors_right`, and `:doors_double` slab door modes.
- [Settings & Defaults (mm)](#settings--defaults-mm) – locate shipped defaults, user overrides, and reset steps.

Copy the library and sample code into SketchUp's Ruby console or load them as scripts to build cabinet geometry automatically.

## SketchUp Extension Packaging

Place `aicabinets.rb` and the `aicabinets/` folder inside SketchUp's `Plugins` directory to load AI Cabinets as an extension. The registrar exposes metadata so the Extension Manager lists "AI Cabinets" with version information from `aicabinets/version.rb`. The loader registers UI commands and toolbars without creating geometry at load time, keeping startup cost minimal while exposing extension entry points.

To verify Ruby syntax locally, run:

```sh
ruby -c aicabinets.rb && find aicabinets -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
```

## Linting

Install RuboCop and run the same command that CI executes:

```sh
gem install rubocop
rubocop --parallel --display-cop-names
```

The **Lint** GitHub Actions workflow provisions Ruby 3.2 with `ruby/setup-ruby@v1` and fails the build when RuboCop reports offenses.

## Running tests (TestUp)

TestUp is SketchUp's Minitest runner. To execute the AI Cabinets smoke tests:

1. Install the TestUp 2 extension alongside AI Cabinets.
2. In **Extensions → TestUp → Preferences → Test Suites**, add the absolute path to `tests/AI Cabinets/`.
3. Open the TestUp window and run the **AI Cabinets** suite or the `TC_Smoke` case.

The suite currently verifies the extension namespace loads, the helper utilities reset the active model cleanly, and shared tolerances work for geometry assertions.

UI dialog tests also stream DevTools console errors back to TestUp. The `TC_DialogConsoleErrors` case opens the Insert dialog, performs a basic interaction, and asserts that no `console.error`, `window.onerror`, or unhandled Promise rejection occurred; dedicated fixtures exercise failure scenarios. Warnings are recorded for review but do not fail the suite.

## Developer workflow – Deploy & TestUp (Windows)

Use the npm helpers to deploy the extension to SketchUp 2026 and run TestUp CI locally:

- Deploy the extension to the SketchUp 2026 Plugins folder:

  ```cmd
  npm run deploy:sketchup
  ```

- Run the full TestUp suite (auto-deploys first):

  ```cmd
  npm run testup:all
  ```

- Run a subset defined by a TestUp YAML config (auto-deploys first):

  ```cmd
  npm run testup:config -- --config "C:\\dev\\aicabinets\\tests\\class_only.yml"
  ```

  Or set `TESTUP_CONFIG` and omit the flag:

  ```cmd
  set TESTUP_CONFIG=C:\\dev\\aicabinets\\tests\\class_only.yml
  npm run testup:config
  ```

- Execute a custom Ruby script within SketchUp, close the active model without saving, and exit (auto-deploys first):

  ```cmd
  npm run sketchup:run -- --script "C:\\dev\\aicabinets\\script\\test_script.rb"
  ```

  Or set `STARTUP_RUBY` and omit the flag:

  ```cmd
  set STARTUP_RUBY=C:\\dev\\aicabinets\\script\\test_script.rb
  npm run sketchup:run
  ```

Defaults assume SketchUp 2026 on Windows with `SketchUp.exe` in `%ProgramFiles%\SketchUp\SketchUp 2026\SketchUp\SketchUp.exe` and Plugins at `%APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins`. Override paths with environment variables or per-command flags:

- `SKETCHUP_EXE` or `--exe <path>`
- `SKETCHUP_PLUGINS_DIR` or `--plugins <path>`
- `SKETCHUP_VERSION` to adjust the default SketchUp version used for the paths above (defaults to `2026`)
- `AI_CABINETS_TESTS` or `--tests <path>`
- `TESTUP_CONFIG` or `--config <path>` (for `testup:config`)
- `STARTUP_RUBY` or `--script <path>` (for `sketchup:run`)

Pass `--debug` after the command to echo resolved paths and the full SketchUp invocation.

To print the effective defaults (shipped JSON merged with user overrides), run:

```sh
ruby -I. script/print_effective_defaults.rb
```

Reset persisted overrides during manual testing with:

```sh
ruby -I. script/reset_overrides.rb
```

To package the extension for manual installation, run:

```sh
zip -r aicabinets-$(ruby -e "load 'aicabinets/version.rb'; puts AICabinets::VERSION").rbz aicabinets.rb aicabinets/
```

When a tag matching `v*` is pushed, the **Package RBZ** workflow zips `aicabinets.rb` and `aicabinets/` into `dist/aicabinets-<VERSION>.rbz`, uploads it as a workflow artifact, and can optionally publish the file on the tag’s GitHub Release.

## Settings & Defaults (mm)

AI Cabinets ships read-only defaults at `aicabinets/data/defaults.json` within the installed extension folder. The extension creates `aicabinets/user/overrides.json` after your first successful Insert or Edit action to persist user-chosen values. Both files live alongside `aicabinets.rb` in the extension’s support directory.

Effective settings are produced by merging the shipped defaults with the user overrides, applying override values last so they take precedence when keys overlap.

When defaults load, a sanitizer ensures every cabinet definition includes a `partitions` container with a resolved `orientation`, a `bays` array sized to `count + 1`, and per-bay defaults (for example, `shelf_count` and `door_mode`). Nested `subpartitions` inherit the perpendicular orientation, clone sane defaults when missing, and keep unknown keys intact so legacy models migrate deterministically.

All serialized length values are stored in millimeters and use the `_mm` suffix in JSON. No other unit system is written to disk.

To reset the extension to the shipped defaults, delete `aicabinets/user/overrides.json`. The extension recreates the overrides file the next time it needs to save user changes.

## Install (SketchUp 2026, unsigned RBZ)

1. Open **Extension Manager** from the **Extensions** menu or its toolbar icon.
2. Click **Install Extension…**, choose the downloaded `aicabinets-<VERSION>.rbz`, and confirm SketchUp’s warning for third-party packages. [SketchUp Help: Manually Installing Extensions](https://help.sketchup.com/en/sketchup/installing-extensions)
3. If SketchUp 2026 blocks the load because the extension is **Unsigned**, open **Extension Manager → Settings (gear)** and review the **Loading Policy**, selecting the mode that matches your security posture. SketchUp documents the three modes—**Identified Extensions Only**, **Approve Unidentified Extensions**, and **Unrestricted**—in its [Loading Policy Preferences](https://help.sketchup.com/en/sketchup/loading-policy-preferences) guide. Changes may require restarting SketchUp before the unsigned extension loads.
4. Only install RBZ files from sources you trust. **Unrestricted** allows all extensions and is the least secure option.
5. Enable the extension in Extension Manager if it did not auto-activate after installation.

## Extension UI

After installing the extension, launch its placeholder action from **Extensions → AI Cabinets → Insert Base Cabinet…** or by showing the **AI Cabinets** toolbar. Both entry points share the same command, which currently opens a simple placeholder message while the full cabinet insertion dialog is under development.

## Partition Options

See [Per-bay shelves & doors](docs/user-guide.md#per-bay-shelves--doors) for a task-focused walk-through of the bay chips, Fronts & Shelves editor, Sub-partitions, Insert/Edit scope, and the double-door guardrail.

Generated base cabinets accept a `partitions` payload to divide the interior into bays.

- `partition_mode` drives the top-level orientation (`vertical` or `horizontal`). When `partition_mode` is `none`, the sanitizer forces `partitions.count` to `0` and `bays` to a single entry.
- `mode` determines how partitions are created:
  - `none` omits partitions.
  - `even` spaces `count` partitions so the resulting `count + 1` bays have nearly equal clear widths.
- `positions` places partitions at explicit offsets measured in millimeters from the cabinet’s left outside face to each partition’s left face.
- `bays` stores per-bay settings such as `shelf_count` and `door_mode`. Its length always matches `count + 1`, and missing or partial entries are filled from the active defaults.
- Shelves and door fronts are generated per leaf bay. Parent bays that declare `subpartitions` skip shelf/front geometry so nested bays can provide their own counts and door modes. Each door leaf uses the bay’s clear width, subtracts edge/top/bottom reveals, and for doubles splits the remaining width around the configured center gap.
- Each bay may define a `subpartitions` container with its own `count`, `orientation`, and nested `bays`. The sanitizer forces nested orientations to stay perpendicular to the parent partitions and fills missing bays to `count + 1`.
- Partitions use the carcass panel thickness (or an explicit `panel_thickness_mm` value when provided) and span the interior height (top of the bottom panel to the underside of the top or stringers) and depth (front face to the back panel).
- Invalid or overlapping requests are ignored, and the generator logs warnings when positions are clamped to the cabinet interior or discarded because they violate minimum bay widths.

## Per-bay Controls

The Insert/Edit HtmlDialog surfaces a bay selector (chips), shelf stepper, and door mode segmented control for each bay. Selecting **None** persists `door_mode: null`, while the Ruby helper blocks “Double” whenever the bay’s clear width cannot accommodate two leaves. Quality-of-life actions apply settings to every bay or mirror the left half to the right, skipping destinations that would violate the double-door constraints.

## HtmlDialog Accessibility

The Insert/Edit dialog ships with a predictable focus order and polite announcements so keyboard and assistive technology users receive the same feedback as mouse users.

- Native radios live inside `<fieldset>/<legend>` groups for the partition mode selector, scope toggle, and bay editor switcher. Each option uses an explicit `<label for="…">` pairing so screen readers expose the full option text.
- Segmented controls (bay chips, bay editor switcher, and door mode) expose a single tab stop per group. Arrow keys (and Home/End) wrap across options, immediately commit the new selection, and leave focus on the active segment so Tab/Shift+Tab can continue the dialog order. Disabled choices are skipped automatically, and `aria-selected`/native `aria-checked` states stay in sync with the visual highlight.
- A single visually hidden live region (`#sr-updates`) relays status changes. The JavaScript `LiveAnnouncer` helper coalesces messages (200 ms debounce) and sanitizes text before setting `textContent` to avoid spamming assistive tech.
- Inactive controls are removed from the tab order with `HTMLElement.inert` when Chromium supports it, or a fallback that toggles `aria-hidden` and saves/restores prior tabindex values.
- Validation errors reuse the same live region: `FormController#setFieldError` sets `aria-invalid`, updates the field’s inline message, and announces `{Label}: {Error}` when the text changes.
