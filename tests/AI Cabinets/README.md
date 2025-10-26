# AI Cabinets Test Suite

This folder contains the TestUp test suite for AI Cabinets. Add the folder to the
**Extensions → TestUp → Preferences → Test Suites** list inside SketchUp and the
suite will appear in the TestUp panel as **AI Cabinets**.

## Running
1. Install the AI Cabinets extension and the TestUp 2 extension in SketchUp.
2. In TestUp Preferences, add the absolute path to this folder.
3. Open the TestUp window and run the suite or the individual `TC_Smoke` test case.

The suite currently provides a smoke test that verifies the extension namespace,
ensures the active model can be reset to a blank state, and confirms the shared
helpers behave as expected.
