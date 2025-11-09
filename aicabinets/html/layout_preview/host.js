(function () {
  'use strict';

  function mount(container, options) {
    if (!container || typeof container !== 'object') {
      throw new Error('LayoutPreviewHost.mount requires a container element.');
    }

    if (!window.LayoutPreview || typeof window.LayoutPreview.render !== 'function') {
      throw new Error('LayoutPreview renderer is unavailable.');
    }

    var renderOptions = options && options.renderOptions ? options.renderOptions : {};
    var handle = window.LayoutPreview.render(container, {}, renderOptions);
    var destroyed = false;
    var previousHandler = null;

    if (window.LayoutPreview && typeof Object.getOwnPropertyDescriptor === 'function') {
      try {
        previousHandler = window.LayoutPreview.onRequestSelectBay;
      } catch (error) {
        previousHandler = null;
      }
    } else {
      previousHandler = window.LayoutPreview.onRequestSelectBay;
    }

    window.LayoutPreview.onRequestSelectBay = function (bayId) {
      if (options && typeof options.onRequestSelect === 'function') {
        try {
          options.onRequestSelect(bayId);
        } catch (error) {
          logError('onRequestSelect', error);
        }
      }

      forwardSelectRequest(bayId);
    };

    if (container.classList && !container.classList.contains('lp-host')) {
      container.classList.add('lp-host');
    }

    function update(model) {
      if (destroyed || !handle || typeof handle.update !== 'function') {
        return false;
      }
      handle.update(model || {});
      return true;
    }

    function setActiveBay(bayId, opts) {
      if (destroyed || !handle || typeof handle.setActiveBay !== 'function') {
        return false;
      }
      return handle.setActiveBay(bayId, opts || {});
    }

    function destroy() {
      if (destroyed) {
        return;
      }
      destroyed = true;

      try {
        window.LayoutPreview.onRequestSelectBay = previousHandler;
      } catch (error) {
        logError('restore-handler', error);
      }

      if (handle && typeof handle.destroy === 'function') {
        try {
          handle.destroy();
        } catch (error) {
          logError('destroy', error);
        }
      }
    }

    return {
      update: update,
      setActiveBay: setActiveBay,
      destroy: destroy
    };
  }

  function logError(context, error) {
    if (!error) {
      return;
    }
    if (window.console && typeof window.console.warn === 'function') {
      window.console.warn('LayoutPreviewHost ' + context + ' failed:', error);
    }
  }

  function forwardSelectRequest(bayId) {
    var bridge = findSketchupBridge();
    if (bridge && typeof bridge.requestSelectBay === 'function') {
      try {
        bridge.requestSelectBay(bayId);
        return true;
      } catch (error) {
        logError('requestSelectBay', error);
      }
    }

    if (window.parent && typeof window.parent.postMessage === 'function') {
      try {
        window.parent.postMessage({ type: 'aicabinets/requestSelectBay', bayId: bayId }, '*');
        return true;
      } catch (error) {
        logError('postMessage', error);
      }
    }

    if (window.sketchup && typeof window.sketchup.requestSelectBay === 'function') {
      try {
        window.sketchup.requestSelectBay(bayId);
        return true;
      } catch (error) {
        logError('requestSelectBay-local', error);
      }
    }

    return false;
  }

  function findSketchupBridge() {
    var candidates = [];
    try {
      if (window.parent && window.parent !== window) {
        candidates.push(window.parent);
      }
    } catch (error) {
      // Accessing window.parent can throw for cross-origin frames; ignore and continue.
    }

    try {
      if (window.top && window.top !== window && window.top !== window.parent) {
        candidates.push(window.top);
      }
    } catch (error) {
      // Ignore cross-origin violations; continue to local candidate.
    }

    candidates.push(window);

    for (var i = 0; i < candidates.length; i += 1) {
      var candidate = candidates[i];
      try {
        if (candidate && candidate.sketchup && typeof candidate.sketchup.requestSelectBay === 'function') {
          return candidate.sketchup;
        }
      } catch (error) {
        // Accessing candidate.sketchup may throw; continue to next candidate.
      }
    }

    return null;
  }

  window.LayoutPreviewHost = {
    mount: function (container, options) {
      return mount(container, options || {});
    }
  };
})();
