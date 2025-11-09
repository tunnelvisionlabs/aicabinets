# Layout Preview Performance Harness

The layout preview renderer now ships with a standalone stress harness that exercises
rapid parameter edits, collects timing samples, and surfaces DOM/memory drift. Use it
to validate controller and renderer changes against the responsiveness targets from
Issue #203.

## Getting Started

1. Open `aicabinets/html/layout_preview/perf_harness.html` in a Chromium-based browser
   or load it through `UI::HtmlDialog` (the automated test `TC_LayoutPreviewPerf`
   does the latter).
2. Choose a fixture (`12-bay stress` or `20-bay stress`), adjust the iteration count
   if needed, and press **Start Stress**. The default run issues 300 `onParamsChanged`
   calls at ~16 ms intervals.
3. Watch the live metrics or inspect the console. The harness also exposes
   `window.__lp_metrics__` for programmatic assertions.

The harness uses the new `LayoutPreviewCtrl` to debounce parameter changes, memoize
layout models by param hash, and minimise DOM churn during re-rendering. Each update
emits:

- `update_ms`: time from params received → DOM applied (median ≤ 100 ms target).
- `render_frame_ms`: frame cost measured with `requestAnimationFrame`
  (median ≤ 16 ms target).
- `node_counts`/`node_drift`: guard against unbounded DOM growth when bay counts stay
  constant.
- `memory_drift_mb` (when CEF exposes `performance.memory`): the harness treats a
  positive slope as a leak indicator.

## Reading the Metrics

| Field | Description |
| --- | --- |
| Median / 95th update | Aggregated from `metrics.update_samples`. Stay ≤ 100 ms median; keep the 95th below ~2× the median. |
| Median / 95th frame | Aggregated from `metrics.frame_samples`. Aim for ≤ 16 ms median to hold 60 fps. |
| SVG nodes | Current total node count with a bay breakdown. A stable count confirms keyed updates rather than full rebuilds. |
| Node drift | Difference between first and latest samples. Non-zero drift on constant bay counts signals excess churn. |
| Heap drift | Delta (MB) across the run. Present only when `performance.memory` is available in the embedded CEF. |

The console logs a one-line summary after each run. Example:

```
[LayoutPreviewPerf] Completed 300 iterations (fixture: stress12) — median 78.4 ms (p95 109.7 ms); frame median 11.6 ms (p95 15.8 ms).
```

## Programmatic Access

`window.LayoutPreviewPerfHarness` exposes helpers used by the automated test:

- `startRun({ fixtureKey, iterations, intervalMs, seed })`
- `stop()` / `whenIdle()`
- `applyFixture(key)` / `resetMetrics()`
- `currentParamsHash()` and `getMetricsSnapshot()`

Live metrics reside on `window.__lp_metrics__` so CI can assert medians, 95ths, node
stability, and (when available) heap drift.

## Thresholds & Expectations

- **AC1**: 12‑bay stress, 300 iterations → median update ≤ 100 ms, 95th ≤ ~200 ms.
- **AC2**: `render_frame_ms` median ≤ 16 ms for the same run.
- **AC3**: The final DOM matches the last params hash (harness stores the hash in
  `__lp_metrics__.last_params_hash`).
- **AC4**: Node drift stays at zero and heap drift remains near 0 MB (allowing a small
  tolerance if the environment cannot expose heap stats).
- **AC5**: Constant bay counts keep the SVG node total stable.
- **AC6**: No `console.error`, unhandled rejection, or `window.onerror` entries — the
  harness follows the existing `DialogConsoleBridge` pattern so tests can drain the
  console.

## Known Limitations

- `performance.memory` is not exposed by SketchUp’s CEF on all platforms. When missing,
  `Heap drift` reads `n/a`; automated tests relax memory assertions accordingly.
- The harness runs on the main thread only. Option B from the issue (moving model
  generation to a worker) remains a follow-up.
