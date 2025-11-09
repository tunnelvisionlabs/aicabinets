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

      if (window.sketchup && typeof window.sketchup.requestSelectBay === 'function') {
        try {
          window.sketchup.requestSelectBay(bayId);
        } catch (error) {
          logError('requestSelectBay', error);
        }
      }
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

  window.LayoutPreviewHost = {
    mount: function (container, options) {
      return mount(container, options || {});
    }
  };
})();
