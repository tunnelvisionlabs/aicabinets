(function () {
  'use strict';

  // Debounce coalesces rapid param edits. 80ms trails the last event so slider
  // scrubs resolve within ~2 frames while still allowing idle leading updates.
  var DEFAULT_DEBOUNCE_MS = 80;
  var REQUEST_ANIMATION_FRAME_FALLBACK_MS = 16;

  function LayoutPreviewController(containerEl, rendererModule, options) {
    if (!containerEl || typeof containerEl !== 'object') {
      throw new Error('LayoutPreviewCtrl.init requires a host element.');
    }
    if (!rendererModule || typeof rendererModule.render !== 'function') {
      throw new Error('LayoutPreviewCtrl.init requires a renderer with a render() function.');
    }

    var opts = options || {};

    this.container = containerEl;
    this.rendererModule = rendererModule;
    this.rendererHandle = null;
    this.renderOptions = cloneObject(opts.renderOptions) || {};
    this.modelBuilder = typeof opts.modelBuilder === 'function' ? opts.modelBuilder : null;
    this.metricsCallback = typeof opts.onMetrics === 'function' ? opts.onMetrics : null;
    this.debounceMs = normalizeDebounceMs(opts.debounceMs);

    this.pendingParams = null;
    this.pendingHash = null;
    this.pendingStart = null;
    this.debounceTimer = null;
    this.renderBusy = false;
    this.destroyed = false;
    this.nextRequestId = 1;
    this.inflightRequest = null;
    this.lastAppliedHash = null;

    this.cacheEntry = {
      hash: null,
      model: null
    };

    this.flushPendingBound = this.flushPending.bind(this);
  }

  LayoutPreviewController.prototype.onParamsChanged = function onParamsChanged(params) {
    if (this.destroyed) {
      return false;
    }

    var hash = computeParamHash(params);

    if (hash && this.lastAppliedHash === hash && !this.pendingHash) {
      return false;
    }

    this.pendingParams = params;
    this.pendingHash = hash;
    this.pendingStart = now();

    if (!this.renderBusy && this.debounceTimer === null) {
      this.flushPending();
    } else {
      this.scheduleDebouncedFlush();
    }

    return true;
  };

  LayoutPreviewController.prototype.setLayoutModel = function setLayoutModel(layoutModel, params) {
    if (this.destroyed) {
      return false;
    }

    var hash = null;
    if (typeof params !== 'undefined') {
      hash = computeParamHash(params);
    } else if (layoutModel && typeof layoutModel === 'object') {
      if (typeof layoutModel.param_hash === 'string' && layoutModel.param_hash.length) {
        hash = layoutModel.param_hash;
      } else if (layoutModel.meta && typeof layoutModel.meta.param_hash === 'string') {
        hash = layoutModel.meta.param_hash;
      }
    }

    this.cacheEntry.hash = hash;
    this.cacheEntry.model = layoutModel || {};
    this.lastAppliedHash = hash;

    this.applyModel(hash, this.cacheEntry.model, now());
    return true;
  };

  LayoutPreviewController.prototype.setActiveBay = function setActiveBay(bayId, opts) {
    if (this.destroyed || !this.rendererHandle || typeof this.rendererHandle.setActiveBay !== 'function') {
      return false;
    }
    return this.rendererHandle.setActiveBay(bayId, opts || {});
  };

  LayoutPreviewController.prototype.destroy = function destroy() {
    if (this.destroyed) {
      return;
    }

    this.destroyed = true;
    if (this.debounceTimer !== null) {
      window.clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = null;
    this.pendingParams = null;
    this.pendingHash = null;
    this.inflightRequest = null;
    this.renderBusy = false;

    if (this.rendererHandle && typeof this.rendererHandle.destroy === 'function') {
      try {
        this.rendererHandle.destroy();
      } catch (error) {
        logError('destroy', error);
      }
    }

    this.rendererHandle = null;
    this.rendererModule = null;
    this.container = null;
    this.metricsCallback = null;
  };

  LayoutPreviewController.prototype.scheduleDebouncedFlush = function scheduleDebouncedFlush() {
    if (this.debounceTimer !== null) {
      window.clearTimeout(this.debounceTimer);
    }

    this.debounceTimer = window.setTimeout(this.flushPendingBound, this.debounceMs);
  };

  LayoutPreviewController.prototype.flushPending = function flushPending() {
    if (this.destroyed) {
      return;
    }

    if (typeof this.pendingHash === 'undefined' || this.pendingHash === null) {
      this.debounceTimer = null;
      return;
    }

    var hash = this.pendingHash;
    var params = this.pendingParams;
    var startedAt = this.pendingStart != null ? this.pendingStart : now();

    this.pendingHash = null;
    this.pendingParams = null;
    this.pendingStart = null;
    this.debounceTimer = null;

    if (hash && this.cacheEntry.hash === hash && this.cacheEntry.model) {
      this.renderBusy = true;
      this.applyModel(hash, this.cacheEntry.model, startedAt);
      return;
    }

    if (!this.modelBuilder) {
      this.renderBusy = false;
      return;
    }

    var requestId = this.nextRequestId;
    this.nextRequestId += 1;
    this.inflightRequest = {
      id: requestId,
      hash: hash,
      metricsStart: startedAt
    };
    this.renderBusy = true;

    var result;
    try {
      result = this.modelBuilder(params, hash);
    } catch (error) {
      this.inflightRequest = null;
      this.renderBusy = false;
      logError('modelBuilder', error);
      return;
    }

    if (result && typeof result.then === 'function') {
      handleAsyncResult(this, result, requestId, hash);
      return;
    }

    this.inflightRequest = null;
    this.cacheAndApplyModel(hash, result, startedAt);
  };

  LayoutPreviewController.prototype.cacheAndApplyModel = function cacheAndApplyModel(hash, model, metricsStart) {
    this.cacheEntry.hash = hash;
    this.cacheEntry.model = model || {};
    this.applyModel(hash, this.cacheEntry.model, metricsStart);
  };

  LayoutPreviewController.prototype.applyModel = function applyModel(hash, model, metricsStart) {
    if (this.destroyed) {
      return;
    }

    this.renderBusy = true;
    var startTimestamp = typeof metricsStart === 'number' ? metricsStart : now();
    var updateStart = now();

    if (!this.rendererHandle || typeof this.rendererHandle.update !== 'function') {
      this.rendererHandle = this.rendererModule.render(this.container, model || {}, this.renderOptions);
    } else {
      this.rendererHandle.update(model || {});
    }

    var domAppliedAt = now();
    this.renderBusy = false;
    this.lastAppliedHash = hash;

    emitMetrics(this.metricsCallback, {
      type: 'update',
      hash: hash,
      params_started_at: startTimestamp,
      dom_applied_at: domAppliedAt,
      update_ms: domAppliedAt - startTimestamp,
      render_ms: domAppliedAt - updateStart
    });

    var frameStart = domAppliedAt;
    raf(function onFrame(frameTime) {
      emitMetrics(
        this.metricsCallback,
        {
          type: 'frame',
          hash: hash,
          params_started_at: startTimestamp,
          dom_applied_at: domAppliedAt,
          frame_captured_at: frameTime,
          render_frame_ms: frameTime - frameStart
        }
      );
    }.bind(this));

    if (typeof this.pendingHash !== 'undefined' && this.pendingHash !== null) {
      this.scheduleDebouncedFlush();
    }
  };

  function handleAsyncResult(controller, promise, requestId, hash) {
    promise
      .then(function handleAsyncSuccess(model) {
        if (controller.destroyed) {
          return;
        }
        if (!controller.inflightRequest || controller.inflightRequest.id !== requestId) {
          controller.cacheEntry.hash = hash;
          controller.cacheEntry.model = model || {};
          controller.renderBusy = !!controller.inflightRequest;
          return;
        }
        var context = controller.inflightRequest;
        controller.inflightRequest = null;
        controller.cacheAndApplyModel(context.hash, model, context.metricsStart);
      })
      .catch(function handleAsyncFailure(error) {
        if (controller.destroyed) {
          return;
        }
        controller.inflightRequest = null;
        controller.renderBusy = false;
        logError('modelBuilder', error);
      });
  }

  function emitMetrics(callback, payload) {
    if (typeof callback === 'function' && payload) {
      try {
        callback(payload);
      } catch (error) {
        logError('metrics', error);
      }
    }
  }

  function normalizeDebounceMs(value) {
    var numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric < 0) {
      return DEFAULT_DEBOUNCE_MS;
    }
    if (numeric === 0) {
      return 0;
    }
    return Math.max(16, Math.min(160, Math.round(numeric)));
  }

  function computeParamHash(params) {
    try {
      return stableSerialize(params);
    } catch (error) {
      logError('hash', error);
      return '__hash_error__';
    }
  }

  function stableSerialize(value) {
    if (value === null) {
      return 'null';
    }

    var type = typeof value;
    if (type === 'number') {
      if (!Number.isFinite(value)) {
        return 'number:null';
      }
      return 'number:' + value;
    }
    if (type === 'string') {
      return 'string:' + JSON.stringify(value);
    }
    if (type === 'boolean') {
      return 'boolean:' + (value ? '1' : '0');
    }
    if (type === 'undefined') {
      return 'undefined:';
    }
    if (type === 'function') {
      return 'function:' + String(value);
    }
    if (type === 'symbol') {
      return 'symbol:' + String(value);
    }

    if (Array.isArray(value)) {
      return 'array:[' + value.map(stableSerialize).join(',') + ']';
    }

    var keys = Object.keys(value).sort();
    var parts = [];
    for (var index = 0; index < keys.length; index += 1) {
      var key = keys[index];
      parts.push(JSON.stringify(key) + ':' + stableSerialize(value[key]));
    }
    return 'object:{' + parts.join(',') + '}';
  }

  function cloneObject(value) {
    if (!value || typeof value !== 'object') {
      return null;
    }
    var clone = {};
    var keys = Object.keys(value);
    for (var index = 0; index < keys.length; index += 1) {
      clone[keys[index]] = value[keys[index]];
    }
    return clone;
  }

  function raf(callback) {
    if (typeof window.requestAnimationFrame === 'function') {
      return window.requestAnimationFrame(callback);
    }
    return window.setTimeout(function fallback() {
      callback(now());
    }, REQUEST_ANIMATION_FRAME_FALLBACK_MS);
  }

  function now() {
    if (window.performance && typeof window.performance.now === 'function') {
      return window.performance.now();
    }
    return Date.now();
  }

  function logError(scope, error) {
    if (!window.console || typeof window.console.error !== 'function') {
      return;
    }
    var message = error && error.message ? error.message : String(error);
    window.console.error('[LayoutPreviewCtrl:' + scope + '] ' + message);
  }

  window.LayoutPreviewCtrl = {
    init: function initController(containerEl, rendererModule, options) {
      return new LayoutPreviewController(containerEl, rendererModule, options || {});
    },
    computeParamHash: computeParamHash,
    DEFAULT_DEBOUNCE_MS: DEFAULT_DEBOUNCE_MS
  };
})();
