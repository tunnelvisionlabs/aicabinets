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

## Issue Types

* **Story** – a user‑visible capability that may span multiple tasks (UI + geometry + tests + docs).
* **Task** – a single work item (feature, enhancement, bug, or chore).
  * **Bug** - a task representing current behavior which deviates from the expected behavior
  * **Feature** - a task representing new behavior that has not been implemented

> **Formatting rule:** Prefer **markdown headings** for section titles (no bold section headers).

## Story Issue Template

```markdown
# [Story] <Concise outcome, e.g., "Edit Selected Cabinet with Scope">

## Goal
One or two sentences describing the user-visible outcome.

## User Story
As a <role>, I want <capability> so that <benefit>.

## Acceptance Criteria
- Given <precondition>, when <action>, then <observable result>.
- Given …, when …, then …
- Include edge cases and validation rules needed to ship.

## Scope
### In
- Bullet list of what is definitely included.

### Out
- Bullet list of what is explicitly excluded.

## UX Notes / Mockups
- Link sketches or describe expected UI states and defaults.

## Data & Persistence
- Data written/read (e.g., JSON defaults in **mm**, component definition/instance attributes).
- Any schema or versioning notes.

## Technical Notes
- High-level approach and key constraints (e.g., FLB *carcass* anchor; undoable operations; HtmlDialog).
- Cross-reference best-practice IDs (e.g., BP‑1, BP‑3, BP‑4, BP‑5).

## Sub-Issues
- [ ] <Task 1>
- [ ] <Task 2>
- [ ] <Task 3>

## Risks
- Foreseeable pitfalls or UX surprises and how we’ll mitigate them.

## Definition of Done
- All acceptance criteria pass.
- Tests for critical logic are added and green.
- Docs updated where relevant.

## Labels
type:story, area:<ui|geometry|…>, component:<dialog|generator|…>, priority:P?
```

## Task Issue Template

```markdown
# [Task|Bug|Feature|Chore] <Crisp action, e.g., "Add edit-scope option to dialog">

## Context
### Summary (general audience)
A one-paragraph overview of what changes and why it matters.

### Technical Description (optional; include only if it adds material detail)
Details for contributors (APIs touched, modules, data shape).

### Actual vs Expected Behavior (only for bugs or behavior changes)
- **Actual:** What happens today. If derived from code analysis, cite the commit SHA.
- **Expected:** What should happen, described concretely.
- **If tested in app:** include SketchUp version, app code version/tag or commit SHA, and operating system.

### Best Practice Reference (optional)
If available and unambiguous, cross-reference a guideline so the expected behavior isn’t just preference (e.g., BP‑1 HtmlDialog, BP‑3 FLB anchor, BP‑4 mm defaults).

## Acceptance Criteria
- [ ] Checklist items that must be true for this task to be complete.
- [ ] Keep them observable and testable from a user or API perspective.

## Implementation Notes (Constraints & Practices)
- List **constraints** required to maintain best practices (e.g., BP‑1, BP‑3, BP‑4, BP‑5, BP‑6).
- Do **not** prescribe specific classes/methods if not necessary to meet the acceptance criteria.
- Aim for a single undoable operation; keep the FLB *carcass* anchor invariant; keep JSON fields in **mm**.

## Labels
type:<task|bug|enhancement|chore>, area:<ui|geometry|…>, component:<dialog|generator|…>, priority:P?
```

> **Omit by default for tasks:** Test Plan, Docs, and Dependencies. Include them **only** when they were explicitly requested for that issue.

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
  * Avoid repeating information that can be inferred. (If a parameter name is count and the <param> description just says “The count.”, that’s not helpful. Either expand on what “count” means in context or omit such a redundant comment.)
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
