(function () {
  'use strict';

  var hostElement = null;
  var controller = null;
  var usingPreviewController = false;
  var controllerOptionsCache = null;

  function ensureHost() {
    if (!hostElement) {
      hostElement = document.querySelector('[data-role="layout-preview-host"]');
    }
    return hostElement;
  }

  function destroyController() {
    if (controller && typeof controller.destroy === 'function') {
      controller.destroy();
    }
    controller = null;
    controllerOptionsCache = null;
    usingPreviewController = false;
  }

  function renderLayout(layoutModel, options) {
    var container = ensureHost();
    if (!container || !window.LayoutPreview || typeof window.LayoutPreview.render !== 'function') {
      return false;
    }

    if (window.LayoutPreviewCtrl && typeof window.LayoutPreviewCtrl.init === 'function') {
      var previewController = ensureController(options || {});
      if (!previewController || typeof previewController.setLayoutModel !== 'function') {
        return false;
      }
      previewController.setLayoutModel(layoutModel || {}, options && options.params);
      return true;
    }

    destroyController();
    controller = window.LayoutPreview.render(container, layoutModel || {}, options || {});
    return true;
  }

  function updateLayout(layoutModel, options) {
    if (window.LayoutPreviewCtrl && typeof window.LayoutPreviewCtrl.init === 'function') {
      var previewController = ensureController(options || {});
      if (!previewController || typeof previewController.setLayoutModel !== 'function') {
        return false;
      }
      previewController.setLayoutModel(layoutModel || {}, options && options.params);
      return true;
    }

    if (controller && typeof controller.update === 'function') {
      controller.update(layoutModel || {});
      return true;
    }
    return renderLayout(layoutModel, options);
  }

  function setActiveBay(bayId, opts) {
    if (controller && typeof controller.setActiveBay === 'function') {
      return controller.setActiveBay(bayId, opts || {});
    }
    if (window.LayoutPreview && typeof window.LayoutPreview.setActiveBay === 'function') {
      return window.LayoutPreview.setActiveBay(bayId, opts || {});
    }
    return false;
  }

  function onParamsChanged(params, options) {
    if (!window.LayoutPreviewCtrl || typeof window.LayoutPreviewCtrl.init !== 'function') {
      return false;
    }
    var previewController = ensureController(options || {});
    if (!previewController || typeof previewController.onParamsChanged !== 'function') {
      return false;
    }
    return previewController.onParamsChanged(params || {});
  }

  function ensureController(options) {
    if (!window.LayoutPreviewCtrl || typeof window.LayoutPreviewCtrl.init !== 'function') {
      return null;
    }

    var container = ensureHost();
    if (!container || !window.LayoutPreview || typeof window.LayoutPreview.render !== 'function') {
      return null;
    }

    var normalized = normalizeControllerOptions(options || {});
    var merged = mergeControllerOptions(controllerOptionsCache, normalized);

    if (!controller || !usingPreviewController || shouldRecreateController(controllerOptionsCache, merged)) {
      destroyController();
      controller = window.LayoutPreviewCtrl.init(container, window.LayoutPreview, merged);
      usingPreviewController = true;
    }

    controllerOptionsCache = merged;
    return controller;
  }

  function normalizeControllerOptions(options) {
    var normalized = {};
    if (!options || typeof options !== 'object') {
      return normalized;
    }

    if (options.renderOptions && typeof options.renderOptions === 'object') {
      normalized.renderOptions = shallowClone(options.renderOptions);
    }

    if (Object.prototype.hasOwnProperty.call(options, 'debounceMs')) {
      normalized.debounceMs = options.debounceMs;
    }

    if (typeof options.modelBuilder === 'function') {
      normalized.modelBuilder = options.modelBuilder;
    }

    if (typeof options.onMetrics === 'function') {
      normalized.onMetrics = options.onMetrics;
    }

    return normalized;
  }

  function mergeControllerOptions(current, next) {
    var merged = {};

    if (current) {
      if (current.renderOptions && typeof current.renderOptions === 'object') {
        merged.renderOptions = shallowClone(current.renderOptions);
      }
      if (Object.prototype.hasOwnProperty.call(current, 'debounceMs')) {
        merged.debounceMs = current.debounceMs;
      }
      if (Object.prototype.hasOwnProperty.call(current, 'modelBuilder')) {
        merged.modelBuilder = current.modelBuilder;
      }
      if (Object.prototype.hasOwnProperty.call(current, 'onMetrics')) {
        merged.onMetrics = current.onMetrics;
      }
    }

    if (next) {
      if (next.renderOptions && typeof next.renderOptions === 'object') {
        merged.renderOptions = shallowClone(next.renderOptions);
      }
      if (Object.prototype.hasOwnProperty.call(next, 'debounceMs')) {
        merged.debounceMs = next.debounceMs;
      }
      if (Object.prototype.hasOwnProperty.call(next, 'modelBuilder')) {
        merged.modelBuilder = next.modelBuilder;
      }
      if (Object.prototype.hasOwnProperty.call(next, 'onMetrics')) {
        merged.onMetrics = next.onMetrics;
      }
    }

    return merged;
  }

  function shouldRecreateController(previous, next) {
    if (!controller || !usingPreviewController) {
      return true;
    }
    if (!previous) {
      return true;
    }

    if (hasChanged(previous.debounceMs, next.debounceMs)) {
      return true;
    }

    if (hasChanged(previous.modelBuilder, next.modelBuilder)) {
      return true;
    }

    if (hasChanged(previous.onMetrics, next.onMetrics)) {
      return true;
    }

    if (!shallowEqual(next.renderOptions, previous.renderOptions)) {
      return true;
    }

    return false;
  }

  function hasChanged(previous, next) {
    var prevDefined = typeof previous !== 'undefined';
    var nextDefined = typeof next !== 'undefined';
    if (!prevDefined && !nextDefined) {
      return false;
    }
    return previous !== next;
  }

  function shallowClone(value) {
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

  function shallowEqual(a, b) {
    if (a === b) {
      return true;
    }
    if (!a || !b) {
      return !a && !b;
    }
    var keysA = Object.keys(a);
    var keysB = Object.keys(b);
    if (keysA.length !== keysB.length) {
      return false;
    }
    for (var index = 0; index < keysA.length; index += 1) {
      var key = keysA[index];
      if (a[key] !== b[key]) {
        return false;
      }
    }
    return true;
  }

  function notifyReady() {
    if (window.sketchup && typeof window.sketchup.layout_preview_ready === 'function') {
      try {
        window.sketchup.layout_preview_ready('ready');
      } catch (error) {
        if (window.console && typeof window.console.warn === 'function') {
          window.console.warn('layout_preview_ready callback failed:', error);
        }
      }
    }
  }

  document.addEventListener('DOMContentLoaded', function onReady() {
    ensureHost();
    notifyReady();
  });

  window.addEventListener('unload', function onUnload() {
    destroyController();
  });

  window.AICabinets = window.AICabinets || {};
  window.AICabinets.UI = window.AICabinets.UI || {};
  window.AICabinets.UI.LayoutPreviewDialog = {
    renderLayout: renderLayout,
    updateLayout: updateLayout,
    onParamsChanged: onParamsChanged,
    setActiveBay: setActiveBay,
    destroy: destroyController,
    hostElement: function hostElementAccessor() {
      return ensureHost();
    }
  };
})();
