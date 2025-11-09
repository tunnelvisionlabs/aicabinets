(function () {
  'use strict';

  var DEFAULT_ITERATIONS = 300;
  var DEFAULT_INTERVAL_MS = 16;
  var MIN_BAY_WIDTH_MM = 120;
  var MAX_BAY_WIDTH_MM = 660;

  var fixtures = buildInlineFixtures();

  var dom = {
    host: null,
    fixtureSelect: null,
    iterationInput: null,
    intervalInput: null,
    startButton: null,
    stopButton: null,
    resetButton: null,
    statusText: null,
    updateMedian: null,
    updateP95: null,
    updateSamples: null,
    frameMedian: null,
    frameP95: null,
    frameSamples: null,
    nodeCount: null,
    nodeDrift: null,
    memoryDrift: null
  };

  var state = {
    controller: null,
    fixtureKey: 'stress12',
    currentParams: null,
    currentParamsHash: null,
    running: false,
    rng: null,
    runTimer: null,
    runPromise: null,
    resolveRun: null
  };

  var metrics = {
    status: 'idle',
    update_samples: [],
    frame_samples: [],
    render_samples: [],
    node_samples: [],
    memory_samples: [],
    medians: { update_ms: null, frame_ms: null },
    p95: { update_ms: null, frame_ms: null },
    iteration_target: DEFAULT_ITERATIONS,
    iteration_count: 0,
    last_params_hash: null,
    last_fixture: null,
    node_counts: null,
    node_drift: null,
    memory_drift_mb: null,
    started_at: null,
    completed_at: null,
    seed: null
  };

  window.__lp_metrics__ = metrics;

  document.addEventListener('DOMContentLoaded', initialize);

  function initialize() {
    dom.host = document.querySelector('[data-role="layout-preview-host"]');
    dom.fixtureSelect = document.querySelector('[data-role="fixture-select"]');
    dom.iterationInput = document.querySelector('[data-role="iteration-count"]');
    dom.intervalInput = document.querySelector('[data-role="interval-ms"]');
    dom.startButton = document.querySelector('[data-role="start-run"]');
    dom.stopButton = document.querySelector('[data-role="stop-run"]');
    dom.resetButton = document.querySelector('[data-role="reset-metrics"]');
    dom.statusText = document.querySelector('[data-role="status-text"]');
    dom.updateMedian = document.querySelector('[data-role="metric-update-median"]');
    dom.updateP95 = document.querySelector('[data-role="metric-update-p95"]');
    dom.updateSamples = document.querySelector('[data-role="metric-update-samples"]');
    dom.frameMedian = document.querySelector('[data-role="metric-frame-median"]');
    dom.frameP95 = document.querySelector('[data-role="metric-frame-p95"]');
    dom.frameSamples = document.querySelector('[data-role="metric-frame-samples"]');
    dom.nodeCount = document.querySelector('[data-role="metric-node-count"]');
    dom.nodeDrift = document.querySelector('[data-role="metric-node-drift"]');
    dom.memoryDrift = document.querySelector('[data-role="metric-memory-drift"]');

    registerUiHandlers();
    initializeController();
    resetMetrics();
    applyFixture(state.fixtureKey);
    updateMetricsDisplay();
    notifyReady();
  }

  function registerUiHandlers() {
    if (dom.fixtureSelect) {
      dom.fixtureSelect.addEventListener('change', function onFixtureChange(event) {
        var key = event.target && event.target.value ? String(event.target.value) : state.fixtureKey;
        applyFixture(key);
      });
    }

    if (dom.startButton) {
      dom.startButton.addEventListener('click', function onStartClick() {
        startRun({});
      });
    }

    if (dom.stopButton) {
      dom.stopButton.addEventListener('click', function onStopClick() {
        stopRun();
      });
    }

    if (dom.resetButton) {
      dom.resetButton.addEventListener('click', function onResetClick() {
        resetMetrics();
        updateMetricsDisplay();
      });
    }
  }

  function initializeController() {
    if (!dom.host || !window.LayoutPreview || typeof window.LayoutPreview.render !== 'function') {
      logWarn('Renderer is unavailable; harness cannot start.');
      return;
    }

    if (!window.LayoutPreviewCtrl || typeof window.LayoutPreviewCtrl.init !== 'function') {
      try {
        state.controller = window.LayoutPreview.render(dom.host, fixtures[state.fixtureKey], { padding_frac: 0.05 });
      } catch (error) {
        logWarn('Failed to initialize fallback renderer: ' + formatError(error));
      }
      return;
    }

    try {
      state.controller = window.LayoutPreviewCtrl.init(dom.host, window.LayoutPreview, {
        renderOptions: { padding_frac: 0.05 },
        modelBuilder: buildLayoutModel,
        onMetrics: handleMetrics,
        debounceMs: window.LayoutPreviewCtrl.DEFAULT_DEBOUNCE_MS
      });
    } catch (error) {
      logWarn('Failed to initialize LayoutPreviewCtrl: ' + formatError(error));
    }
  }

  function applyFixture(key) {
    if (!fixtures[key]) {
      return false;
    }

    state.fixtureKey = key;
    metrics.last_fixture = key;
    var params = createParamsFromFixture(fixtures[key], key);
    state.currentParams = params;
    state.currentParamsHash = computeHash(params);
    metrics.last_params_hash = state.currentParamsHash;

    if (state.controller && typeof state.controller.setLayoutModel === 'function') {
      state.controller.setLayoutModel(fixtures[key], params);
    } else if (state.controller && typeof state.controller.update === 'function') {
      state.controller.update(fixtures[key]);
    }

    if (dom.fixtureSelect) {
      dom.fixtureSelect.value = key;
    }

    updateNodeMetrics(sampleDom());
    updateMetricsDisplay();
    return true;
  }

  function startRun(config) {
    if (!state.controller || typeof state.controller.onParamsChanged !== 'function') {
      logWarn('LayoutPreviewCtrl is not active; cannot start stress run.');
      return false;
    }

    if (state.running) {
      stopRun();
    }

    var iterations = parseNumber((config && config.iterations) || (dom.iterationInput && dom.iterationInput.value), DEFAULT_ITERATIONS);
    var intervalMs = parseNumber((config && config.intervalMs) || (dom.intervalInput && dom.intervalInput.value), DEFAULT_INTERVAL_MS);
    var fixtureKey = (config && config.fixtureKey) || state.fixtureKey;
    var seed = typeof (config && config.seed) === 'number' ? config.seed : Date.now();

    applyFixture(fixtureKey);
    resetMetrics();
    metrics.iteration_target = clamp(iterations, 30, 600);
    metrics.iteration_count = 0;
    metrics.seed = seed >>> 0;
    metrics.started_at = now();
    metrics.completed_at = null;
    metrics.status = 'running';
    updateStatusText();
    updateMetricsDisplay();

    state.rng = createRng(metrics.seed);
    state.running = true;
    toggleButtons(true);

    state.runPromise = new Promise(function (resolve) {
      state.resolveRun = resolve;
    });

    pumpIteration(intervalMs);
    return true;
  }

  function pumpIteration(intervalMs) {
    if (!state.running) {
      return;
    }

    if (metrics.iteration_count >= metrics.iteration_target) {
      finalizeRun();
      return;
    }

    metrics.iteration_count += 1;
    updateStatusText();

    var nextParams = mutateParams(state.currentParams, state.rng);
    state.currentParams = nextParams;
    state.currentParamsHash = computeHash(nextParams);

    state.controller.onParamsChanged(nextParams);

    state.runTimer = window.setTimeout(function scheduleNext() {
      pumpIteration(intervalMs);
    }, Math.max(0, intervalMs));
  }

  function stopRun() {
    if (!state.running) {
      return false;
    }

    state.running = false;
    if (state.runTimer) {
      window.clearTimeout(state.runTimer);
      state.runTimer = null;
    }
    metrics.status = 'stopped';
    updateStatusText();
    toggleButtons(false);
    resolveRunPromise(buildRunSummary(true));
    return true;
  }

  function finalizeRun() {
    if (state.runTimer) {
      window.clearTimeout(state.runTimer);
      state.runTimer = null;
    }
    state.running = false;
    metrics.status = 'idle';
    metrics.completed_at = now();
    updateTimingStats();
    updateNodeMetrics(sampleDom());
    updateMemoryMetrics();
    updateStatusText();
    updateMetricsDisplay();
    toggleButtons(false);
    logSummary();
    resolveRunPromise(buildRunSummary(false));
  }

  function resolveRunPromise(summary) {
    if (state.resolveRun) {
      var resolver = state.resolveRun;
      state.resolveRun = null;
      resolver(summary);
    }
    state.runPromise = null;
  }

  function whenIdle() {
    if (!state.running && !state.runPromise) {
      return Promise.resolve(buildRunSummary(false));
    }
    return state.runPromise || Promise.resolve(buildRunSummary(false));
  }

  function resetMetrics() {
    metrics.update_samples = [];
    metrics.frame_samples = [];
    metrics.render_samples = [];
    metrics.node_samples = [];
    metrics.memory_samples = [];
    metrics.medians.update_ms = null;
    metrics.medians.frame_ms = null;
    metrics.p95.update_ms = null;
    metrics.p95.frame_ms = null;
    metrics.iteration_count = 0;
    metrics.node_counts = null;
    metrics.node_drift = null;
    metrics.memory_drift_mb = null;
    metrics.started_at = null;
    metrics.completed_at = null;
    metrics.status = state.running ? 'running' : 'idle';
    updateStatusText();
  }

  function mutateParams(params, rng) {
    var next = cloneParams(params);
    if (!next || !next.bay_widths_mm || !next.bay_widths_mm.length) {
      return params;
    }
    var index = Math.floor((rng || Math.random)() * next.bay_widths_mm.length);
    if (index < 0 || index >= next.bay_widths_mm.length) {
      index = 0;
    }
    var delta = ((rng || Math.random)() - 0.5) * 80;
    var candidate = clamp(next.bay_widths_mm[index] + delta, MIN_BAY_WIDTH_MM, MAX_BAY_WIDTH_MM);
    next.bay_widths_mm[index] = candidate;
    next.outer.w_mm = Math.max(candidate, 1);
    var total = 0;
    for (var i = 0; i < next.bay_widths_mm.length; i += 1) {
      total += next.bay_widths_mm[i];
    }
    next.outer.w_mm = Math.max(total, 1);
    next.sequence = (next.sequence || 0) + 1;
    return next;
  }

  function buildLayoutModel(params) {
    var safeParams = params || {};
    var widths = Array.isArray(safeParams.bay_widths_mm) ? safeParams.bay_widths_mm.slice() : [];
    var height = toPositiveNumber(safeParams.outer && safeParams.outer.h_mm, 762);
    var totalWidth = 0;
    var bays = [];
    var fronts = [];
    var x = 0;

    for (var index = 0; index < widths.length; index += 1) {
      var width = toPositiveNumber(widths[index], MIN_BAY_WIDTH_MM);
      totalWidth += width;
      bays.push({
        id: 'bay-' + index,
        role: 'bay',
        x_mm: round3(x),
        y_mm: 0,
        w_mm: round3(width),
        h_mm: height
      });
      var role = index % 3 === 1 ? 'drawer' : 'door';
      fronts.push({
        id: 'front-' + index,
        role: role,
        x_mm: round3(x),
        y_mm: 0,
        w_mm: round3(width),
        h_mm: height
      });
      x += width;
    }

    var model = {
      outer: {
        w_mm: round3(totalWidth || toPositiveNumber(safeParams.outer && safeParams.outer.w_mm, 762)),
        h_mm: height
      },
      bays: bays,
      fronts: fronts
    };

    var hash = computeHash(params);
    if (hash) {
      model.param_hash = hash;
      model.meta = model.meta || {};
      model.meta.param_hash = hash;
    }

    return model;
  }

  function handleMetrics(event) {
    if (!event || typeof event !== 'object') {
      return;
    }

    if (event.type === 'update') {
      if (typeof event.update_ms === 'number') {
        metrics.update_samples.push(event.update_ms);
      }
      if (typeof event.render_ms === 'number') {
        metrics.render_samples.push(event.render_ms);
      }
      if (event.hash) {
        metrics.last_params_hash = event.hash;
      }
      updateNodeMetrics(sampleDom());
      updateMemoryMetrics();
      updateTimingStats();
      updateMetricsDisplay();
    } else if (event.type === 'frame') {
      if (typeof event.render_frame_ms === 'number') {
        metrics.frame_samples.push(event.render_frame_ms);
      }
      updateTimingStats();
      updateMetricsDisplay();
    }
  }

  function updateTimingStats() {
    metrics.medians.update_ms = computeQuantile(metrics.update_samples, 0.5);
    metrics.p95.update_ms = computeQuantile(metrics.update_samples, 0.95);
    metrics.medians.frame_ms = computeQuantile(metrics.frame_samples, 0.5);
    metrics.p95.frame_ms = computeQuantile(metrics.frame_samples, 0.95);
  }

  function updateNodeMetrics(sample) {
    if (!sample) {
      return;
    }
    metrics.node_counts = sample;
    metrics.node_samples.push(sample);
    if (metrics.node_samples.length > 1) {
      var first = metrics.node_samples[0];
      metrics.node_drift = {
        total: sample.total - first.total,
        bays: sample.bays - first.bays,
        rects: sample.rects - first.rects
      };
    } else {
      metrics.node_drift = { total: 0, bays: 0, rects: 0 };
    }
  }

  function updateMemoryMetrics() {
    if (!window.performance || !window.performance.memory || typeof window.performance.memory.usedJSHeapSize !== 'number') {
      metrics.memory_drift_mb = null;
      return;
    }
    var memorySample = {
      used_js_heap: window.performance.memory.usedJSHeapSize,
      timestamp: now()
    };
    metrics.memory_samples.push(memorySample);
    if (metrics.memory_samples.length > 1) {
      var first = metrics.memory_samples[0];
      var deltaBytes = memorySample.used_js_heap - first.used_js_heap;
      metrics.memory_drift_mb = deltaBytes / (1024 * 1024);
    } else {
      metrics.memory_drift_mb = 0;
    }
  }

  function sampleDom() {
    if (!dom.host) {
      return null;
    }
    var total = dom.host.querySelectorAll('*').length;
    var bays = dom.host.querySelectorAll('[data-role="bay"]').length;
    var rects = dom.host.querySelectorAll('rect').length;
    return {
      total: total,
      bays: bays,
      rects: rects,
      timestamp: now()
    };
  }

  function updateStatusText() {
    if (!dom.statusText) {
      return;
    }
    var text = 'Idle — choose a fixture and press Start Stress.';
    if (metrics.status === 'running') {
      text = 'Running ' + metrics.iteration_count + ' / ' + metrics.iteration_target + ' iterations…';
    } else if (metrics.status === 'stopped') {
      text = 'Stopped before completion.';
    } else if (metrics.status === 'idle' && metrics.completed_at) {
      text = 'Last run completed ' + metrics.iteration_count + ' iterations.';
    }
    dom.statusText.textContent = text;
  }

  function updateMetricsDisplay() {
    if (dom.updateMedian) {
      dom.updateMedian.textContent = formatMs(metrics.medians.update_ms);
    }
    if (dom.updateP95) {
      dom.updateP95.textContent = formatMs(metrics.p95.update_ms);
    }
    if (dom.updateSamples) {
      dom.updateSamples.textContent = String(metrics.update_samples.length);
    }
    if (dom.frameMedian) {
      dom.frameMedian.textContent = formatMs(metrics.medians.frame_ms);
    }
    if (dom.frameP95) {
      dom.frameP95.textContent = formatMs(metrics.p95.frame_ms);
    }
    if (dom.frameSamples) {
      dom.frameSamples.textContent = String(metrics.frame_samples.length);
    }
    if (dom.nodeCount) {
      var countText = metrics.node_counts ? metrics.node_counts.total + ' total / ' + metrics.node_counts.bays + ' bays' : '—';
      dom.nodeCount.textContent = countText;
    }
    if (dom.nodeDrift) {
      var drift = metrics.node_drift ? metrics.node_drift.total : null;
      dom.nodeDrift.textContent = drift === null ? '—' : formatDelta(drift);
    }
    if (dom.memoryDrift) {
      if (metrics.memory_drift_mb === null || typeof metrics.memory_drift_mb === 'undefined') {
        dom.memoryDrift.textContent = 'n/a';
      } else {
        dom.memoryDrift.textContent = metrics.memory_drift_mb.toFixed(2) + ' MB';
      }
    }
  }

  function logSummary() {
    if (!window.console || typeof window.console.info !== 'function') {
      return;
    }
    window.console.info(
      '[LayoutPreviewPerf] Completed %d iterations (fixture: %s) — median %.1f ms (p95 %.1f ms); frame median %.1f ms (p95 %.1f ms).',
      metrics.iteration_count,
      state.fixtureKey,
      metrics.medians.update_ms || 0,
      metrics.p95.update_ms || 0,
      metrics.medians.frame_ms || 0,
      metrics.p95.frame_ms || 0
    );
  }

  function toggleButtons(running) {
    if (dom.startButton) {
      dom.startButton.disabled = running;
    }
    if (dom.stopButton) {
      dom.stopButton.disabled = !running;
    }
  }

  function getMetricsSnapshot() {
    return {
      status: metrics.status,
      iteration_target: metrics.iteration_target,
      iteration_count: metrics.iteration_count,
      medians: {
        update_ms: metrics.medians.update_ms,
        frame_ms: metrics.medians.frame_ms
      },
      p95: {
        update_ms: metrics.p95.update_ms,
        frame_ms: metrics.p95.frame_ms
      },
      samples: {
        update: metrics.update_samples.length,
        frame: metrics.frame_samples.length
      },
      node_counts: metrics.node_counts,
      node_drift: metrics.node_drift,
      memory_drift_mb: metrics.memory_drift_mb,
      last_params_hash: metrics.last_params_hash,
      last_fixture: metrics.last_fixture,
      seed: metrics.seed
    };
  }

  function buildRunSummary(aborted) {
    return {
      aborted: !!aborted,
      status: metrics.status,
      iteration_count: metrics.iteration_count,
      iteration_target: metrics.iteration_target,
      medians: metrics.medians,
      p95: metrics.p95,
      last_params_hash: metrics.last_params_hash
    };
  }

  function notifyReady() {
    if (window.sketchup && typeof window.sketchup.layout_preview_perf_ready === 'function') {
      try {
        window.sketchup.layout_preview_perf_ready('ready');
      } catch (error) {
        logWarn('layout_preview_perf_ready callback failed: ' + formatError(error));
      }
    }
  }

  function computeHash(params) {
    if (window.LayoutPreviewCtrl && typeof window.LayoutPreviewCtrl.computeParamHash === 'function') {
      return window.LayoutPreviewCtrl.computeParamHash(params);
    }
    try {
      return JSON.stringify(params);
    } catch (error) {
      return null;
    }
  }

  function createParamsFromFixture(fixture, key) {
    var widths = [];
    if (fixture && Array.isArray(fixture.bays)) {
      for (var index = 0; index < fixture.bays.length; index += 1) {
        widths.push(toPositiveNumber(fixture.bays[index].w_mm, MIN_BAY_WIDTH_MM));
      }
    }
    return {
      fixtureKey: key,
      outer: {
        w_mm: toPositiveNumber(fixture && fixture.outer && fixture.outer.w_mm, 762),
        h_mm: toPositiveNumber(fixture && fixture.outer && fixture.outer.h_mm, 762)
      },
      bay_widths_mm: widths,
      sequence: 0
    };
  }

  function cloneParams(params) {
    if (!params) {
      return null;
    }
    return {
      fixtureKey: params.fixtureKey,
      outer: {
        w_mm: toPositiveNumber(params.outer && params.outer.w_mm, 762),
        h_mm: toPositiveNumber(params.outer && params.outer.h_mm, 762)
      },
      bay_widths_mm: Array.isArray(params.bay_widths_mm) ? params.bay_widths_mm.slice() : [],
      sequence: params.sequence || 0
    };
  }

  function buildInlineFixtures() {
    return {
      stress12: buildFixtureFromWidths(
        [254, 279, 229, 305, 330, 279, 254, 330, 305, 279, 229, 305],
        762
      ),
      stress20: buildFixtureFromWidths(
        [203, 254, 229, 279, 229, 305, 254, 330, 279, 229, 305, 254, 330, 305, 254, 279, 254, 305, 279, 254],
        762
      )
    };
  }

  function buildFixtureFromWidths(widths, height) {
    var bays = [];
    var fronts = [];
    var x = 0;
    for (var index = 0; index < widths.length; index += 1) {
      var width = toPositiveNumber(widths[index], MIN_BAY_WIDTH_MM);
      bays.push({
        id: 'bay-' + index,
        role: 'bay',
        x_mm: round3(x),
        y_mm: 0,
        w_mm: round3(width),
        h_mm: height
      });
      var role = index % 3 === 1 ? 'drawer' : 'door';
      fronts.push({
        id: 'front-' + index,
        role: role,
        x_mm: round3(x),
        y_mm: 0,
        w_mm: round3(width),
        h_mm: height
      });
      x += width;
    }
    return {
      outer: {
        w_mm: round3(x),
        h_mm: height
      },
      bays: bays,
      fronts: fronts
    };
  }

  function createRng(seed) {
    var value = (seed >>> 0) || 1;
    return function rng() {
      value = (value + 0x6d2b79f5) >>> 0;
      var t = value;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function computeQuantile(samples, q) {
    if (!samples || samples.length === 0) {
      return null;
    }
    var ordered = samples.slice().sort(function (a, b) {
      return a - b;
    });
    var index = (ordered.length - 1) * q;
    var lower = Math.floor(index);
    var upper = Math.ceil(index);
    if (lower === upper) {
      return ordered[lower];
    }
    var weight = index - lower;
    return ordered[lower] * (1 - weight) + ordered[upper] * weight;
  }

  function formatMs(value) {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return '—';
    }
    return value.toFixed(1) + ' ms';
  }

  function formatDelta(value) {
    var numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric === 0) {
      return '±0';
    }
    var prefix = numeric > 0 ? '+' : '';
    return prefix + numeric;
  }

  function parseNumber(value, fallback) {
    var number = Number(value);
    if (!Number.isFinite(number)) {
      return fallback;
    }
    return number;
  }

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function toPositiveNumber(value, fallback) {
    var number = Number(value);
    if (!Number.isFinite(number) || number <= 0) {
      return fallback;
    }
    return number;
  }

  function round3(value) {
    return Math.round(value * 1000) / 1000;
  }

  function now() {
    if (window.performance && typeof window.performance.now === 'function') {
      return window.performance.now();
    }
    return Date.now();
  }

  function formatError(error) {
    if (!error) {
      return 'unknown error';
    }
    if (error && typeof error.message === 'string') {
      return error.message;
    }
    return String(error);
  }

  function logWarn(message) {
    if (window.console && typeof window.console.warn === 'function') {
      window.console.warn('[LayoutPreviewPerf] ' + message);
    }
  }

  window.LayoutPreviewPerfHarness = {
    startRun: startRun,
    stop: stopRun,
    whenIdle: whenIdle,
    applyFixture: applyFixture,
    resetMetrics: resetMetrics,
    currentParamsHash: function currentParamsHash() {
      return state.currentParamsHash;
    },
    getMetricsSnapshot: getMetricsSnapshot
  };
})();
