# AI Cabinets Test Suite

This folder contains the TestUp test suite for AI Cabinets. Add the folder to the
**Extensions → TestUp → Preferences → Test Suites** list inside SketchUp and the
suite will appear in the TestUp panel as **AI Cabinets**.

## Running

1. Install the AI Cabinets extension and the TestUp 2 extension in SketchUp.
2. In TestUp Preferences, add the absolute path to this folder.
3. Open the TestUp window and run the suite or the individual test cases such as
   `TC_Smoke` or `TC_CarcassContract`.

## Test Cases

* `TC_Smoke` exercises the extension namespace, confirms the helper utilities, and
  verifies the test harness can reset the active model.
* `TC_CarcassContract` builds a base carcass with canonical millimeter parameters
  and enforces the geometry contract (local bounding box dimensions, FLB anchor,
  part containers, tagging hygiene, and toe-kick origin invariance).
* `TC_EditScope` creates two cabinet instances that share a definition, exercises
  the edit workflow for **Only this instance** and **All instances**, and verifies
  definition keys, stored parameters, transforms, FLB origin invariance, and
  single-step undo behavior.
