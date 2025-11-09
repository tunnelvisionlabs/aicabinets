(function () {
  'use strict';

  var hostElement = null;
  var controller = null;

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
  }

  function renderLayout(layoutModel, options) {
    var container = ensureHost();
    if (!container || !window.LayoutPreview || typeof window.LayoutPreview.render !== 'function') {
      return false;
    }

    destroyController();
    controller = window.LayoutPreview.render(container, layoutModel || {}, options || {});
    return true;
  }

  function updateLayout(layoutModel) {
    if (controller && typeof controller.update === 'function') {
      controller.update(layoutModel || {});
      return true;
    }
    return renderLayout(layoutModel);
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
    setActiveBay: setActiveBay,
    destroy: destroyController,
    hostElement: function hostElementAccessor() {
      return ensureHost();
    }
  };
})();
