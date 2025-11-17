# Agents Guide

## Purpose & Audience

This document standardizes how humans and coding agents contribute to **AI Cabinets**.
It defines **issue structures**, **project conventions**, **best‑practice references**, and **writing guidelines** so contributions are consistent, easy to review, and safe to merge.

## Project Conventions (Invariants)

These rules apply across the codebase and issues.

### Units & Measurement

* **Defaults and serialized parameters are in millimeters (mm).**
* JSON fields representing lengths are suffixed `_mm`.
* Convert to SketchUp `Length` only at modeling time (e.g., `mm_val.to_f.mm`).
* UI input may accept raw numbers or explicit unit suffixes.

### Placement Anchor

* The **insert origin is the front‑left‑bottom (FLB) corner of the *carcass***.
* Do **not** shift the origin for doors/drawers; front geometry may extend toward −Y without affecting the origin.

### Edit Scope & Parameter Storage

* Editing a placed cabinet supports **This instance only** (default) **or** **All instances (shared definition)**.
* **Canonical parameters live on the `ComponentDefinition`** (attribute dictionary `AICabinets`, e.g., `params_json_mm`, `schema_version`).
* For “This instance only” edits on a shared definition, call `make_unique` before regeneration.

### UI Technology & Commands

* Use **`UI::HtmlDialog`** for all new UI.
* Expose actions via **`UI::Command`** (menu + toolbar); keep icons and tooltips consistent.

### Tagging & Naming

* Tag by category (e.g., `AICabinets/Cabinet`, `AICabinets/Sides`, `AICabinets/Shelves`, `AICabinets/Back`, `AICabinets/Fronts`, `AICabinets/Partitions`).
* Create tags if missing via the Tags/Layers API.
* **Do not embed dimensions in component names.** Prefer stable, descriptive names.

### Undo & Operations

* Wrap modeling mutations in a **single undoable operation** (`start_operation`/`commit_operation`).
* Keep operations small and deterministic.

### File Layout & Loading

* Namespace all code under `AICabinets`.
* Use a registrar (`aicabinets.rb`) and a support folder (`aicabinets/`).
* Prefer `Sketchup.require` for load paths to remain compatible with packaged/signed extensions.
* `lib/*` contains prototype/POC reference code kept for historical context. It is read-only for agents and will be removed once the extension reaches a superset of feature parity.

## Best‑Practice References (IDs you can cite in issues)

Use these short IDs in **Implementation Notes (Constraints & Practices)** to justify constraints without over‑specifying the solution.

* **BP‑1:** Use `UI::HtmlDialog` for UI; avoid legacy dialogs.
* **BP‑2:** Expose features via `UI::Command` (menu + toolbar); include tooltips and proper icon sizes.
* **BP‑3:** Keep the **FLB *carcass* anchor** invariant; front geometry must not move the origin.
* **BP‑4:** JSON defaults and serialized parameters are **mm**; suffix `_mm`; convert to `Length` at modeling time.
* **BP‑5:** Store canonical parameters on **`ComponentDefinition`**; for instance‑only edits on shared definitions, call **`make_unique`** then regenerate.
* **BP‑6:** Wrap modeling actions in **one undoable operation**.
* **BP‑7:** Tag **by category**; create tags if missing; avoid dimension‑encoded names.
* **BP‑8:** Use `Sketchup.require`, not `require_relative`, for extension‑friendly loading.
* **BP‑9:** Accept and display lengths using model units; parse with `String#to_l`/`.mm` and format with `Sketchup.format_length`.
* **BP‑10:** `lib/*` is a read-only prototype. Do not modify.

## Issue Types

* **Story** – a user‑visible capability that may span multiple tasks (UI + geometry + tests + docs).
* **Task** – a single work item (feature, enhancement, bug, or chore).
  * **Bug** - a task representing current behavior which deviates from the expected behavior
  * **Feature** - a task representing new behavior that has not been implemented

Start new issues with the structured GitHub forms so titles, labels, and required details stay consistent:

* [Story issue form](https://github.com/tunnelvisionlabs/aicabinets/issues/new?template=story.yml)
* [Task issue form](https://github.com/tunnelvisionlabs/aicabinets/issues/new?template=task.yml)
* [Bug report form](https://github.com/tunnelvisionlabs/aicabinets/issues/new?template=bug_report.yml)
* [Enhancement issue form](https://github.com/tunnelvisionlabs/aicabinets/issues/new?template=enhancement.yml)
* [Feature request form](https://github.com/tunnelvisionlabs/aicabinets/issues/new?template=feature_request.yml)

> **Formatting rule:** Prefer **markdown headings** for section titles (no bold section headers), and follow each heading with a blank line before the next content.

Use the sections provided by each form; include optional sections when the details are specific, accurate, and materially help contributors complete the work.

## Labels

Recommended label taxonomy:

* **Type:** `Story`, `Task`, `Bug`, `Feature`
* **Area:** `area:ui`, `area:geometry`, `area:persistence`, `area:packaging`, `area:testing`, `area:build`
* **Component:** `component:dialog`, `component:generator`, `component:ops`, `component:registrar`, `component:tags`
* **Priority:** `priority:P0`, `priority:P1`, `priority:P2`, `priority:P3`

## Pull Request Checklist

* [ ] Acceptance criteria in the linked issue are met.
* [ ] Changes respect **project invariants** (FLB *carcass* anchor, JSON in mm, definition‑level params).
* [ ] Modeling changes are wrapped in one undoable operation.
* [ ] UI changes use `UI::HtmlDialog`; commands use `UI::Command`.
* [ ] New/changed parameters use `_mm` suffix in JSON and are converted to `Length` during modeling.
* [ ] Tags/names follow category tagging and avoid dimension‑encoded names.
* [ ] Tests updated or added where behavior changed.
* [ ] README or user docs updated if behavior is user‑visible.

## Branch & Commit Conventions

* Branch names: `type/short-summary` (e.g., `task/edit-scope-ui`, `bug/fix-shelf-spacing`).
* Commits: imperative mood, scoped (`generator: ensure shelves clear toe-kick`).
* Reference issues in commits/PRs (`Fixes #123`, `Refs #456`).

## General Writing Guidelines

Use this section to standardize tone and content quality across issues, PRs, docs, and comments.

### Style & Structure

* Conciseness vs. Usefulness: Write in a clear, concise manner, but include enough detail to be useful. Avoid overly verbose descriptions that don’t add value, but also avoid being so brief that important usage information is missing. Every sentence should help a developer understand the what, why, or how of the situation or API. If a comment doesn’t provide new information (e.g., just rephrases an API member name), remove or refine it.
* Use **markdown headings** for structure; avoid bold for section titles.
* Front‑load context; keep rationale close to decisions.
* Audience-Appropriate Depth: Tailor the documentation detail to the intended audience of the content or API:
  * For user features and experiences, use straightforward language and maybe a bit more explanation or context, assuming the user might not be a developer and/or might be less experienced. Define any domain-specific terms that a general user might not know.
  * For common or beginner-friendly APIs, use straightforward language and maybe a bit more explanation or context, assuming the developer might be less experienced. Define any domain-specific terms that a developer might not know.
  * For advanced or specialized internal behaviors or APIs, it’s okay to assume more expertise. Focus on the specifics that an expert user needs, and use domain-specific terminology if the target audience will understand it. (Still, avoid unnecessary jargon and explain complexities clearly.)
* Show data/observations when making assertions (commit SHAs, measurements, screenshots).
* Avoid speculative language in shipped docs; keep “future ideas” in issue comments or separate RFCs.
* Use third-person descriptive voice. The tone should be professional and informative. Use the present tense for descriptions.
* Trim Unnecessary Details: If the documentation becomes too lengthy or includes information that’s not crucial for understanding a feature or API’s usage, trim it down. Developers typically read docs to decide how to use an API; focus on information that influences that decision or helps in using the API correctly. For example:
  * Omit internal algorithm details unless knowing them helps the user (e.g., mentioning that a method uses caching might explain why calling it repeatedly is cheap).
  * Avoid repeating information that can be inferred. (If a parameter name is count and the parameter description just says “The count.”, that’s not helpful. Either expand on what “count” means in context or omit such a redundant comment.)
  * Ensure the length is appropriate: shorter for simple members, longer (but still focused) for complex ones. It’s better to be slightly succinct than to overwhelm with extraneous info.

### Terminology

* Use consistent terms: **carcass**, **fronts** (doors/drawers), **FLB anchor**, **definition** vs **instance**, **tag** (aka “layer” in API).
* Units: say **mm** explicitly in prose when ambiguity is possible.

### Audience Awareness

* For issues: write **Summary** for general readers; put implementation detail under **Technical Description**.
* For PRs: state what changed and why first; then how.

## General Writing Guidelines — Code Comments

* Focus on Exposed Behavior (Not Implementation)
  * Describe what the member does and how to use it, rather than how it’s implemented internally.
  * Only include implementation details if they affect inputs or outputs in a way the caller needs to understand (e.g. performance implications, special conditions, side effects).
  * Preconditions and postconditions are important: document any requirements (e.g. “parameter X cannot be null” or range limits) and effects (e.g. changes in state or global effects) that a caller should know.
  * Avoid simply restating the member name or signature. Provide information that adds value for someone deciding whether to use this member.
* Comment **why**, not *what the code obviously does*.
* Document **public APIs** and entry points (methods invoked by UI/Commands).
* Specify **units** for any numeric parameter or return value (`_mm` if serialized; `Length` if in model space).
* Keep comments adjacent to the code they explain; avoid stale headers.
* Use consistent Ruby doc style (e.g., YARD tags where helpful: `@param`, `@return`).
* Avoid apologetic or speculative comments. If behavior is uncertain, open a task issue instead.

## General Writing Guidelines — Project Documentation

* Keep docs **task‑oriented** (how to install, insert, edit).
* Always note **SketchUp version compatibility**.
* Call out **project invariants** (FLB *carcass* anchor, mm defaults, edit scope).
* Provide **copy‑paste snippets** and **expected results**.
* For behavior changes, include **Before/After** notes and link to the driving issue.
* Keep screenshots minimal and current; annotate only where it clarifies behavior.
* When describing measurements, state **units explicitly** and avoid mixing unit systems in a single example.

## Windows Deploy & TestUp Documentation

Document the Windows Deploy and TestUp workflows in `README.md` so contributors can find the npm commands and environment overrides.

Deploy/TestUp commands are available only during local agent execution; assume they cannot run in cloud execution environments.

## Local validation (docs & Ruby)

Run these commands before sending a PR when you touch Markdown or Ruby files so CI matches local results:

### Markdown changes

* `npx --yes markdownlint-cli@0.41.0 "**/*.md" --config .markdownlint.jsonc --ignore node_modules --ignore dist`
* `npx --yes cspell@8.14.2 "**/*.md" --config .cspell.json --no-progress --no-summary`
* `npx --yes linkinator@6.0.0 "**/*.md" --config ./.linkinator.config.json --skip "https://help\\.sketchup\\.com/.*" --skip "https://www\\.githubstatus\\.com/.*"`

### Ruby changes

* `bundle exec rubocop --parallel --display-cop-names`
  * If RuboCop is not yet installed locally, run `bundle install` first, or fallback to `gem install rubocop && rubocop --parallel --display-cop-names`.
