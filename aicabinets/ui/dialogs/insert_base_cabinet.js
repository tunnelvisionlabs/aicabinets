(function () {
  'use strict';

  function invokeSketchUp(action, payload) {
    if (!action) {
      return;
    }

    if (window.sketchup && typeof window.sketchup[action] === 'function') {
      window.sketchup[action](payload);
    }
  }

  function requestSketchUpFocus() {
    if (typeof window.blur !== 'function') {
      return;
    }

    window.setTimeout(function () {
      try {
        window.blur();
      } catch (error) {
        // Ignore focus errors; SketchUp will retain the previous focus target.
      }
    }, 0);
  }

  function restoreDialogFocus() {
    if (typeof window.focus !== 'function') {
      return;
    }

    window.setTimeout(function () {
      try {
        window.focus();
      } catch (error) {
        // Ignore focus errors; the dialog will remain in its prior state.
      }
    }, 0);
  }

  var root = (window.AICabinets = window.AICabinets || {});
  var uiRoot = (root.UI = root.UI || {});
  var namespace = (uiRoot.InsertBaseCabinet = uiRoot.InsertBaseCabinet || {});
  var insertFormNamespace = (uiRoot.InsertForm = uiRoot.InsertForm || {});

  var controller = null;
  var testSupport = {
    enabled: window.__AICABINETS_TEST__ === true,
    readyPromise: null,
    readyResolve: null,
    lastLiveRegion: '',
    pendingDoubleValidity: [],
    waitForDoubleValidity: function waitForDoubleValidity(index) {
      if (!this.enabled) {
        return Promise.resolve();
      }

      var numeric = Number(index);
      if (!isFinite(numeric)) {
        numeric = 0;
      }

      return new Promise(function (resolve) {
        testSupport.pendingDoubleValidity.push({ index: numeric, resolve: resolve });
      });
    },
    resolveDoubleValidity: function resolveDoubleValidity(index) {
      if (!this.enabled || !this.pendingDoubleValidity.length) {
        return;
      }

      var numeric = Number(index);
      if (!isFinite(numeric)) {
        numeric = 0;
      }

      for (var i = 0; i < this.pendingDoubleValidity.length; i += 1) {
        var entry = this.pendingDoubleValidity[i];
        if (!entry) {
          continue;
        }
        if (entry.index === numeric) {
          this.pendingDoubleValidity.splice(i, 1);
          try {
            entry.resolve();
          } catch (error) {
            // Ignore test-mode resolution errors to avoid masking dialog issues.
          }
          break;
        }
      }
    }
  };
  if (testSupport.enabled) {
    testSupport.readyPromise = new Promise(function (resolve) {
      testSupport.readyResolve = resolve;
    });
  }
  var pendingUnitSettings = null;
  var pendingDefaults = null;
  var pendingConfiguration = null;
  var pendingPlacementEvents = [];
  var pendingBayState = null;
  var pendingBayValidity = [];
  var pendingToasts = [];

  var layoutPreviewManager = (function () {
    var state = {
      enabled: false,
      pane: null,
      container: null,
      loadPromise: null,
      readyPromise: null,
      hostHandle: null
    };

    function enable(options) {
      ensureReady(options);
      return true;
    }

    function update(model) {
      var payload = parseModelPayload(model);
      if (!payload) {
        return false;
      }
      withHost(function (host) {
        if (host && typeof host.update === 'function') {
          host.update(payload);
        }
      });
      return true;
    }

    function setActiveBay(bayId, opts) {
      withHost(function (host) {
        if (host && typeof host.setActiveBay === 'function') {
          host.setActiveBay(bayId, opts || {});
        }
      });
      return true;
    }

    function selectBay(selection) {
      var data = parseSelectionPayload(selection);
      if (!data) {
        return false;
      }
      whenReady(function (formController) {
        applySelectionToForm(formController, data);
        return true;
      }).catch(function (error) {
        logPreviewError('selectBay', error);
      });
      return true;
    }

    function destroy() {
      state.enabled = false;
      if (state.hostHandle && typeof state.hostHandle.destroy === 'function') {
        try {
          state.hostHandle.destroy();
        } catch (error) {
          logPreviewError('destroy', error);
        }
      }
      state.hostHandle = null;
      state.readyPromise = null;
      state.loadPromise = null;
      state.container = null;
      if (state.pane) {
        state.pane.hidden = true;
      }
      document.body.classList.remove('has-layout-preview');
      return true;
    }

    function isReady() {
      return !!state.hostHandle;
    }

    function ensureReady(options) {
      state.enabled = true;
      ensurePane();
      if (!state.readyPromise) {
        state.readyPromise = loadAssets()
          .then(function () {
            ensurePane();
            var host = mountHost(options);
            if (!host) {
              throw new Error('LayoutPreviewHost unavailable');
            }
            state.hostHandle = host;
            return host;
          })
          .catch(function (error) {
            logPreviewError('enable', error);
            state.readyPromise = null;
            throw error;
          });
      }
      return state.readyPromise;
    }

    function withHost(callback, options) {
      ensureReady(options)
        .then(function (host) {
          if (!host || typeof callback !== 'function') {
            return;
          }
          try {
            callback(host);
          } catch (error) {
            logPreviewError('callback', error);
          }
        })
        .catch(function (error) {
          logPreviewError('withHost', error);
        });
    }

    function ensurePane() {
      if (!state.pane) {
        state.pane = document.querySelector('[data-role="layout-preview-pane"]');
      }
      if (state.pane && state.pane.hidden) {
        state.pane.hidden = false;
      }
      if (!state.container) {
        if (state.pane) {
          state.container = state.pane.querySelector('[data-role="layout-preview-container"]');
        }
        if (!state.container) {
          state.container = document.querySelector('[data-role="layout-preview-container"]');
        }
      }
      if (state.pane && state.container) {
        document.body.classList.add('has-layout-preview');
      }
    }

    function loadAssets() {
      if (state.loadPromise) {
        return state.loadPromise;
      }
      state.loadPromise = loadStylesheet('../layout_preview/renderer.css')
        .then(function () {
          return loadScript('../layout_preview/renderer.js');
        })
        .then(function () {
          return loadScript('../layout_preview/a11y.js');
        })
        .then(function () {
          return loadScript('../layout_preview/host.js');
        })
        .catch(function (error) {
          state.loadPromise = null;
          throw error;
        });
      return state.loadPromise;
    }

    function loadStylesheet(href) {
      return new Promise(function (resolve, reject) {
        var existing = document.querySelector('link[data-layout-preview-css="' + href + '"]');
        if (existing) {
          resolve(existing);
          return;
        }
        var link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = href;
        link.dataset.layoutPreviewCss = href;
        link.addEventListener('load', function () {
          resolve(link);
        });
        link.addEventListener('error', function () {
          reject(new Error('Failed to load stylesheet: ' + href));
        });
        document.head.appendChild(link);
      });
    }

    function loadScript(src) {
      return new Promise(function (resolve, reject) {
        var existing = document.querySelector('script[data-layout-preview-script="' + src + '"]');
        if (existing) {
          resolve(existing);
          return;
        }
        var script = document.createElement('script');
        script.src = src;
        script.async = false;
        script.dataset.layoutPreviewScript = src;
        script.addEventListener('load', function () {
          resolve(script);
        });
        script.addEventListener('error', function () {
          reject(new Error('Failed to load script: ' + src));
        });
        document.head.appendChild(script);
      });
    }

    function mountHost(options) {
      if (!state.container || !window.LayoutPreviewHost || typeof window.LayoutPreviewHost.mount !== 'function') {
        return null;
      }
      try {
        return window.LayoutPreviewHost.mount(state.container, options || {});
      } catch (error) {
        logPreviewError('mount', error);
        return null;
      }
    }

    function parseModelPayload(model) {
      if (!model) {
        return {};
      }
      if (typeof model === 'string') {
        try {
          return JSON.parse(model);
        } catch (error) {
          logPreviewError('parse-model', error);
          return {};
        }
      }
      if (typeof model === 'object') {
        return model;
      }
      return {};
    }

    function parseSelectionPayload(payload) {
      if (!payload) {
        return null;
      }
      if (typeof payload === 'string') {
        try {
          return JSON.parse(payload);
        } catch (error) {
          return null;
        }
      }
      if (typeof payload === 'object') {
        return payload;
      }
      return null;
    }

    function applySelectionToForm(formController, data) {
      if (!formController) {
        return;
      }
      var partitions = (formController.values || {}).partitions || {};
      var bays = Array.isArray(partitions.bays) ? partitions.bays : [];
      var length = bays.length || 1;
      var index = Number(data.index);
      if (!Number.isFinite(index)) {
        index = 0;
      }
      var clamped = clampSelectedIndex(index, length);
      formController.selectedBayIndex = clamped;
      formController.pendingSelectedBayIndex = clamped;
      if (formController.bayController && typeof formController.bayController.setSelectedIndex === 'function') {
        formController.bayController.setSelectedIndex(clamped, {
          emit: data.emit === true,
          focus: data.focus !== false,
          announce: data.announce !== false,
          requestValidity: data.requestValidity !== false
        });
      }
    }

    function logPreviewError(context, error) {
      if (!error) {
        return;
      }
      if (window.console && typeof window.console.warn === 'function') {
        window.console.warn('Layout preview ' + context + ' failed:', error);
      }
    }

    return {
      enable: enable,
      update: update,
      setActiveBay: setActiveBay,
      selectBay: selectBay,
      destroy: destroy,
      isReady: isReady
    };
  })();

  namespace.layoutPreview = layoutPreviewManager;

  var BAY_MODES = ['fronts_shelves', 'subpartitions'];

  var UNIT_TO_MM = {
    inch: 25.4,
    foot: 304.8,
    millimeter: 1,
    centimeter: 10,
    meter: 1000
  };

  var LENGTH_FIELDS = [
    'width',
    'depth',
    'height',
    'panel_thickness',
    'toe_kick_height',
    'toe_kick_depth'
  ];

  var LENGTH_DEFAULT_KEYS = {
    width: 'width_mm',
    depth: 'depth_mm',
    height: 'height_mm',
    panel_thickness: 'panel_thickness_mm',
    toe_kick_height: 'toe_kick_height_mm',
    toe_kick_depth: 'toe_kick_depth_mm'
  };

  var INTEGER_FIELDS = ['shelves', 'partitions_count'];

  var UI_PAYLOAD_VERSION = '1.0.0';

  var stringsNamespace = uiRoot.Strings || {};

  function formatTemplate(template, params) {
    if (typeof template !== 'string') {
      return template;
    }

    if (!params || typeof params !== 'object') {
      return template;
    }

    return template.replace(/%\{(\w+)\}/g, function (_, key) {
      if (Object.prototype.hasOwnProperty.call(params, key)) {
        return String(params[key]);
      }
      return '%{' + key + '}';
    });
  }

  function translate(key, params) {
    if (stringsNamespace && typeof stringsNamespace.t === 'function') {
      return stringsNamespace.t(key, params);
    }

    if (typeof key === 'string' && key.indexOf('%{') !== -1) {
      return formatTemplate(key, params);
    }

    return key;
  }

  var FOCUSABLE_SELECTOR =
    'a[href], area[href], button, input, select, textarea, [tabindex], [contenteditable="true"]';

  function collapseWhitespace(value) {
    if (value == null) {
      return '';
    }

    return String(value).replace(/\s+/g, ' ').trim();
  }

  function ensureDescribedBy(control, id) {
    if (!control || !id) {
      return;
    }

    var tokens = (control.getAttribute('aria-describedby') || '').split(/\s+/).filter(Boolean);
    if (tokens.indexOf(id) === -1) {
      tokens.push(id);
    }

    if (tokens.length) {
      control.setAttribute('aria-describedby', tokens.join(' '));
    }
  }

  function setElementInert(element, inert) {
    if (!element) {
      return;
    }

    if ('inert' in element) {
      element.inert = !!inert;
      if (!inert) {
        element.removeAttribute('aria-hidden');
      }
      return;
    }

    if (inert) {
      element.setAttribute('aria-hidden', 'true');
      element.setAttribute('data-inert-applied', 'true');
      var focusable = element.querySelectorAll(FOCUSABLE_SELECTOR);
      for (var index = 0; index < focusable.length; index += 1) {
        var node = focusable[index];
        if (!node) {
          continue;
        }
        if (!node.hasAttribute('data-inert-tabindex')) {
          var current = node.getAttribute('tabindex');
          node.setAttribute('data-inert-tabindex', current != null ? current : '');
        }
        node.setAttribute('tabindex', '-1');
      }
    } else {
      if (element.getAttribute('data-inert-applied') === 'true') {
        element.removeAttribute('data-inert-applied');
        var nodes = element.querySelectorAll('[data-inert-tabindex]');
        for (var i = 0; i < nodes.length; i += 1) {
          var target = nodes[i];
          if (!target) {
            continue;
          }
          var previous = target.getAttribute('data-inert-tabindex');
          target.removeAttribute('data-inert-tabindex');
          if (previous === null || previous === '') {
            target.removeAttribute('tabindex');
          } else {
            target.setAttribute('tabindex', previous);
          }
        }
      }
      element.removeAttribute('aria-hidden');
    }
  }

  function LiveAnnouncer(element, options) {
    options = options || {};
    this.element = element || null;
    this.delay = typeof options.delay === 'number' && options.delay >= 0 ? options.delay : 200;
    this.pendingMessage = '';
    this.timerId = null;
  }

  LiveAnnouncer.prototype.setElement = function setElement(element) {
    this.element = element || null;
  };

  LiveAnnouncer.prototype.sanitize = function sanitize(message) {
    if (message == null) {
      return '';
    }

    var text = String(message);
    if (!text) {
      return '';
    }

    return text.replace(/\s+/g, ' ').trim();
  };

  LiveAnnouncer.prototype.post = function post(message, options) {
    var text = this.sanitize(message);
    if (!text || !this.element) {
      return;
    }

    this.pendingMessage = text;
    var immediate = options && options.immediate;
    var delay = this.delay;
    if (options && typeof options.delay === 'number' && options.delay >= 0) {
      delay = options.delay;
    }

    if (immediate) {
      this.flush();
      return;
    }

    var self = this;
    window.clearTimeout(this.timerId);
    this.timerId = window.setTimeout(function () {
      self.flush();
    }, delay);
  };

  LiveAnnouncer.prototype.flush = function flush() {
    if (!this.element || !this.pendingMessage) {
      return;
    }

    window.clearTimeout(this.timerId);
    this.timerId = null;

    var message = this.pendingMessage;
    this.pendingMessage = '';

    this.element.textContent = '';
    this.element.textContent = message;
    window.__AICABINETS_LAST_LIVE_REGION__ = message;
    if (testSupport.enabled) {
      testSupport.lastLiveRegion = message;
    }
  };

  LiveAnnouncer.prototype.clear = function clear() {
    window.clearTimeout(this.timerId);
    this.timerId = null;
    this.pendingMessage = '';
    if (this.element) {
      this.element.textContent = '';
    }
    window.__AICABINETS_LAST_LIVE_REGION__ = '';
    if (testSupport.enabled) {
      testSupport.lastLiveRegion = '';
    }
  };

  function parsePayload(value) {
    if (typeof value === 'string') {
      try {
        return JSON.parse(value);
      } catch (error) {
        return null;
      }
    }

    return value;
  }

  function clampSelectedIndex(index, bayCount) {
    var length = Number(bayCount);
    if (!isFinite(length) || length < 1) {
      length = 1;
    } else {
      length = Math.round(length);
      if (length < 1) {
        length = 1;
      }
    }

    var numeric = Number(index);
    if (!isFinite(numeric)) {
      numeric = 0;
    }

    numeric = Math.round(numeric);
    if (numeric < 0) {
      numeric = 0;
    }
    if (numeric >= length) {
      numeric = length - 1;
    }

    return numeric;
  }

  function isInputDisabled(input) {
    if (!input) {
      return true;
    }

    if (input.disabled) {
      return true;
    }

    if (input.getAttribute && input.getAttribute('aria-disabled') === 'true') {
      return true;
    }

    return false;
  }

  function findFirstEnabledIndex(inputs) {
    if (!inputs || !inputs.length) {
      return -1;
    }

    for (var index = 0; index < inputs.length; index += 1) {
      if (!isInputDisabled(inputs[index])) {
        return index;
      }
    }

    return -1;
  }

  function findLastEnabledIndex(inputs) {
    if (!inputs || !inputs.length) {
      return -1;
    }

    for (var index = inputs.length - 1; index >= 0; index -= 1) {
      if (!isInputDisabled(inputs[index])) {
        return index;
      }
    }

    return -1;
  }

  function findNextEnabledIndex(inputs, startIndex, delta) {
    if (!inputs || !inputs.length) {
      return startIndex;
    }

    var length = inputs.length;
    if (length < 1) {
      return startIndex;
    }

    var normalized = Number(startIndex);
    if (!isFinite(normalized)) {
      normalized = 0;
    }
    normalized = Math.round(normalized);
    if (normalized < 0) {
      normalized = 0;
    }
    if (normalized >= length) {
      normalized = length - 1;
    }

    for (var step = 0; step < length; step += 1) {
      normalized = (normalized + delta + length) % length;
      if (!isInputDisabled(inputs[normalized])) {
        return normalized;
      }
    }

    return startIndex;
  }

  function activateSegmentedInputElement(input) {
    if (!input || input.disabled) {
      return;
    }

    if (typeof input.click === 'function') {
      input.click();
    } else {
      input.checked = true;
      var changeEvent = document.createEvent('Event');
      changeEvent.initEvent('change', true, true);
      input.dispatchEvent(changeEvent);
    }

    if (typeof input.focus === 'function') {
      input.focus();
    }
  }

  function handleSegmentedGroupKeyDown(inputs, event) {
    if (!event || !inputs || !inputs.length) {
      return;
    }

    var list = Array.isArray(inputs) ? inputs : Array.prototype.slice.call(inputs);
    var target = event.target;
    var index = list.indexOf(target);
    if (index === -1) {
      return;
    }

    var key = event.key || event.keyCode;
    var nextIndex = null;
    var handled = false;

    if (
      key === 'ArrowRight' ||
      key === 'Right' ||
      key === 39 ||
      key === 'ArrowDown' ||
      key === 'Down' ||
      key === 40
    ) {
      nextIndex = findNextEnabledIndex(list, index, 1);
      handled = true;
    } else if (
      key === 'ArrowLeft' ||
      key === 'Left' ||
      key === 37 ||
      key === 'ArrowUp' ||
      key === 'Up' ||
      key === 38
    ) {
      nextIndex = findNextEnabledIndex(list, index, -1);
      handled = true;
    } else if (key === 'Home' || key === 36) {
      nextIndex = findFirstEnabledIndex(list);
      handled = true;
    } else if (key === 'End' || key === 35) {
      nextIndex = findLastEnabledIndex(list);
      handled = true;
    }

    if (!handled) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    if (nextIndex == null || nextIndex === -1 || nextIndex === index) {
      return;
    }

    activateSegmentedInputElement(list[nextIndex]);
  }

  function bindSegmentedGroupKeyHandlers(inputs) {
    if (!inputs || !inputs.length) {
      return;
    }

    var list = Array.isArray(inputs) ? inputs.slice() : Array.prototype.slice.call(inputs);
    list.forEach(function (input) {
      if (!input || input.__aicSegmentedKeyHandler) {
        return;
      }

      var handler = function (event) {
        handleSegmentedGroupKeyDown(list, event);
      };

      input.addEventListener('keydown', handler);
      input.__aicSegmentedKeyHandler = handler;
    });
  }

  function normalizeBayMode(mode) {
    if (typeof mode === 'string') {
      var text = mode.trim().toLowerCase();
      if (BAY_MODES.indexOf(text) !== -1) {
        return text;
      }
    }

    return 'fronts_shelves';
  }

  function normalizeDoorMode(value) {
    if (value == null) {
      return null;
    }

    var text = String(value).trim();
    if (!text) {
      return null;
    }

    if (text === 'none') {
      return null;
    }

    if (text === 'empty' || text === 'doors_left' || text === 'doors_right' || text === 'doors_double') {
      return text;
    }

    return null;
  }

  function cloneFrontsShelvesState(source) {
    var state = source && typeof source === 'object' ? source : {};
    var shelfValue = state.shelf_count;
    var shelf = Number(shelfValue);
    if (!isFinite(shelf)) {
      shelf = 0;
    }
    shelf = Math.max(0, Math.round(shelf));

    var door = state.door_mode;
    if (door == null && Object.prototype.hasOwnProperty.call(state, 'door_mode')) {
      door = state.door_mode;
    }

    return {
      shelf_count: shelf,
      door_mode: normalizeDoorMode(door)
    };
  }

  function cloneSubpartitionState(source) {
    var state = source && typeof source === 'object' ? source : {};
    var countValue = state.count;
    var count = Number(countValue);
    if (!isFinite(count)) {
      count = 0;
    }
    count = Math.max(0, Math.round(count));

    return {
      count: count
    };
  }

  function cloneBay(bay) {
    if (!bay || typeof bay !== 'object') {
      return {
        mode: 'fronts_shelves',
        shelf_count: 0,
        door_mode: null,
        fronts_shelves_state: { shelf_count: 0, door_mode: null },
        subpartitions_state: { count: 0 }
      };
    }

    var frontsSource = bay.fronts_shelves_state && typeof bay.fronts_shelves_state === 'object' ? bay.fronts_shelves_state : bay;
    var fronts = cloneFrontsShelvesState(frontsSource);
    if (fronts.door_mode == null && bay.door_mode != null) {
      fronts.door_mode = normalizeDoorMode(bay.door_mode);
    }
    if ((fronts.shelf_count == null || !isFinite(fronts.shelf_count)) && typeof bay.shelf_count === 'number') {
      fronts.shelf_count = Math.max(0, Math.round(bay.shelf_count));
    }

    var subpartitions = cloneSubpartitionState(bay.subpartitions_state);

    return {
      mode: normalizeBayMode(bay.mode),
      shelf_count: fronts.shelf_count,
      door_mode: fronts.door_mode,
      fronts_shelves_state: fronts,
      subpartitions_state: subpartitions
    };
  }

  function cloneSubpartitionsForTest(source) {
    if (!source || typeof source !== 'object') {
      return null;
    }

    var bays = Array.isArray(source.bays)
      ? source.bays.map(function (entry) {
          return cloneBayForTest(entry);
        })
      : [];

    return {
      count: typeof source.count === 'number' ? source.count : 0,
      orientation: source.orientation || null,
      bays: bays
    };
  }

  function cloneBayForTest(bay) {
    if (!bay || typeof bay !== 'object') {
      return null;
    }

    var clone = cloneBay(bay);
    var result = {
      mode: clone.mode,
      shelf_count: clone.shelf_count,
      door_mode: clone.door_mode,
      fronts_shelves_state: {
        shelf_count: clone.fronts_shelves_state
          ? clone.fronts_shelves_state.shelf_count
          : null,
        door_mode: clone.fronts_shelves_state
          ? clone.fronts_shelves_state.door_mode
          : null
      },
      subpartitions_state: {
        count: clone.subpartitions_state ? clone.subpartitions_state.count : 0
      }
    };

    if (bay.subpartitions && typeof bay.subpartitions === 'object') {
      result.subpartitions = cloneSubpartitionsForTest(bay.subpartitions);
    }

    return result;
  }

  function isElementVisible(element) {
    if (!element) {
      return false;
    }

    if (element.hidden) {
      return false;
    }
    if (element.getAttribute && element.getAttribute('aria-hidden') === 'true') {
      return false;
    }
    if (element.classList && element.classList.contains('is-hidden')) {
      return false;
    }

    return true;
  }

  function gatherPartitionRadioLabels() {
    if (!controller || !controller.partitionModeInputs) {
      return [];
    }

    return controller.partitionModeInputs.map(function (input) {
      if (!input || !input.id || !controller.form) {
        return '';
      }

      var escaped = input.id.replace(/(["\\])/g, '\\$1');
      var label = controller.form.querySelector('label[for="' + escaped + '"]');
      return label ? collapseWhitespace(label.textContent) : '';
    });
  }

  function gatherChipData() {
    if (!controller || !controller.bayController || !controller.bayController.chipButtons) {
      return [];
    }

    return controller.bayController.chipButtons.map(function (button, index) {
      if (!button) {
        return {
          index: index,
          label: '',
          selected: false,
          tabIndex: null,
          ariaDisabled: false
        };
      }

      return {
        index: index,
        label: collapseWhitespace(button.textContent),
        selected: button.getAttribute('aria-selected') === 'true',
        tabIndex: typeof button.tabIndex === 'number' ? button.tabIndex : null,
        ariaDisabled: button.getAttribute('aria-disabled') === 'true'
      };
    });
  }

  function collectDoubleDoorState(bayController) {
    if (!bayController) {
      return null;
    }

    var input = bayController.doubleDoorInput || null;
    var hint = bayController.hint || null;
    var validity = Array.isArray(bayController.doubleValidity)
      ? bayController.doubleValidity[bayController.selectedIndex]
      : null;

    return {
      disabled: input ? input.disabled === true : false,
      checked: input ? input.checked === true : false,
      tabIndex: input && typeof input.tabIndex === 'number' ? input.tabIndex : null,
      hint: hint ? collapseWhitespace(hint.textContent) : '',
      hintVisible: !!(hint && !hint.hidden && collapseWhitespace(hint.textContent)),
      validity: validity
        ? {
            allowed: validity.allowed !== false,
            reason: validity.reason || null,
            leafWidthMm: validity.leafWidthMm,
            minLeafWidthMm: validity.minLeafWidthMm
          }
        : null
    };
  }

  function collectState() {
    if (testSupport.enabled && controller && controller.liveAnnouncer) {
      controller.liveAnnouncer.flush();
    }

    if (!controller) {
      return {
        partition_mode: null,
        count: null,
        selected_bay_index: null,
        gating: {
          globalsVisible: false,
          shelvesVisible: false,
          partitionControlsVisible: false,
          baysVisible: false
        },
        chips: [],
        a11y: {},
        baySnapshot: {},
        announcement: testSupport.lastLiveRegion || window.__AICABINETS_LAST_LIVE_REGION__ || ''
      };
    }

    var values = controller.values || {};
    var partitions = values.partitions || {};
    var bays = Array.isArray(partitions.bays) ? partitions.bays.slice() : [];
    var selectedIndex = controller.selectedBayIndex != null ? controller.selectedBayIndex : 0;
    var fieldset = controller.partitionModeFieldset || null;
    var legend = fieldset ? fieldset.querySelector('legend') : null;
    var statusRegion = controller.statusRegion || null;
    var liveRegionData = {
      role: statusRegion ? statusRegion.getAttribute('role') || '' : '',
      ariaLive: statusRegion ? statusRegion.getAttribute('aria-live') || '' : '',
      ariaAtomic: statusRegion ? statusRegion.getAttribute('aria-atomic') || '' : ''
    };
    var chipInfo = gatherChipData();

    return {
      partition_mode: values.partition_mode || 'none',
      count: typeof partitions.count === 'number' ? partitions.count : null,
      selected_bay_index: selectedIndex,
      gating: {
        globalsVisible: isElementVisible(controller.globalFrontGroup),
        shelvesVisible: isElementVisible(controller.globalShelvesGroup),
        partitionControlsVisible: isElementVisible(controller.partitionControls),
        baysVisible: isElementVisible(controller.baySection)
      },
      chips: chipInfo,
      a11y: {
        partitionFieldsetTag: fieldset ? fieldset.tagName.toLowerCase() : null,
        partitionLegend: legend ? collapseWhitespace(legend.textContent) : '',
        radioLabels: gatherPartitionRadioLabels(),
        liveRegion: liveRegionData,
        chipTabStops: chipInfo.map(function (chip) {
          return chip.tabIndex;
        })
      },
      baySnapshot: {
        total: bays.length,
        selectedIndex: selectedIndex,
        selected: cloneBayForTest(bays[selectedIndex]),
        template: cloneBayForTest(controller.bayTemplate),
        double: collectDoubleDoorState(controller.bayController)
      },
      announcement: testSupport.lastLiveRegion || window.__AICABINETS_LAST_LIVE_REGION__ || ''
    };
  }

  function whenReady(callback) {
    if (controller) {
      try {
        return Promise.resolve(callback(controller));
      } catch (error) {
        return Promise.reject(error);
      }
    }

    if (testSupport.readyPromise) {
      return testSupport.readyPromise.then(function () {
        return callback(controller);
      });
    }

    return Promise.reject(new Error('Controller not initialized'));
  }

  function buildTestApi() {
    return {
      ready: function ready() {
        if (!testSupport.readyPromise) {
          return Promise.resolve(collectState());
        }
        return testSupport.readyPromise.then(function () {
          return collectState();
        });
      },
      setPartitionMode: function setPartitionMode(mode) {
        return whenReady(function (formController) {
          formController.setPartitionMode(mode);
          return collectState();
        });
      },
      setTopCount: function setTopCount(value) {
        return whenReady(function (formController) {
          var numeric = Math.max(0, Math.round(Number(value) || 0));
          formController.applyIntegerValue('partitions_count', numeric);
          if (formController.inputs && formController.inputs.partitions_count) {
            formController.inputs.partitions_count.value = String(numeric);
          }
          formController.refreshBaySummary();
          formController.updateInsertButtonState();
          return collectState();
        });
      },
      setNestedCount: function setNestedCount(value) {
        return whenReady(function (formController) {
          var numeric = Math.max(0, Math.round(Number(value) || 0));
          var index = formController.selectedBayIndex != null ? formController.selectedBayIndex : 0;
          formController.handleBaySubpartitionChange(index, numeric);
          return collectState();
        });
      },
      clickBay: function clickBay(index) {
        return whenReady(function (formController) {
          if (formController.bayController) {
            formController.bayController.setSelectedIndex(Number(index) || 0, {
              emit: true,
              focus: true,
              announce: true
            });
          }
          return collectState();
        });
      },
      toggleBayEditor: function toggleBayEditor(mode) {
        return whenReady(function (formController) {
          var index = formController.selectedBayIndex != null ? formController.selectedBayIndex : 0;
          formController.handleBayModeChange(index, mode);
          return collectState();
        });
      },
      requestDoubleValidity: function requestDoubleValidity() {
        return whenReady(function (formController) {
          var index = formController.selectedBayIndex != null ? formController.selectedBayIndex : 0;
          var wait =
            testSupport.enabled && typeof testSupport.waitForDoubleValidity === 'function'
              ? testSupport.waitForDoubleValidity(index)
              : Promise.resolve();
          formController.handleRequestBayValidity(index);
          return wait.then(function () {
            return new Promise(function (resolve) {
              if (typeof window.requestAnimationFrame === 'function') {
                window.requestAnimationFrame(function () {
                  resolve(collectState());
                });
              } else {
                window.setTimeout(function () {
                  resolve(collectState());
                }, 0);
              }
            });
          });
        });
      },
      getState: function getState() {
        return collectState();
      },
      lastLiveRegion: function lastLiveRegion() {
        return testSupport.lastLiveRegion || window.__AICABINETS_LAST_LIVE_REGION__ || '';
      }
    };
  }

  function BayController(options) {
    options = options || {};

    this.root = options.root || null;
    this.onSelect = typeof options.onSelect === 'function' ? options.onSelect : function () {};
    this.onShelfChange =
      typeof options.onShelfChange === 'function' ? options.onShelfChange : function () {};
    this.onDoorChange =
      typeof options.onDoorChange === 'function' ? options.onDoorChange : function () {};
    this.onModeChange =
      typeof options.onModeChange === 'function' ? options.onModeChange : function () {};
    this.onSubpartitionChange =
      typeof options.onSubpartitionChange === 'function'
        ? options.onSubpartitionChange
        : function () {};
    this.onApplyToAll =
      typeof options.onApplyToAll === 'function' ? options.onApplyToAll : function () {};
    this.onCopyLeftToRight =
      typeof options.onCopyLeftToRight === 'function' ? options.onCopyLeftToRight : function () {};
    this.onRequestValidity =
      typeof options.onRequestValidity === 'function' ? options.onRequestValidity : function () {};
    this.announceCallback =
      typeof options.onAnnounce === 'function' ? options.onAnnounce : function () {};
    this.translate = typeof options.translate === 'function' ? options.translate : translate;
    if (typeof options.formatMillimeters === 'function') {
      this.formatMillimeters = options.formatMillimeters;
    } else {
      this.formatMillimeters = function (value) {
        var numeric = Number(value);
        if (!isFinite(numeric)) {
          return '';
        }
        return numeric.toFixed(0) + ' mm';
      };
    }

    this.selectedIndex = 0;
    this.bays = [];
    this.chipButtons = [];
    this.focusedIndex = 0;
    this.lastRenderedBayCount = 0;
    this.doubleValidity = [];
    this.lastDoubleEligibility = [];
    this.template = cloneBay(null);
    this.shelfLock = false;
    this.doorLock = false;
    this.buttonsDisabled = false;

    this.cacheElements();
    if (this.root) {
      this.initializeText();
      this.bindEvents();
    }
  }

  BayController.prototype.cacheElements = function cacheElements() {
    if (!this.root) {
      this.selector = null;
      this.chipsContainer = null;
      this.shelfLabel = null;
      this.stepper = null;
      this.decreaseButton = null;
      this.increaseButton = null;
      this.shelfInput = null;
      this.modeFieldset = null;
      this.modeInputs = [];
      this.modeLegend = null;
      this.modeLabelFronts = null;
      this.modeLabelSubpartitions = null;
      this.frontsEditor = null;
      this.subpartitionsEditor = null;
      this.subpartitionLabel = null;
      this.subpartitionStepper = null;
      this.subpartitionDecreaseButton = null;
      this.subpartitionIncreaseButton = null;
      this.subpartitionInput = null;
      this.doorFieldset = null;
      this.doorLegend = null;
      this.doorInputs = [];
      this.doubleDoorInput = null;
      this.hint = null;
      this.applyAllButton = null;
      this.copyButton = null;
      this.actionsContainer = null;
      this.subpartitionLock = false;
      return;
    }

    this.selector = this.root.querySelector('[data-role="bay-selector"]');
    this.chipsContainer = this.root.querySelector('[data-role="bay-chips"]');
    this.sectionTitle = this.root.closest('[data-role="bay-section"]')
      ? this.root.closest('[data-role="bay-section"]').querySelector('[data-role="bay-section-title"]')
      : null;
    this.shelfRow = this.root.querySelector('[data-role="bay-shelf-row"]');
    this.shelfLabel = this.root.querySelector('[data-role="bay-shelf-label"]');
    this.stepper = this.root.querySelector('[data-role="bay-stepper"]');
    this.decreaseButton = this.root.querySelector('[data-role="bay-stepper-decrease"]');
    this.increaseButton = this.root.querySelector('[data-role="bay-stepper-increase"]');
    this.shelfInput = this.root.querySelector('[data-role="bay-shelf-input"]');
    this.modeFieldset = this.root.querySelector('[data-role="bay-mode-fieldset"]');
    var modeOptions = this.root.querySelectorAll('[data-role="bay-mode-option"]');
    this.modeInputs = Array.prototype.slice.call(modeOptions || []);
    this.modeLegend = this.root.querySelector('[data-role="bay-mode-legend"]');
    this.modeLabelFronts = this.root.querySelector('[data-role="bay-mode-label-fronts"]');
    this.modeLabelSubpartitions = this.root.querySelector('[data-role="bay-mode-label-subpartitions"]');
    this.frontsEditor = this.root.querySelector('[data-role="bay-fronts-editor"]');
    this.subpartitionsEditor = this.root.querySelector('[data-role="bay-subpartitions-editor"]');
    this.subpartitionLabel = this.root.querySelector('[data-role="bay-subpartition-label"]');
    this.subpartitionStepper = this.root.querySelector('[data-role="bay-subpartition-stepper"]');
    this.subpartitionDecreaseButton = this.root.querySelector('[data-role="bay-subpartition-decrease"]');
    this.subpartitionIncreaseButton = this.root.querySelector('[data-role="bay-subpartition-increase"]');
    this.subpartitionInput = this.root.querySelector('[data-role="bay-subpartition-input"]');
    this.doorFieldset = this.root.querySelector('[data-role="bay-door-fieldset"]');
    this.doorLegend = this.root.querySelector('[data-role="bay-door-legend"]');
    var doorOptions = this.root.querySelectorAll('[data-role="bay-door-option"]');
    this.doorInputs = Array.prototype.slice.call(doorOptions || []);
    this.doubleDoorInput = this.doorInputs.find(function (input) {
      return input && input.value === 'doors_double';
    }) || null;
    this.doorLabelNone = this.root.querySelector('[data-role="bay-door-label-none"]');
    this.doorLabelLeft = this.root.querySelector('[data-role="bay-door-label-left"]');
    this.doorLabelRight = this.root.querySelector('[data-role="bay-door-label-right"]');
    this.doorLabelDouble = this.root.querySelector('[data-role="bay-door-label-double"]');
    this.hint = this.root.querySelector('[data-role="bay-double-hint"]');
    this.applyAllButton = this.root.querySelector('[data-role="bay-apply-all"]');
    this.copyButton = this.root.querySelector('[data-role="bay-copy-lr"]');
    this.actionsContainer = this.root.querySelector('[data-role="bay-actions"]');
    this.subpartitionLock = false;
  };

  BayController.prototype.initializeText = function initializeText() {
    if (!this.root) {
      return;
    }

    if (this.sectionTitle) {
      this.sectionTitle.textContent = this.translate('bay_section_title');
    }
    if (this.chipsContainer) {
      this.chipsContainer.setAttribute('aria-label', this.translate('bay_selector_label'));
    }
    if (this.shelfLabel) {
      this.shelfLabel.textContent = this.translate('shelf_stepper_label');
    }
    if (this.decreaseButton) {
      this.decreaseButton.setAttribute('aria-label', this.translate('shelf_stepper_decrease'));
      this.decreaseButton.textContent = '−';
    }
    if (this.increaseButton) {
      this.increaseButton.setAttribute('aria-label', this.translate('shelf_stepper_increase'));
      this.increaseButton.textContent = '+';
    }
    if (this.shelfInput) {
      this.shelfInput.setAttribute('aria-label', this.translate('shelf_input_aria'));
    }
    if (this.modeLegend) {
      this.modeLegend.textContent = this.translate('bay_editor_group_label');
    }
    if (this.modeLabelFronts) {
      this.modeLabelFronts.textContent = this.translate('bay_editor_option_fronts');
    }
    if (this.modeLabelSubpartitions) {
      this.modeLabelSubpartitions.textContent = this.translate('bay_editor_option_subpartitions');
    }
    if (this.subpartitionLabel) {
      this.subpartitionLabel.textContent = this.translate('subpartition_stepper_label');
    }
    if (this.subpartitionDecreaseButton) {
      this.subpartitionDecreaseButton.setAttribute(
        'aria-label',
        this.translate('subpartition_stepper_decrease')
      );
      this.subpartitionDecreaseButton.textContent = '−';
    }
    if (this.subpartitionIncreaseButton) {
      this.subpartitionIncreaseButton.setAttribute(
        'aria-label',
        this.translate('subpartition_stepper_increase')
      );
      this.subpartitionIncreaseButton.textContent = '+';
    }
    if (this.subpartitionInput) {
      this.subpartitionInput.setAttribute('aria-label', this.translate('subpartition_input_aria'));
    }
    if (this.doorLegend) {
      this.doorLegend.textContent = this.translate('door_mode_group_label');
    }
    if (this.doorLabelNone) {
      this.doorLabelNone.textContent = this.translate('door_mode_none');
    }
    if (this.doorLabelLeft) {
      this.doorLabelLeft.textContent = this.translate('door_mode_left');
    }
    if (this.doorLabelRight) {
      this.doorLabelRight.textContent = this.translate('door_mode_right');
    }
    if (this.doorLabelDouble) {
      this.doorLabelDouble.textContent = this.translate('door_mode_double');
    }
    if (this.applyAllButton) {
      this.applyAllButton.textContent = this.translate('apply_to_all_label');
    }
    if (this.copyButton) {
      this.copyButton.textContent = this.translate('copy_left_to_right_label');
    }
  };

  BayController.prototype.bindEvents = function bindEvents() {
    var self = this;
    if (this.decreaseButton) {
      this.decreaseButton.addEventListener('click', function () {
        self.adjustShelf(-1);
      });
    }
    if (this.increaseButton) {
      this.increaseButton.addEventListener('click', function () {
        self.adjustShelf(1);
      });
    }
    if (this.shelfInput) {
      this.shelfInput.addEventListener('input', function () {
        self.handleShelfInput();
      });
      this.shelfInput.addEventListener('blur', function () {
        self.handleShelfBlur();
      });
    }
    this.doorInputs.forEach(function (input) {
      input.addEventListener('change', function () {
        self.handleDoorChange(input.value);
      });
    });
    this.modeInputs.forEach(function (input) {
      if (!input) {
        return;
      }
      input.addEventListener('change', function () {
        self.handleModeChange(input.value);
      });
    });
    this.bindSegmentedInputKeys(this.modeInputs);
    this.bindSegmentedInputKeys(this.doorInputs);
    if (this.subpartitionDecreaseButton) {
      this.subpartitionDecreaseButton.addEventListener('click', function () {
        self.adjustSubpartition(-1);
      });
    }
    if (this.subpartitionIncreaseButton) {
      this.subpartitionIncreaseButton.addEventListener('click', function () {
        self.adjustSubpartition(1);
      });
    }
    if (this.subpartitionInput) {
      this.subpartitionInput.addEventListener('input', function () {
        self.handleSubpartitionInput();
      });
      this.subpartitionInput.addEventListener('blur', function () {
        self.handleSubpartitionBlur();
      });
    }
    if (this.applyAllButton) {
      this.applyAllButton.addEventListener('click', function () {
        self.onApplyToAll(self.selectedIndex);
      });
    }
    if (this.copyButton) {
      this.copyButton.addEventListener('click', function () {
        self.onCopyLeftToRight();
      });
    }

    if (this.chipsContainer) {
      this.chipsContainer.addEventListener('click', function (event) {
        self.handleChipContainerClick(event);
      });
      this.chipsContainer.addEventListener('keydown', function (event) {
        self.handleChipContainerKeyDown(event);
      });
    }
  };

  BayController.prototype.bindSegmentedInputKeys = function bindSegmentedInputKeys(inputs) {
    bindSegmentedGroupKeyHandlers(inputs);
  };

  BayController.prototype.renderChips = function renderChips() {
    if (!this.chipsContainer) {
      return;
    }

    var container = this.chipsContainer;
    var desiredCount = this.bays.length;
    if (desiredCount < 1) {
      desiredCount = 1;
    }

    var existing = this.chipButtons ? this.chipButtons.slice() : [];
    var activeBefore = document.activeElement;
    var hadFocusInside = activeBefore && container.contains(activeBefore);

    var newButtons = [];

    for (var index = 0; index < desiredCount; index += 1) {
      var button = existing[index];
      if (!button || button.parentElement !== container) {
        button = document.createElement('button');
        button.type = 'button';
        button.className = 'bay-chip';
      }

      if (button.getAttribute('role') !== 'tab') {
        button.setAttribute('role', 'tab');
      }

      var referenceNode = container.children[index] || null;
      if (referenceNode !== button) {
        container.insertBefore(button, referenceNode);
      }

      var label = this.translate('bay_chip_label', { index: index + 1 });
      if (button.textContent !== label) {
        button.textContent = label;
      }
      button.setAttribute('data-index', String(index));

      newButtons.push(button);
    }

    for (var removeIndex = existing.length - 1; removeIndex >= desiredCount; removeIndex -= 1) {
      var extra = existing[removeIndex];
      if (extra && extra.parentElement === container) {
        container.removeChild(extra);
      }
    }

    while (container.children.length > desiredCount) {
      var trailing = container.lastElementChild;
      if (!trailing) {
        break;
      }
      container.removeChild(trailing);
    }

    this.chipButtons = newButtons;
    this.selectedIndex = clampSelectedIndex(this.selectedIndex, desiredCount);
    this.focusedIndex = clampSelectedIndex(
      this.focusedIndex != null ? this.focusedIndex : this.selectedIndex,
      desiredCount
    );

    var lostFocus =
      hadFocusInside && (!activeBefore || !container.contains(activeBefore) || !document.contains(activeBefore));

    this.refreshChipAttributes({ focus: lostFocus && !this.buttonsDisabled });
    this.updateActionsVisibility();
    this.lastRenderedBayCount = desiredCount;
  };

  BayController.prototype.refreshChipAttributes = function refreshChipAttributes(options) {
    if (!this.chipButtons || !this.chipButtons.length) {
      return;
    }

    var clampedFocus = clampSelectedIndex(
      this.focusedIndex != null ? this.focusedIndex : 0,
      this.chipButtons.length
    );
    this.focusedIndex = clampedFocus;

    for (var index = 0; index < this.chipButtons.length; index += 1) {
      var button = this.chipButtons[index];
      if (!button) {
        continue;
      }
      var isSelected = index === this.selectedIndex;
      button.setAttribute('aria-selected', isSelected ? 'true' : 'false');
      button.tabIndex = index === clampedFocus ? 0 : -1;
      if (this.buttonsDisabled) {
        button.setAttribute('aria-disabled', 'true');
      } else {
        button.removeAttribute('aria-disabled');
      }
    }

    if (
      options &&
      options.focus &&
      !this.buttonsDisabled &&
      this.chipButtons[clampedFocus] &&
      typeof this.chipButtons[clampedFocus].focus === 'function'
    ) {
      this.chipButtons[clampedFocus].focus();
    }
  };

  BayController.prototype.setFocusIndex = function setFocusIndex(index, options) {
    if (!this.chipButtons || !this.chipButtons.length) {
      return;
    }

    var clamped = clampSelectedIndex(index, this.chipButtons.length);
    this.focusedIndex = clamped;
    this.refreshChipAttributes({ focus: options && options.focus });
  };

  BayController.prototype.handleChipContainerClick = function handleChipContainerClick(event) {
    if (!event) {
      return;
    }

    if (this.buttonsDisabled) {
      return;
    }

    var target = event.target && event.target.closest('[data-index]');
    var index = this.resolveChipIndex(target);
    if (index == null) {
      return;
    }

    event.preventDefault();
    this.setFocusIndex(index, { focus: true });
    this.setSelectedIndex(index, { emit: true, focus: true });
  };

  BayController.prototype.handleChipContainerKeyDown = function handleChipContainerKeyDown(event) {
    if (!event) {
      return;
    }

    var target = event.target && event.target.closest('[data-index]');
    var index = this.resolveChipIndex(target);
    if (index == null) {
      return;
    }

    this.handleChipKeyDown(event, index);
  };

  BayController.prototype.resolveChipIndex = function resolveChipIndex(element) {
    var current = element;
    while (current && current !== this.chipsContainer) {
      if (
        current.tagName &&
        current.tagName.toUpperCase() === 'BUTTON' &&
        current.hasAttribute('data-index') &&
        current.getAttribute('data-index') !== null
      ) {
        var value = parseInt(current.getAttribute('data-index'), 10);
        if (isFinite(value)) {
          return value;
        }
      }
      current = current.parentElement;
    }

    return null;
  };

  BayController.prototype.handleChipKeyDown = function handleChipKeyDown(event, index) {
    if (!event) {
      return;
    }

    if (this.buttonsDisabled) {
      return;
    }

    var key = event.key || event.keyCode;
    var length = this.chipButtons ? this.chipButtons.length : 0;
    if (!length) {
      return;
    }

    var handled = false;
    var nextIndex = null;
    if (
      key === 'ArrowRight' ||
      key === 'Right' ||
      key === 39 ||
      key === 'ArrowDown' ||
      key === 'Down' ||
      key === 40
    ) {
      nextIndex = (index + 1 + length) % length;
      handled = true;
    } else if (
      key === 'ArrowLeft' ||
      key === 'Left' ||
      key === 37 ||
      key === 'ArrowUp' ||
      key === 'Up' ||
      key === 38
    ) {
      nextIndex = (index - 1 + length) % length;
      handled = true;
    } else if (key === 'Home' || key === 36) {
      nextIndex = 0;
      handled = true;
    } else if (key === 'End' || key === 35) {
      nextIndex = length - 1;
      handled = true;
    } else if (
      key === ' ' ||
      key === 'Spacebar' ||
      key === 32 ||
      key === 'Enter' ||
      key === 13
    ) {
      this.setSelectedIndex(index, { emit: true, focus: true });
      handled = true;
    }

    if (nextIndex != null) {
      this.setSelectedIndex(nextIndex, { emit: true, focus: true });
    }

    if (handled) {
      event.preventDefault();
      event.stopPropagation();
    }
  };

  BayController.prototype.setSelectedIndex = function setSelectedIndex(index, options) {
    if (!this.bays || !this.bays.length) {
      return;
    }

    var clamped = clampSelectedIndex(index, this.bays.length);

    options = options || {};
    var previous = this.selectedIndex;
    var selectionChanged = clamped !== previous;
    var shouldAnnounce = options.announce !== false;
    this.selectedIndex = clamped;

    this.focusedIndex = clamped;
    this.refreshChipAttributes({ focus: options.focus });

    this.updateShelfControls();
    this.updateDoorControls({
      announce: shouldAnnounce,
      force: options.forceAnnounce === true || (shouldAnnounce && selectionChanged)
    });
    this.updateModeControls();
    this.updateSubpartitionControls();
    this.applyModeSpecificDisabling();
    this.updateActionsVisibility();

    if ((shouldAnnounce && selectionChanged) || options.forceAnnounce) {
      this.announce(
        this.translate('bay_selection_status', { index: clamped + 1, total: this.bays.length }),
        { immediate: true }
      );
    }

    if (options.emit && clamped !== previous) {
      this.onSelect(clamped);
    }

    if (options.requestValidity !== false) {
      this.requestValidity();
    }
  };

  BayController.prototype.updateShelfControls = function updateShelfControls() {
    if (!this.shelfInput) {
      return;
    }

    var bay = this.bays[this.selectedIndex] || this.template;
    var fronts = bay.fronts_shelves_state || {};
    var value = typeof fronts.shelf_count === 'number' ? fronts.shelf_count : 0;
    this.shelfLock = true;
    this.shelfInput.value = String(value);
    this.shelfLock = false;
  };

  BayController.prototype.updateDoorControls = function updateDoorControls(options) {
    options = options || {};
    var bay = this.bays[this.selectedIndex] || this.template;
    var fronts = bay.fronts_shelves_state || {};
    var mode = fronts.door_mode;
    if (mode == null || mode === '') {
      mode = 'none';
    }

    this.doorLock = true;
    this.doorInputs.forEach(function (input) {
      if (!input) {
        return;
      }
      input.checked = input.value === mode;
    });
    this.doorLock = false;
    this.applyDoubleValidityState(options);
  };

  BayController.prototype.setBays = function setBays(bays, options) {
    options = options || {};
    this.bays = Array.isArray(bays) ? bays.slice() : [];
    this.template = this.bays.length ? cloneBay(this.bays[0]) : cloneBay(null);
    if (this.doubleValidity.length > this.bays.length) {
      this.doubleValidity.length = this.bays.length;
    }
    if (this.lastDoubleEligibility.length > this.bays.length) {
      this.lastDoubleEligibility.length = this.bays.length;
    }
    var desiredIndex = options.selectedIndex != null ? options.selectedIndex : this.selectedIndex;
    desiredIndex = clampSelectedIndex(desiredIndex, this.bays.length);
    this.selectedIndex = desiredIndex;
    this.focusedIndex = clampSelectedIndex(
      this.focusedIndex != null ? this.focusedIndex : desiredIndex,
      this.bays.length || 1
    );
    this.renderChips();
    var shouldAnnounce = options.announce === true;
    this.setSelectedIndex(desiredIndex, {
      emit: options.emit === true,
      focus: options.focus === true,
      announce: shouldAnnounce,
      requestValidity: options.requestValidity !== false
    });
  };

  // cloneBay defined earlier

  BayController.prototype.setBayValue = function setBayValue(index, bay) {
    if (index < 0 || index >= this.bays.length) {
      return;
    }

    this.bays[index] = cloneBay(bay);
    if (index === this.selectedIndex) {
      this.updateShelfControls();
      this.updateDoorControls({ announce: false });
      this.updateSubpartitionControls();
      this.updateModeControls();
      this.applyModeSpecificDisabling();
    }
  };

  BayController.prototype.adjustShelf = function adjustShelf(delta) {
    var bay = this.bays[this.selectedIndex] || { shelf_count: 0 };
    var current = typeof bay.shelf_count === 'number' ? bay.shelf_count : 0;
    var next = Math.max(0, current + delta);
    if (next === current) {
      return;
    }

    if (this.shelfInput) {
      this.shelfInput.value = String(next);
    }
    this.onShelfChange(this.selectedIndex, next);
    this.announce(
      this.translate('shelves_value_status', {
        count: next
      })
    );
  };

  BayController.prototype.handleShelfInput = function handleShelfInput() {
    if (this.shelfLock) {
      return;
    }

    if (!this.shelfInput) {
      return;
    }

    var value = parseInt(this.shelfInput.value, 10);
    if (!isFinite(value) || value < 0) {
      return;
    }
    this.onShelfChange(this.selectedIndex, value);
  };

  BayController.prototype.handleShelfBlur = function handleShelfBlur() {
    if (!this.shelfInput) {
      return;
    }

    var value = parseInt(this.shelfInput.value, 10);
    if (!isFinite(value) || value < 0) {
      value = 0;
    }
    this.shelfInput.value = String(value);
    this.onShelfChange(this.selectedIndex, value);
  };

  BayController.prototype.handleModeChange = function handleModeChange(value) {
    var normalized = normalizeBayMode(value);
    var bay = this.bays[this.selectedIndex];
    if (!bay) {
      return;
    }

    if (bay.mode === normalized) {
      return;
    }

    bay.mode = normalized;
    this.updateModeControls();
    this.applyModeSpecificDisabling();
    this.updateActionsVisibility();
    this.ensureActiveEditorFocus(normalized);
    var editorStatusKey =
      normalized === 'subpartitions' ? 'bay_editor_status_subpartitions' : 'bay_editor_status_fronts';
    this.announce(this.translate(editorStatusKey), { immediate: true });
    this.onModeChange(this.selectedIndex, normalized);
    if (normalized === 'fronts_shelves') {
      this.requestValidity();
    }
  };

  BayController.prototype.adjustSubpartition = function adjustSubpartition(delta) {
    if (!this.subpartitionInput) {
      return;
    }

    var bay = this.bays[this.selectedIndex] || this.template;
    var state = bay.subpartitions_state || {};
    var current = typeof state.count === 'number' ? state.count : 0;
    var next = Math.max(0, current + delta);
    if (next === current) {
      return;
    }

    this.subpartitionInput.value = String(next);
    this.onSubpartitionChange(this.selectedIndex, next);
  };

  BayController.prototype.handleSubpartitionInput = function handleSubpartitionInput() {
    if (this.subpartitionLock) {
      return;
    }
    if (!this.subpartitionInput) {
      return;
    }

    var value = parseInt(this.subpartitionInput.value, 10);
    if (!isFinite(value) || value < 0) {
      return;
    }
    this.onSubpartitionChange(this.selectedIndex, value);
  };

  BayController.prototype.handleSubpartitionBlur = function handleSubpartitionBlur() {
    if (!this.subpartitionInput) {
      return;
    }

    var value = parseInt(this.subpartitionInput.value, 10);
    if (!isFinite(value) || value < 0) {
      value = 0;
    }
    this.subpartitionInput.value = String(value);
    this.onSubpartitionChange(this.selectedIndex, value);
  };

  BayController.prototype.handleDoorChange = function handleDoorChange(value) {
    if (this.doorLock) {
      return;
    }

    this.onDoorChange(this.selectedIndex, value);
    var statusKey;
    switch (value) {
      case 'doors_left':
        statusKey = 'door_mode_status_left';
        break;
      case 'doors_right':
        statusKey = 'door_mode_status_right';
        break;
      case 'doors_double':
        statusKey = 'door_mode_status_double';
        break;
      default:
        statusKey = 'door_mode_status_none';
        break;
    }
    this.announce(this.translate(statusKey));
  };

  BayController.prototype.updateModeControls = function updateModeControls() {
    var bay = this.bays[this.selectedIndex] || this.template;
    var mode = normalizeBayMode(bay.mode);
    if (this.modeInputs && this.modeInputs.length) {
      this.modeInputs.forEach(function (input) {
        if (!input) {
          return;
        }
        input.checked = input.value === mode;
      });
    }
    this.updateEditorVisibility(mode);
  };

  BayController.prototype.updateSubpartitionControls = function updateSubpartitionControls() {
    if (!this.subpartitionInput) {
      return;
    }

    var bay = this.bays[this.selectedIndex] || this.template;
    var state = bay.subpartitions_state || {};
    var value = typeof state.count === 'number' ? state.count : 0;
    this.subpartitionLock = true;
    this.subpartitionInput.value = String(value);
    this.subpartitionLock = false;
  };

  BayController.prototype.updateEditorVisibility = function updateEditorVisibility(mode) {
    var resolved = mode || normalizeBayMode((this.bays[this.selectedIndex] || this.template).mode);
    if (this.frontsEditor) {
      var hideFronts = resolved !== 'fronts_shelves';
      this.frontsEditor.classList.toggle('is-hidden', hideFronts);
      this.frontsEditor.hidden = hideFronts;
      setElementInert(this.frontsEditor, hideFronts);
    }
    if (this.subpartitionsEditor) {
      var hideSub = resolved !== 'subpartitions';
      this.subpartitionsEditor.classList.toggle('is-hidden', hideSub);
      this.subpartitionsEditor.hidden = hideSub;
      setElementInert(this.subpartitionsEditor, hideSub);
    }
    this.applyModeSpecificDisabling();
    this.ensureActiveEditorFocus(resolved);
  };

  BayController.prototype.focusFrontEditorControls = function focusFrontEditorControls() {
    if (this.shelfInput && !this.shelfInput.disabled && typeof this.shelfInput.focus === 'function') {
      this.shelfInput.focus();
      return true;
    }

    for (var index = 0; index < this.doorInputs.length; index += 1) {
      var doorInput = this.doorInputs[index];
      if (doorInput && !doorInput.disabled && typeof doorInput.focus === 'function') {
        doorInput.focus();
        return true;
      }
    }

    if (this.applyAllButton && !this.applyAllButton.disabled && typeof this.applyAllButton.focus === 'function') {
      this.applyAllButton.focus();
      return true;
    }

    if (
      this.copyButton &&
      !this.copyButton.disabled &&
      !this.copyButton.hidden &&
      typeof this.copyButton.focus === 'function'
    ) {
      this.copyButton.focus();
      return true;
    }

    return false;
  };

  BayController.prototype.focusSubpartitionEditorControls = function focusSubpartitionEditorControls() {
    if (
      this.subpartitionInput &&
      !this.subpartitionInput.disabled &&
      typeof this.subpartitionInput.focus === 'function'
    ) {
      this.subpartitionInput.focus();
      return true;
    }

    if (
      this.subpartitionDecreaseButton &&
      !this.subpartitionDecreaseButton.disabled &&
      typeof this.subpartitionDecreaseButton.focus === 'function'
    ) {
      this.subpartitionDecreaseButton.focus();
      return true;
    }

    if (
      this.subpartitionIncreaseButton &&
      !this.subpartitionIncreaseButton.disabled &&
      typeof this.subpartitionIncreaseButton.focus === 'function'
    ) {
      this.subpartitionIncreaseButton.focus();
      return true;
    }

    return false;
  };

  BayController.prototype.ensureActiveEditorFocus = function ensureActiveEditorFocus(mode, options) {
    var resolved = normalizeBayMode(mode || (this.bays[this.selectedIndex] || this.template).mode);
    var activeElement = document.activeElement;
    var focusInsideFronts = this.frontsEditor && activeElement && this.frontsEditor.contains(activeElement);
    var focusInsideSub = this.subpartitionsEditor && activeElement && this.subpartitionsEditor.contains(activeElement);

    var forceFocus = options && options.force;
    var needsFocus = forceFocus;

    if (!needsFocus && focusInsideFronts && this.frontsEditor && this.frontsEditor.hidden) {
      needsFocus = true;
    }
    if (!needsFocus && focusInsideSub && this.subpartitionsEditor && this.subpartitionsEditor.hidden) {
      needsFocus = true;
    }

    if (!needsFocus) {
      return;
    }

    var moved = false;
    if (resolved === 'subpartitions') {
      moved = this.focusSubpartitionEditorControls();
    } else {
      moved = this.focusFrontEditorControls();
    }

    if (!moved && this.chipButtons && this.chipButtons[this.selectedIndex]) {
      var button = this.chipButtons[this.selectedIndex];
      if (button && typeof button.focus === 'function') {
        button.focus();
      }
    }
  };

  function coerceNumeric(value) {
    var numeric = Number(value);
    return isFinite(numeric) ? numeric : null;
  }

  function sanitizeReason(reason) {
    if (!reason) {
      return null;
    }
    var text = collapseWhitespace(reason);
    return text || null;
  }

  BayController.prototype.setDoubleDoorFocusability = function setDoubleDoorFocusability(
    enabled
  ) {
    var input = this.doubleDoorInput || null;
    if (!input) {
      return;
    }

    if (!Object.prototype.hasOwnProperty.call(input, '__aicOriginalTabIndex')) {
      input.__aicOriginalTabIndex = input.hasAttribute('tabindex')
        ? input.getAttribute('tabindex')
        : null;
    }

    if (enabled) {
      var original = input.__aicOriginalTabIndex;
      if (original == null || original === '') {
        input.removeAttribute('tabindex');
      } else {
        input.setAttribute('tabindex', original);
      }
      if (typeof input.tabIndex === 'number' && input.tabIndex < 0) {
        input.tabIndex = 0;
      }
      return;
    }

    input.setAttribute('tabindex', '-1');
    input.tabIndex = -1;
  };

  BayController.prototype.setDoubleDoorDisabledState = function setDoubleDoorDisabledState(
    disabled
  ) {
    if (!this.doubleDoorInput) {
      return;
    }

    var isDisabled = disabled === true;
    this.doubleDoorInput.disabled = isDisabled;
    if (isDisabled) {
      this.doubleDoorInput.setAttribute('aria-disabled', 'true');
    } else {
      this.doubleDoorInput.removeAttribute('aria-disabled');
    }
  };

  BayController.prototype.applyDoubleValidityState = function applyDoubleValidityState(options) {
    if (!this.doubleDoorInput) {
      return;
    }

    options = options || {};
    var shouldAnnounce = options.announce !== false;
    var force = options.force === true;

    var bay = this.bays[this.selectedIndex] || this.template;
    var mode = normalizeBayMode(bay.mode);
    var frontDisabled = this.buttonsDisabled || mode !== 'fronts_shelves';

    if (frontDisabled) {
      this.setDoubleDoorDisabledState(true);
      this.setDoubleDoorFocusability(false);
      this.clearHint();
      this.lastDoubleEligibility[this.selectedIndex] = {
        allowed: false,
        key: 'front-disabled'
      };
      return;
    }

    var validity = this.doubleValidity[this.selectedIndex] || null;
    var allowed = !validity || validity.allowed === true;
    var reason = sanitizeReason(validity && validity.reason);
    var leafWidthMm = validity ? coerceNumeric(validity.leafWidthMm) : null;
    var minLeafWidthMm = validity ? coerceNumeric(validity.minLeafWidthMm) : null;

    var previous = this.lastDoubleEligibility[this.selectedIndex] || { allowed: null, key: null };
    var key = allowed ? 'allowed' : 'disallowed';
    var announcement = null;
    var hintText = null;

    if (allowed) {
      this.setDoubleDoorDisabledState(false);
      this.setDoubleDoorFocusability(true);
      this.clearHint();

      if (minLeafWidthMm != null) {
        key = key + '|min=' + minLeafWidthMm;
        if (shouldAnnounce) {
          var formattedMinAllowed = this.formatMillimeters(minLeafWidthMm);
          announcement = this.translate('door_mode_double_available_due_to_min', {
            min: formattedMinAllowed
          });
        }
      }
    } else {
      this.setDoubleDoorDisabledState(true);
      this.setDoubleDoorFocusability(false);
      var current = this.bays[this.selectedIndex] || {};
      var fronts = current.fronts_shelves_state || {};
      if (fronts.door_mode === 'doors_double') {
        this.handleDoorChange('none');
      }

      if (reason) {
        hintText = reason;
      } else if (minLeafWidthMm != null && leafWidthMm != null) {
        hintText = this.translate('door_mode_double_disabled_due_to_min_hint', {
          leaf: this.formatMillimeters(leafWidthMm),
          min: this.formatMillimeters(minLeafWidthMm)
        });
      } else if (minLeafWidthMm != null) {
        hintText = this.translate('door_mode_double_disabled_due_to_min_threshold', {
          min: this.formatMillimeters(minLeafWidthMm)
        });
      } else {
        hintText = this.translate('door_mode_double_disabled_hint');
      }
      this.showHint(hintText);

      if (minLeafWidthMm != null) {
        key = key + '|min=' + minLeafWidthMm;
      }
      if (leafWidthMm != null) {
        key = key + '|leaf=' + leafWidthMm;
      }
      if (hintText) {
        key = key + '|hint=' + hintText;
      }

      if (shouldAnnounce) {
        if (minLeafWidthMm != null) {
          announcement = this.translate('door_mode_double_disabled_due_to_min_announcement', {
            min: this.formatMillimeters(minLeafWidthMm)
          });
        } else {
          announcement = hintText || this.translate('door_mode_double_disabled_hint');
        }
      }
    }

    var changed =
      force ||
      previous.allowed !== allowed ||
      previous.key !== key;

    if (changed) {
      this.lastDoubleEligibility[this.selectedIndex] = { allowed: allowed, key: key };
      if (shouldAnnounce && announcement) {
        this.announce(announcement, { immediate: false });
      }
    }
  };

  BayController.prototype.applyModeSpecificDisabling = function applyModeSpecificDisabling() {
    var bay = this.bays[this.selectedIndex] || this.template;
    var mode = normalizeBayMode(bay.mode);
    var frontDisabled = this.buttonsDisabled || mode !== 'fronts_shelves';
    var subDisabled = this.buttonsDisabled || mode !== 'subpartitions';
    var self = this;

    if (this.decreaseButton) {
      this.decreaseButton.disabled = frontDisabled;
    }
    if (this.increaseButton) {
      this.increaseButton.disabled = frontDisabled;
    }
    if (this.shelfInput) {
      this.shelfInput.disabled = frontDisabled;
    }
    this.doorInputs.forEach(function (input) {
      if (!input) {
        return;
      }
      if (input === self.doubleDoorInput && !frontDisabled) {
        return;
      }
      input.disabled = frontDisabled;
    });
    if (this.doubleDoorInput) {
      if (frontDisabled) {
        this.setDoubleDoorDisabledState(true);
        this.setDoubleDoorFocusability(false);
        this.clearHint();
      } else {
        this.applyDoubleValidityState({ announce: false, force: true });
      }
    }
    if (this.subpartitionDecreaseButton) {
      this.subpartitionDecreaseButton.disabled = subDisabled;
    }
    if (this.subpartitionIncreaseButton) {
      this.subpartitionIncreaseButton.disabled = subDisabled;
    }
    if (this.subpartitionInput) {
      this.subpartitionInput.disabled = subDisabled;
    }
  };

  BayController.prototype.setDoubleValidity = function setDoubleValidity(index, payload) {
    var numericIndex = typeof index === 'number' && isFinite(index) ? index : Number(index);
    if (!isFinite(numericIndex)) {
      numericIndex = 0;
    }
    var entry = payload && typeof payload === 'object' ? payload : {};
    var normalized = {
      allowed: entry.allowed !== false,
      reason: entry.reason || null,
      leafWidthMm: entry.leaf_width_mm,
      minLeafWidthMm: entry.min_leaf_width_mm
    };
    this.doubleValidity[numericIndex] = normalized;
    if (numericIndex === this.selectedIndex) {
      this.applyDoubleValidityState({ announce: true, force: true });
    }
    if (testSupport.enabled && typeof testSupport.resolveDoubleValidity === 'function') {
      testSupport.resolveDoubleValidity(numericIndex);
    }
  };

  BayController.prototype.showHint = function showHint(message) {
    if (!this.hint) {
      return;
    }
    this.hint.textContent = message;
    this.hint.hidden = !message;
  };

  BayController.prototype.clearHint = function clearHint() {
    if (!this.hint) {
      return;
    }
    this.hint.textContent = '';
    this.hint.hidden = true;
  };

  BayController.prototype.requestValidity = function requestValidity() {
    var bay = this.bays[this.selectedIndex] || this.template;
    if (normalizeBayMode(bay.mode) !== 'fronts_shelves') {
      return;
    }
    this.onRequestValidity(this.selectedIndex);
  };

  BayController.prototype.updateActionsVisibility = function updateActionsVisibility() {
    var bay = this.bays[this.selectedIndex] || this.template;
    var mode = normalizeBayMode(bay.mode);
    var hideActions = mode !== 'fronts_shelves';

    if (this.actionsContainer) {
      this.actionsContainer.classList.toggle('is-hidden', hideActions);
      this.actionsContainer.hidden = hideActions;
    }
    if (this.applyAllButton) {
      this.applyAllButton.disabled = this.buttonsDisabled || hideActions;
    }
    if (this.copyButton) {
      var disableCopy = this.buttonsDisabled || hideActions || this.bays.length < 2;
      this.copyButton.disabled = disableCopy;
      this.copyButton.hidden = hideActions || this.bays.length < 2;
    }
  };

  BayController.prototype.announce = function announce(message, options) {
    if (!message) {
      return;
    }
    if (typeof this.announceCallback === 'function') {
      this.announceCallback(message, options || {});
    }
  };

  BayController.prototype.setButtonsDisabled = function setButtonsDisabled(disabled) {
    this.buttonsDisabled = !!disabled;
    if (this.modeInputs && this.modeInputs.length) {
      this.modeInputs.forEach(function (input) {
        if (input) {
          input.disabled = disabled;
        }
      });
    }
    this.applyModeSpecificDisabling();
    this.updateActionsVisibility();
    this.refreshChipAttributes();
  };

  var MODE_COPY = {
    insert: {
      title: 'Insert Base Cabinet',
      subtitle:
        "Configure cabinet parameters, then choose \u003cstrong\u003eInsert\u003c/strong\u003e when ready.",
      primaryLabel: 'Insert'
    },
    edit: {
      title: 'Edit Base Cabinet',
      subtitle:
        "Update the selected cabinet, then choose \u003cstrong\u003eSave Changes\u003c/strong\u003e when ready.",
      primaryLabel: 'Save Changes'
    }
  };

  var ACK_FIELD_TO_INPUT = {
    width_mm: 'width',
    depth_mm: 'depth',
    height_mm: 'height',
    panel_thickness_mm: 'panel_thickness',
    toe_kick_height_mm: 'toe_kick_height',
    toe_kick_depth_mm: 'toe_kick_depth',
    shelves: 'shelves',
    front: 'front',
    'partitions.count': 'partitions_count',
    'partitions.positions_mm': 'partitions_positions',
    'partitions.mode': 'partitions_mode'
  };

  function defaultLengthSettings() {
    return {
      unit: 'millimeter',
      unit_label: 'mm',
      unit_name: 'millimeters',
      format: 'decimal',
      precision: 0,
      fractional_precision: 3
    };
  }

  function normalizeLengthSettings(settings) {
    var normalized = defaultLengthSettings();
    if (!settings || typeof settings !== 'object') {
      return normalized;
    }

    if (typeof settings.unit === 'string' && UNIT_TO_MM[settings.unit]) {
      normalized.unit = settings.unit;
    }

    if (typeof settings.unit_label === 'string' && settings.unit_label.trim()) {
      normalized.unit_label = settings.unit_label.trim();
    } else if (normalized.unit === 'inch') {
      normalized.unit_label = 'in';
    } else if (normalized.unit === 'foot') {
      normalized.unit_label = 'ft';
    }

    if (typeof settings.unit_name === 'string' && settings.unit_name.trim()) {
      normalized.unit_name = settings.unit_name.trim();
    } else {
      normalized.unit_name = defaultUnitName(normalized.unit);
    }

    if (typeof settings.format === 'string') {
      var lowered = settings.format.toLowerCase();
      if (['architectural', 'fractional', 'decimal', 'engineering'].indexOf(lowered) !== -1) {
        normalized.format = lowered;
      }
    }

    if (typeof settings.precision === 'number' && isFinite(settings.precision)) {
      var precision = Math.max(0, Math.min(6, Math.round(settings.precision)));
      normalized.precision = precision;
    }

    if (
      typeof settings.fractional_precision === 'number' &&
      isFinite(settings.fractional_precision)
    ) {
      var frac = Math.max(0, Math.min(5, Math.round(settings.fractional_precision)));
      normalized.fractional_precision = frac;
    }

    return normalized;
  }

  function defaultUnitName(unit) {
    switch (unit) {
      case 'inch':
        return 'inches';
      case 'foot':
        return 'feet';
      case 'centimeter':
        return 'centimeters';
      case 'meter':
        return 'meters';
      default:
        return 'millimeters';
    }
  }

  function LengthService(settings) {
    this.settings = normalizeLengthSettings(settings);
  }

  LengthService.prototype.updateSettings = function updateSettings(settings) {
    this.settings = normalizeLengthSettings(settings);
  };

  LengthService.prototype.parse = function parse(value) {
    var text = String(value == null ? '' : value);
    text = text.trim();
    if (!text) {
      return { ok: false, error: 'Enter a length.' };
    }

    text = text
      .replace(/[\u2018\u2019\u2032\u00b4]/g, "'")
      .replace(/[\u201c\u201d\u2033]/g, '"')
      .replace(/″/g, '"')
      .replace(/′/g, "'");

    if (/^\s*-/.test(text)) {
      return { ok: false, error: 'Length must be non-negative.' };
    }

    var footValue = parseFootAndInches(text);
    if (footValue != null) {
      if (!isFinite(footValue)) {
        return { ok: false, error: 'Enter a valid length.' };
      }
      return { ok: true, value_mm: footValue };
    }

    var suffix = extractUnitSuffix(text);
    var unit = suffix.unit || this.settings.unit;
    if (!UNIT_TO_MM[unit]) {
      unit = 'millimeter';
    }

    var numberText = suffix.text.trim();
    if (!numberText) {
      numberText = '0';
    }

    var numericValue = parseMixedNumber(numberText);
    if (!isFinite(numericValue)) {
      return { ok: false, error: 'Enter a valid length.' };
    }

    var mmValue = numericValue * UNIT_TO_MM[unit];
    return { ok: true, value_mm: mmValue };
  };

  LengthService.prototype.format = function format(mmValue) {
    if (typeof mmValue !== 'number' || !isFinite(mmValue)) {
      return '';
    }

    var settings = this.settings;
    if (settings.unit === 'inch' && (settings.format === 'fractional' || settings.format === 'architectural')) {
      return formatFractionalInches(mmValue, settings.fractional_precision);
    }

    if (settings.unit === 'inch' && settings.format === 'engineering') {
      var feetValue = mmValue / UNIT_TO_MM.foot;
      return trimDecimal(feetValue, settings.precision) + ' ft';
    }

    var divisor = UNIT_TO_MM[settings.unit] || 1;
    var decimalValue = mmValue / divisor;
    var label = settings.unit === 'inch' ? 'in' : settings.unit_label;
    return trimDecimal(decimalValue, settings.precision) + ' ' + label;
  };

  function parseFootAndInches(input) {
    var normalized = input
      .replace(/[\u2018\u2019\u2032\u00b4]/g, "'")
      .replace(/[\u201c\u201d\u2033]/g, '"')
      .replace(/″/g, '"')
      .replace(/′/g, "'")
      .replace(/\bfeet\b|\bfoot\b|\bft\b/gi, "'")
      .replace(/\binches\b|\binch\b|\bin\b/gi, '"');

    if (normalized.indexOf("'") === -1) {
      return null;
    }

    var parts = normalized.split("'");
    if (!parts.length) {
      return null;
    }

    var feetText = parts[0].trim();
    var remaining = parts.slice(1).join("'").trim();

    var feetValue = 0;
    if (feetText) {
      feetValue = parseMixedNumber(feetText);
      if (!isFinite(feetValue)) {
        return NaN;
      }
    }

    var mmValue = feetValue * UNIT_TO_MM.foot;

    if (!remaining) {
      return mmValue;
    }

    var inchesText = remaining;
    var quoteIndex = inchesText.indexOf('"');
    if (quoteIndex !== -1) {
      var afterQuote = inchesText.slice(quoteIndex + 1).trim();
      if (afterQuote) {
        return NaN;
      }
      inchesText = inchesText.slice(0, quoteIndex).trim();
    }

    if (!inchesText) {
      return mmValue;
    }

    var inchesValue = parseMixedNumber(inchesText);
    if (!isFinite(inchesValue)) {
      return NaN;
    }

    return mmValue + inchesValue * UNIT_TO_MM.inch;
  }

  function extractUnitSuffix(value) {
    var text = value.trim();
    var lower = text.toLowerCase();
    var suffixes = [
      { unit: 'millimeter', labels: ['millimeters', 'millimeter', 'mm'] },
      { unit: 'centimeter', labels: ['centimeters', 'centimeter', 'cm'] },
      { unit: 'meter', labels: ['meters', 'meter', 'm'] },
      { unit: 'inch', labels: ['inches', 'inch', 'in'] },
      { unit: 'foot', labels: ['feet', 'foot', 'ft'] }
    ];

    for (var i = 0; i < suffixes.length; i += 1) {
      var entry = suffixes[i];
      for (var j = 0; j < entry.labels.length; j += 1) {
        var label = entry.labels[j];
        if (lower.endsWith(label)) {
          return {
            unit: entry.unit,
            text: text.slice(0, text.length - label.length)
          };
        }
      }
    }

    if (text.endsWith('"')) {
      return { unit: 'inch', text: text.slice(0, -1) };
    }

    if (text.endsWith("'")) {
      return { unit: 'foot', text: text.slice(0, -1) };
    }

    return { unit: null, text: text };
  }

  function parseMixedNumber(text) {
    var cleaned = text.trim();
    if (!cleaned) {
      return NaN;
    }

    cleaned = cleaned.replace(/\s*-\s*/g, ' ');
    var parts = cleaned.split(/\s+/);
    var index = 0;
    var value = 0;

    if (index < parts.length && isFraction(parts[index])) {
      value += parseFraction(parts[index]);
      index += 1;
      if (index < parts.length) {
        return NaN;
      }
      return value;
    }

    if (index < parts.length) {
      var base = parseFloat(parts[index]);
      if (!isFinite(base)) {
        return NaN;
      }
      value += base;
      index += 1;
    }

    if (index < parts.length) {
      if (isFraction(parts[index])) {
        value += parseFraction(parts[index]);
        index += 1;
      } else {
        return NaN;
      }
    }

    if (index !== parts.length) {
      return NaN;
    }

    return value;
  }

  function isFraction(text) {
    return /^(?:\d+)\s*\/\s*(?:\d+)$/.test(text);
  }

  function parseFraction(text) {
    var match = text.match(/^(\d+)\s*\/\s*(\d+)$/);
    if (!match) {
      return NaN;
    }

    var numerator = parseInt(match[1], 10);
    var denominator = parseInt(match[2], 10);
    if (denominator === 0) {
      return NaN;
    }

    return numerator / denominator;
  }

  function gcd(a, b) {
    while (b) {
      var temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }

  function formatFractionalInches(mmValue, fractionalPrecision) {
    var totalInches = mmValue / UNIT_TO_MM.inch;
    var denominator = Math.pow(2, fractionalPrecision + 1);
    var whole = Math.floor(totalInches + 1e-9);
    var remainder = totalInches - whole;
    var numerator = Math.round(remainder * denominator);

    if (numerator === denominator) {
      whole += 1;
      numerator = 0;
    }

    if (numerator !== 0) {
      var divisor = gcd(numerator, denominator);
      numerator /= divisor;
      denominator /= divisor;
    }

    var parts = [];
    if (whole > 0 || numerator === 0) {
      parts.push(String(whole));
    }

    if (numerator > 0) {
      var fractionText = numerator + '/' + denominator;
      if (whole > 0) {
        parts[parts.length - 1] = parts[parts.length - 1] + ' ' + fractionText;
      } else {
        parts.push(fractionText);
      }
    }

    if (!parts.length) {
      parts.push('0');
    }

    return parts.join('') + '"';
  }

  function trimDecimal(value, precision) {
    var fixed = value.toFixed(precision);
    if (precision === 0) {
      return fixed;
    }

    return fixed.replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1');
  }

  function defaultSelectionInfo() {
    return {
      instancesCount: 0,
      definitionName: null,
      sharesDefinition: false
    };
  }

  function FormController(form) {
    this.form = form;
    this.lengthService = new LengthService();
    this.inputs = {};
    this.errorElements = {};
    this.fieldLabels = {};
    this.fieldErrorMessages = {};
    this.touched = {};
    this.values = {
      lengths: {},
      front: 'empty',
      shelves: 0,
      partition_mode: 'none',
      partitions: {
        mode: 'none',
        count: 0,
        positions_mm: [],
        bays: []
      }
    };
    this.partitionLayoutByMode = { vertical: 'even', horizontal: 'even' };
    this.values.lengths.toe_kick_thickness = null;

    this.isPlacing = false;
    this.cancelPending = false;
    this.dialogRoot = document.querySelector('.dialog');
    this.placingIndicator = document.querySelector('[data-role="placing-indicator"]');
    this.interactiveElements = [];
    this.disabledByPlacement = new Map();
    this.secondaryButton =
      document.querySelector('[data-role="secondary-action"]') ||
      document.querySelector('button[data-action="cancel"]');
    this.secondaryDefaultLabel = 'Cancel';
    this.secondaryPlacementLabel = 'Cancel Placement';
    this.secondaryCloseLabel = 'Close';
    this.secondaryCurrentAction = 'cancel';

    this.unitsNote = form.querySelector('[data-role="units-note"]');
    this.insertButton =
      document.querySelector('[data-role="primary-action"]') ||
      document.querySelector('button[data-action="insert"]');
    this.dialogTitle = document.querySelector('[data-role="dialog-title"]');
    this.dialogSubtitle = document.querySelector('[data-role="dialog-subtitle"]');
    this.scopeSection = form.querySelector('[data-role="scope-section"]');
    this.scopeControls = this.scopeSection
      ? this.scopeSection.querySelector('[data-role="scope-controls"]')
      : null;
    this.scopeInputs = Array.prototype.slice.call(
      form.querySelectorAll('input[name="scope"]')
    );
    this.scopeHint = this.scopeControls
      ? this.scopeControls.querySelector('[data-role="scope-hint"]')
      : null;
    this.scopeNote = this.scopeSection
      ? this.scopeSection.querySelector('[data-role="scope-note"]')
      : null;
    this.globalFrontGroup = form.querySelector('[data-role="global-front-group"]');
    this.globalShelvesGroup = form.querySelector('[data-role="global-shelves-group"]');
    this.partitionModeFieldset = form.querySelector('[data-role="partition-mode-group"]');
    this.partitionModeInputs = Array.prototype.slice.call(
      form.querySelectorAll('input[name="partition_mode"]')
    );
    this.partitionControls = form.querySelector('[data-role="partition-controls"]');
    this.baySection = form.querySelector('[data-role="bay-section"]');
    this.statusRegion = document.querySelector('[data-role="dialog-status"]');
    this.liveAnnouncer = new LiveAnnouncer(this.statusRegion, { delay: 200 });
    if (this.statusRegion) {
      this.statusRegion.setAttribute('aria-label', translate('live_region_title'));
    }
    this.currentUiVisibility = null;
    this.lastSentPartitionMode = null;
    this.lastSentPartitionsLayout = null;
    this.lastSentPartitionsState = null;
    this.bannerElement = document.querySelector('[data-role="form-banner"]');
    this.partitionsEvenField = form.querySelector('[data-partitions-control="even"]');
    this.partitionsPositionsField = form.querySelector('[data-partitions-control="positions"]');
    this.bannerTimer = null;
    this.isSubmitting = false;
    this.mode = 'insert';
    this.scope = 'instance';
    this.scopeDefault = 'instance';
    this.scopeDisplayMode = 'hidden';
    this.selectionInfo = defaultSelectionInfo();
    this.selectionProvided = false;
    this.primaryActionLabel = MODE_COPY.insert.primaryLabel;
    this.placementNotice = '';
    this.selectedBayIndex = 0;
    this.pendingSelectedBayIndex = null;
    this.bayTemplate = cloneBay(null);
    this.lastAnnouncedBayCount = null;

    this.initializeElements();
    this.bindEvents();
    this.setPartitionsLayout('none', {
      notify: false,
      resetValues: false,
      ensureLength: false,
      updateInsertButton: false,
      force: true
    });
    this.setPartitionMode('none', {
      notify: false,
      resetSelection: false,
      restoreLayout: false,
      ensureLength: false,
      updateInsertButton: false,
      announce: false
    });
    this.updateInsertButtonState();
    this.setSecondaryAction('cancel', this.secondaryDefaultLabel);

    this.bayController = new BayController({
      root: form.querySelector('[data-role="bay-controls"]'),
      onSelect: this.handleBaySelection.bind(this),
      onShelfChange: this.handleBayShelfChange.bind(this),
      onDoorChange: this.handleBayDoorChange.bind(this),
      onModeChange: this.handleBayModeChange.bind(this),
      onSubpartitionChange: this.handleBaySubpartitionChange.bind(this),
      onApplyToAll: this.handleApplyBayToAll.bind(this),
      onCopyLeftToRight: this.handleCopyLeftToRight.bind(this),
      onRequestValidity: this.handleRequestBayValidity.bind(this),
      onAnnounce: this.handleBayAnnouncement.bind(this),
      formatMillimeters: this.lengthService.format.bind(this.lengthService),
      translate: translate
    });
  }

  FormController.prototype.captureFieldMetadata = function captureFieldMetadata(name) {
    if (!name) {
      return;
    }

    if (!Object.prototype.hasOwnProperty.call(this.fieldErrorMessages, name)) {
      this.fieldErrorMessages[name] = '';
    }

    var input = this.inputs[name];
    var errorElement = this.errorElements[name];

    if (!Object.prototype.hasOwnProperty.call(this.fieldLabels, name)) {
      this.fieldLabels[name] = '';
    }

    if (input && !this.fieldLabels[name]) {
      var labelText = '';
      if (input.id) {
        var safeId = input.id.replace(/(["\\])/g, '\\$1');
        var label = this.form.querySelector('label[for="' + safeId + '"]');
        if (label) {
          labelText = collapseWhitespace(label.textContent);
        }
      }
      this.fieldLabels[name] = labelText;
    }

    if (input && errorElement) {
      if (!errorElement.id) {
        errorElement.id = 'field-error-' + name;
      }
      ensureDescribedBy(input, errorElement.id);
    }
  };

  FormController.prototype.initializeElements = function initializeElements() {
    var self = this;
    var interactiveNodeList = this.form.querySelectorAll('input, select, textarea');
    this.interactiveElements = Array.prototype.slice.call(interactiveNodeList);
    this.interactiveElements.forEach(function (element) {
      self.disabledByPlacement.set(element, element.disabled);
    });
    LENGTH_FIELDS.forEach(function (name) {
      var input = self.form.querySelector('[name="' + name + '"]');
      self.inputs[name] = input;
      self.errorElements[name] = self.form.querySelector('[data-error-for="' + name + '"]');
      self.values.lengths[name] = null;
      self.touched[name] = false;
      self.captureFieldMetadata(name);
    });

    INTEGER_FIELDS.forEach(function (name) {
      self.inputs[name] = self.form.querySelector('[name="' + name + '"]');
      self.errorElements[name] = self.form.querySelector('[data-error-for="' + name + '"]');
      self.touched[name] = false;
      self.captureFieldMetadata(name);
    });

    this.inputs.front = this.form.querySelector('[name="front"]');
    this.inputs.partitions_mode = this.form.querySelector('[name="partitions_mode"]');
    this.inputs.partitions_positions = this.form.querySelector('[name="partitions_positions"]');
    this.errorElements.partitions_positions = this.form.querySelector('[data-error-for="partitions_positions"]');
    this.errorElements.front = this.form.querySelector('[data-error-for="front"]');
    this.errorElements.partitions_mode = this.form.querySelector('[data-error-for="partitions_mode"]');
    this.touched.partitions_positions = false;
    this.touched.front = false;
    this.touched.partitions_mode = false;
    this.captureFieldMetadata('front');
    this.captureFieldMetadata('partitions_mode');
    this.captureFieldMetadata('partitions_positions');

    if (this.inputs.shelves) {
      this.inputs.shelves.value = '0';
      this.values.shelves = 0;
    }

    if (this.inputs.front) {
      this.values.front = this.inputs.front.value;
    }

    this.captureFieldMetadata('shelves');
  };

  FormController.prototype.toggleElementVisibility = function toggleElementVisibility(
    element,
    shouldShow
  ) {
    if (!element) {
      return;
    }

    if (shouldShow) {
      element.classList.remove('is-hidden');
      element.removeAttribute('hidden');
      element.removeAttribute('aria-hidden');
      setElementInert(element, false);
    } else {
      element.classList.add('is-hidden');
      element.setAttribute('hidden', '');
      element.setAttribute('aria-hidden', 'true');
      setElementInert(element, true);
    }
  };

  FormController.prototype.refreshBaySummary = function refreshBaySummary() {
    var bays = this.values.partitions.bays || [];
    var bayCount = bays.length > 0 ? bays.length : 1;
    if (bayCount === this.lastAnnouncedBayCount) {
      return;
    }

    this.lastAnnouncedBayCount = bayCount;
    var partitionCount = this.values.partition_mode === 'none' ? 0 : Math.max(0, bayCount - 1);
    var partitionLabel =
      partitionCount === 1
        ? translate('count_partition_singular')
        : translate('count_partition_plural');
    var bayLabel = bayCount === 1 ? translate('count_bay_singular') : translate('count_bay_plural');

    this.announce(
      translate('top_level_summary', {
        partitions: partitionCount,
        partition_label: partitionLabel,
        bays: bayCount,
        bay_label: bayLabel
      }),
      { immediate: true }
    );
  };

  FormController.prototype.announce = function announce(message, options) {
    if (!message || !this.liveAnnouncer) {
      return;
    }

    this.liveAnnouncer.post(message, options || {});
  };

  FormController.prototype.deriveVisibilityFromPartitionMode =
    function deriveVisibilityFromPartitionMode(mode) {
      var normalized = this.normalizePartitionMode(mode);
      var showPartitions = normalized !== 'none';

      return {
        show_bays: showPartitions,
        show_partition_controls: showPartitions,
        show_global_front_layout: !showPartitions,
        show_global_shelves: !showPartitions
      };
    };

  FormController.prototype.applyUiVisibility = function applyUiVisibility(flags) {
    var settings = flags && typeof flags === 'object' ? flags : {};
    var derived = this.deriveVisibilityFromPartitionMode(this.values.partition_mode);
    var showPartitionControls =
      typeof settings.show_partition_controls === 'boolean'
        ? settings.show_partition_controls
        : derived.show_partition_controls;
    var showBays =
      typeof settings.show_bays === 'boolean' ? settings.show_bays : derived.show_bays;
    var showFront =
      typeof settings.show_global_front_layout === 'boolean'
        ? settings.show_global_front_layout
        : derived.show_global_front_layout;
    var showShelves =
      typeof settings.show_global_shelves === 'boolean'
        ? settings.show_global_shelves
        : derived.show_global_shelves;

    var effectiveShowBays = showPartitionControls && showBays;

    this.currentUiVisibility = {
      show_partition_controls: showPartitionControls,
      show_bays: effectiveShowBays,
      show_global_front_layout: showFront,
      show_global_shelves: showShelves
    };
    this.toggleElementVisibility(this.partitionControls, showPartitionControls);
    this.toggleElementVisibility(this.baySection, effectiveShowBays);
    this.toggleElementVisibility(this.globalFrontGroup, showFront);
    this.toggleElementVisibility(this.globalShelvesGroup, showShelves);

    if (this.bayController) {
      this.bayController.setButtonsDisabled(!effectiveShowBays);
    }
  };

  FormController.prototype.normalizeBay = function normalizeBay(bay) {
    return cloneBay(bay);
  };

  FormController.prototype.normalizePartitionMode = function normalizePartitionMode(mode) {
    if (typeof mode !== 'string') {
      return 'none';
    }

    var text = mode.trim().toLowerCase();
    if (text === 'vertical' || text === 'horizontal') {
      return text;
    }

    return 'none';
  };

  FormController.prototype.normalizePartitionsLayout = function normalizePartitionsLayout(mode) {
    if (typeof mode !== 'string') {
      return 'none';
    }

    var text = mode.trim().toLowerCase();
    if (text === 'even' || text === 'positions') {
      return text;
    }

    return 'none';
  };

  FormController.prototype.setBayArray = function setBayArray(bays, options) {
    var sanitized = Array.isArray(bays)
      ? bays.map(this.normalizeBay, this)
      : [this.normalizeBay(this.bayTemplate)];
    if (!sanitized.length) {
      sanitized = [this.normalizeBay(this.bayTemplate)];
    }

    var desiredLength = null;
    if (options && typeof options.desiredLength === 'number' && isFinite(options.desiredLength)) {
      desiredLength = Math.max(1, Math.round(options.desiredLength));
    } else {
      desiredLength = this.computeDesiredBayCount();
    }

    if (desiredLength > sanitized.length) {
      var templateSource = sanitized.length ? sanitized[0] : this.bayTemplate;
      while (sanitized.length < desiredLength) {
        sanitized.push(cloneBay(templateSource));
      }
    }

    var preferredIndex = this.selectedBayIndex;
    if (options && typeof options.selectedIndex === 'number' && isFinite(options.selectedIndex)) {
      preferredIndex = options.selectedIndex;
    }
    preferredIndex = clampSelectedIndex(preferredIndex, sanitized.length);

    this.values.partitions.bays = sanitized;
    this.bayTemplate = cloneBay(sanitized[0]);
    this.selectedBayIndex = preferredIndex;

    if (this.bayController) {
      this.bayController.setBays(sanitized.map(cloneBay), {
        selectedIndex: preferredIndex,
        emit: options && options.emit === true
      });
    }
    this.refreshBaySummary();
  };

  FormController.prototype.computeDesiredBayCount = function computeDesiredBayCount() {
    var mode = this.values.partitions.mode;
    if (mode === 'even') {
      if (typeof this.values.partitions.count === 'number') {
        return Math.max(1, this.values.partitions.count + 1);
      }
      return Math.max(1, this.values.partitions.bays.length || 1);
    }

    if (mode === 'positions') {
      var positions = this.values.partitions.positions_mm || [];
      return Math.max(1, positions.length + 1);
    }

    return 1;
  };

  FormController.prototype.ensureBayLength = function ensureBayLength() {
    var desired = this.computeDesiredBayCount();
    var bays = this.values.partitions.bays || [];
    if (desired < 1) {
      desired = 1;
    }

    if (bays.length > desired) {
      bays = bays.slice(0, desired);
    } else if (bays.length < desired) {
      while (bays.length < desired) {
        bays.push(cloneBay(this.bayTemplate));
      }
    }

    this.values.partitions.bays = bays;
    this.selectedBayIndex = clampSelectedIndex(this.selectedBayIndex, bays.length);
    if (this.bayController) {
      this.bayController.setBays(bays.map(cloneBay), {
        selectedIndex: this.selectedBayIndex
      });
    }
    this.refreshBaySummary();
  };

  FormController.prototype.handleBaySelection = function handleBaySelection(index) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    var bays = this.values.partitions.bays || [];
    if (!bays.length) {
      return;
    }

    var clamped = clampSelectedIndex(index, bays.length);
    if (clamped === this.selectedBayIndex) {
      return;
    }

    this.selectedBayIndex = clamped;
    this.pendingSelectedBayIndex = clamped;
    invokeSketchUp('ui_select_bay', JSON.stringify({ index: clamped }));
  };

  FormController.prototype.handleBayShelfChange = function handleBayShelfChange(index, value) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    var bays = this.values.partitions.bays || [];
    if (!bays[index]) {
      this.ensureBayLength();
      bays = this.values.partitions.bays || [];
    }

    if (!bays[index]) {
      bays[index] = cloneBay(this.bayTemplate);
    }

    var numeric = Math.max(0, Math.round(Number(value) || 0));
    var state = bays[index].fronts_shelves_state || { shelf_count: 0, door_mode: null };
    state.shelf_count = numeric;
    bays[index].fronts_shelves_state = state;
    bays[index].shelf_count = numeric;
    if (this.bayTemplate.fronts_shelves_state) {
      this.bayTemplate.fronts_shelves_state.shelf_count = bays[0]
        ? bays[0].fronts_shelves_state && typeof bays[0].fronts_shelves_state.shelf_count === 'number'
          ? bays[0].fronts_shelves_state.shelf_count
          : numeric
        : numeric;
    }
    this.bayTemplate.shelf_count = bays[0] ? bays[0].shelf_count : numeric;
    if (this.bayController) {
      this.bayController.setBayValue(index, bays[index]);
    }
    this.updateInsertButtonState();
    if (normalizeBayMode(bays[index].mode) === 'fronts_shelves') {
      this.sendBayShelfUpdate(index, numeric);
    }
  };

  FormController.prototype.handleBayDoorChange = function handleBayDoorChange(index, value) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    var bays = this.values.partitions.bays || [];
    if (!bays[index]) {
      this.ensureBayLength();
      bays = this.values.partitions.bays || [];
    }

    if (!bays[index]) {
      bays[index] = cloneBay(this.bayTemplate);
    }

    var normalized = value === 'none' ? null : value;
    var state = bays[index].fronts_shelves_state || { shelf_count: 0, door_mode: null };
    state.door_mode = normalized;
    bays[index].fronts_shelves_state = state;
    bays[index].door_mode = normalized;
    if (index === 0 && this.bayTemplate.fronts_shelves_state) {
      this.bayTemplate.fronts_shelves_state.door_mode = normalized;
    }
    if (index === 0) {
      this.bayTemplate.door_mode = normalized;
    }
    if (this.bayController) {
      this.bayController.setBayValue(index, bays[index]);
    }
    this.updateInsertButtonState();
    if (normalizeBayMode(bays[index].mode) === 'fronts_shelves') {
      this.sendBayDoorUpdate(index, normalized);
    }
  };

  FormController.prototype.handleBayModeChange = function handleBayModeChange(index, value) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    var bays = this.values.partitions.bays || [];
    if (!bays[index]) {
      this.ensureBayLength();
      bays = this.values.partitions.bays || [];
    }

    if (!bays[index]) {
      bays[index] = cloneBay(this.bayTemplate);
    }

    var normalized = value === 'subpartitions' ? 'subpartitions' : 'fronts_shelves';
    bays[index].mode = normalized;
    if (this.bayController) {
      this.bayController.setBayValue(index, bays[index]);
    }
    this.updateInsertButtonState();
    this.sendBayModeUpdate(index, normalized);
  };

  FormController.prototype.handleBaySubpartitionChange = function handleBaySubpartitionChange(index, value) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    var bays = this.values.partitions.bays || [];
    if (!bays[index]) {
      this.ensureBayLength();
      bays = this.values.partitions.bays || [];
    }

    if (!bays[index]) {
      bays[index] = cloneBay(this.bayTemplate);
    }

    var numeric = Math.max(0, Math.round(Number(value) || 0));
    var state = bays[index].subpartitions_state || { count: 0 };
    state.count = numeric;
    bays[index].subpartitions_state = state;
    if (this.bayTemplate.subpartitions_state) {
      var templateCount = bays[0]
        ? bays[0].subpartitions_state && typeof bays[0].subpartitions_state.count === 'number'
          ? bays[0].subpartitions_state.count
          : numeric
        : numeric;
      this.bayTemplate.subpartitions_state.count = templateCount;
    }
    if (this.bayController) {
      this.bayController.setBayValue(index, bays[index]);
    }
    this.updateInsertButtonState();
    if (normalizeBayMode(bays[index].mode) === 'subpartitions') {
      this.sendBaySubpartitionUpdate(index, numeric);
    }
  };

  FormController.prototype.handleApplyBayToAll = function handleApplyBayToAll(index) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    invokeSketchUp('ui_apply_to_all', JSON.stringify({ index: index }));
  };

  FormController.prototype.handleCopyLeftToRight = function handleCopyLeftToRight() {
    invokeSketchUp('ui_copy_left_to_right');
  };

  FormController.prototype.handleRequestBayValidity = function handleRequestBayValidity(index) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    invokeSketchUp('ui_request_validity', JSON.stringify({ index: index }));
  };

  FormController.prototype.handleBayAnnouncement = function handleBayAnnouncement(message, options) {
    if (!message) {
      return;
    }
    this.announce(message, options);
  };

  FormController.prototype.notifyPartitionModeChange = function notifyPartitionModeChange(mode) {
    var normalized = this.normalizePartitionMode(mode);
    if (this.lastSentPartitionMode === normalized) {
      return;
    }

    this.lastSentPartitionMode = normalized;
    invokeSketchUp('ui_set_partition_mode', JSON.stringify({ value: normalized }));
  };

  FormController.prototype.notifyPartitionsLayoutChange = function notifyPartitionsLayoutChange(mode) {
    var normalized = this.normalizePartitionsLayout(mode);
    if (this.lastSentPartitionsLayout === normalized) {
      return;
    }

    this.lastSentPartitionsLayout = normalized;
    invokeSketchUp('ui_set_partitions_layout', JSON.stringify({ value: normalized }));
  };

  FormController.prototype.notifyPartitionCountChange = function notifyPartitionCountChange(value) {
    var numeric = Number(value);
    if (!isFinite(numeric)) {
      return;
    }

    numeric = Math.max(0, Math.round(numeric));
    var bays = this.values.partitions.bays || [];
    var selectedIndex = clampSelectedIndex(this.selectedBayIndex, bays.length);
    this.selectedBayIndex = selectedIndex;
    this.pendingSelectedBayIndex = selectedIndex;

    this.sendPartitionsState(numeric, selectedIndex);
  };

  FormController.prototype.sendPartitionsState = function sendPartitionsState(count, selectedIndex) {
    if (this.values.partition_mode === 'none') {
      return;
    }

    var numericCount = Number(count);
    if (!isFinite(numericCount)) {
      numericCount = 0;
    }
    numericCount = Math.max(0, Math.round(numericCount));

    var bayCount = this.values.partitions.bays ? this.values.partitions.bays.length : 0;
    var clampedIndex = clampSelectedIndex(selectedIndex, bayCount);

    var previous = this.lastSentPartitionsState;
    if (
      previous &&
      previous.count === numericCount &&
      previous.selected_index === clampedIndex
    ) {
      return;
    }

    this.lastSentPartitionsState = { count: numericCount, selected_index: clampedIndex };
    var payload = { count: numericCount, selected_index: clampedIndex };
    invokeSketchUp('ui_partitions_changed', JSON.stringify(payload));
  };

  FormController.prototype.sendBayShelfUpdate = function sendBayShelfUpdate(index, value) {
    var payload = { index: index, value: value };
    invokeSketchUp('ui_set_shelf_count', JSON.stringify(payload));
  };

  FormController.prototype.sendBayDoorUpdate = function sendBayDoorUpdate(index, value) {
    var payload = { index: index, value: value };
    invokeSketchUp('ui_set_door_mode', JSON.stringify(payload));
  };

  FormController.prototype.sendBayModeUpdate = function sendBayModeUpdate(index, mode) {
    var payload = { index: index, value: mode };
    invokeSketchUp('ui_set_bay_mode', JSON.stringify(payload));
  };

  FormController.prototype.sendBaySubpartitionUpdate = function sendBaySubpartitionUpdate(index, count) {
    var payload = { index: index, count: count };
    invokeSketchUp('ui_set_subpartition_count', JSON.stringify(payload));
  };

  FormController.prototype.updateBayFromSketchUp = function updateBayFromSketchUp(index, bay) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    var bays = this.values.partitions.bays || [];
    while (bays.length <= index) {
      bays.push(cloneBay(this.bayTemplate));
    }

    bays[index] = this.normalizeBay(bay);
    this.values.partitions.bays = bays;
    if (this.bayController) {
      this.bayController.setBayValue(index, bays[index]);
    }
    this.refreshBaySummary();
    this.updateInsertButtonState();
  };

  FormController.prototype.applyBayStateInit = function applyBayStateInit(state) {
    if (!state || typeof state !== 'object') {
      return;
    }

    var statePartitionMode = this.normalizePartitionMode(state.partition_mode);
    if (state.partitions && typeof state.partitions.mode === 'string') {
      var layoutMode = this.normalizePartitionsLayout(state.partitions.mode);
      this.values.partitions.mode = layoutMode;
      if (layoutMode !== 'none') {
        if (statePartitionMode === 'vertical' || statePartitionMode === 'horizontal') {
          this.partitionLayoutByMode[statePartitionMode] = layoutMode;
        }
      }
      if (this.inputs.partitions_mode) {
        this.inputs.partitions_mode.value = layoutMode;
      }
    }

    var count = null;
    if (state.partitions && typeof state.partitions.count === 'number') {
      count = Math.max(0, Math.round(state.partitions.count));
      this.values.partitions.count = count;
    }

    if (state.partitions && Array.isArray(state.partitions.positions_mm)) {
      this.values.partitions.positions_mm = state.partitions.positions_mm.slice();
    }

    var bays = Array.isArray(state.bays) ? state.bays : [];
    var bayTotal = bays.length > 0 ? bays.length : 1;
    var pendingSelection = this.pendingSelectedBayIndex;
    var nextSelected = this.selectedBayIndex;
    if (typeof state.selected_index === 'number' && isFinite(state.selected_index)) {
      nextSelected = state.selected_index;
    }

    if (pendingSelection != null && isFinite(pendingSelection)) {
      nextSelected = pendingSelection;
    }

    nextSelected = clampSelectedIndex(nextSelected, bayTotal);

    this.selectedBayIndex = nextSelected;
    this.setBayArray(bays, { selectedIndex: nextSelected });
    this.ensureBayLength();
    this.pendingSelectedBayIndex = null;

    if (count == null) {
      var bayCount = this.values.partitions.bays ? this.values.partitions.bays.length : 0;
      count = Math.max(0, bayCount - 1);
      this.values.partitions.count = count;
    }

    if (this.inputs.partitions_count) {
      if (this.values.partitions.mode === 'even') {
        this.inputs.partitions_count.value = String(count);
      } else {
        this.inputs.partitions_count.value = '';
      }
      this.inputs.partitions_count.removeAttribute('data-invalid');
      this.touched.partitions_count = false;
      this.setFieldError('partitions_count', null, true);
    }

    if (this.inputs.partitions_positions) {
      if (this.values.partitions.mode === 'positions') {
        this.reformatPartitionPositions();
      } else {
        this.inputs.partitions_positions.value = '';
      }
      this.inputs.partitions_positions.removeAttribute('data-invalid');
      this.touched.partitions_positions = false;
      this.setFieldError('partitions_positions', null, true);
    }

    this.setPartitionsLayout(this.values.partitions.mode, {
      notify: false,
      resetValues: false,
      ensureLength: false,
      updateInsertButton: false,
      force: true
    });
    this.setPartitionMode(statePartitionMode, {
      notify: false,
      resetSelection: false,
      restoreLayout: false,
      ensureLength: false,
      updateInsertButton: false
    });

    if (Array.isArray(state.can_double)) {
      state.can_double.forEach(
        function (entry, index) {
          if (!entry || typeof entry !== 'object') {
            return;
          }
          this.applyDoubleValidity(index, entry);
        }.bind(this)
      );
    }

    if (state.ui && typeof state.ui === 'object') {
      this.applyUiVisibility(state.ui);
    } else if (this.currentUiVisibility) {
      this.applyUiVisibility(this.currentUiVisibility);
    }

    this.lastSentPartitionMode = this.values.partition_mode;
    this.lastSentPartitionsState = {
      count: count,
      selected_index: this.selectedBayIndex
    };
  };

  FormController.prototype.applyDoubleValidity = function applyDoubleValidity(index, payload) {
    if (this.bayController) {
      this.bayController.setDoubleValidity(index, payload);
    }
  };

  FormController.prototype.showToast = function showToast(message) {
    if (!message) {
      return;
    }
    if (this.bayController) {
      this.bayController.announce(message);
    }
    this.setBanner('success', message, { autoHide: true });
  };

  FormController.prototype.bindEvents = function bindEvents() {
    var self = this;

    LENGTH_FIELDS.forEach(function (name) {
      var input = self.inputs[name];
      if (!input) {
        return;
      }

      input.addEventListener('input', function () {
        self.handleLengthInput(name);
      });

      input.addEventListener('blur', function () {
        self.handleLengthBlur(name);
      });
    });

    INTEGER_FIELDS.forEach(function (name) {
      var input = self.inputs[name];
      if (!input) {
        return;
      }

      input.addEventListener('input', function () {
        self.handleIntegerInput(name);
      });

      input.addEventListener('blur', function () {
        self.handleIntegerBlur(name);
      });
    });

    if (this.inputs.front) {
      this.inputs.front.addEventListener('change', function (event) {
        self.values.front = event.target.value;
        self.touched.front = true;
        self.setFieldError('front', null, true);
        event.target.removeAttribute('data-invalid');
      });
    }

    if (this.inputs.partitions_mode) {
      this.inputs.partitions_mode.addEventListener('change', function (event) {
        self.handlePartitionsLayoutChange(event.target.value);
        self.touched.partitions_mode = true;
        self.setFieldError('partitions_mode', null, true);
        event.target.removeAttribute('data-invalid');
      });
    }

    if (this.partitionModeInputs.length) {
      bindSegmentedGroupKeyHandlers(this.partitionModeInputs);
      this.partitionModeInputs.forEach(function (input) {
        input.addEventListener('change', function (event) {
          if (event.target.checked) {
            self.setPartitionMode(event.target.value);
          }
        });
      });
    }

    if (this.inputs.partitions_positions) {
      this.inputs.partitions_positions.addEventListener('input', function () {
        self.handlePartitionsPositionsInput();
      });

      this.inputs.partitions_positions.addEventListener('blur', function () {
        self.handlePartitionsPositionsBlur();
      });
    }

    if (this.scopeInputs.length) {
      this.scopeInputs.forEach(function (input) {
        input.addEventListener('change', function (event) {
          if (event.target.checked) {
            self.setScope(event.target.value);
          }
        });
      });
    }

    this.form.addEventListener('submit', function (event) {
      event.preventDefault();
    });
  };

  FormController.prototype.setUnits = function setUnits(settings) {
    this.lengthService.updateSettings(settings);
    this.updateUnitsNotice();
    this.reformatValidatedLengths();
    this.reformatPartitionPositions();
  };

  FormController.prototype.applyDefaults = function applyDefaults(defaults) {
    if (!defaults || typeof defaults !== 'object') {
      return;
    }

    var formatLength = this.lengthService.format.bind(this.lengthService);

    LENGTH_FIELDS.forEach(
      function (name) {
        var key = LENGTH_DEFAULT_KEYS[name];
        var input = this.inputs[name];
        if (!key || !input) {
          return;
        }

        var mmValue = defaults[key];
        if (typeof mmValue !== 'number') {
          mmValue = Number(mmValue);
        }

        if (!isFinite(mmValue)) {
          return;
        }

        this.values.lengths[name] = mmValue;
        this.touched[name] = false;
        input.dataset.mmValue = String(mmValue);
        input.value = formatLength(mmValue);
        input.removeAttribute('data-invalid');
        this.setFieldError(name, null, true);
      }.bind(this)
    );

    var toeKickThickness = defaults.toe_kick_thickness_mm;
    if (typeof toeKickThickness !== 'number') {
      toeKickThickness = Number(toeKickThickness);
    }
    if (!isFinite(toeKickThickness)) {
      toeKickThickness = this.values.lengths.panel_thickness;
    }
    if (isFinite(toeKickThickness)) {
      this.values.lengths.toe_kick_thickness = toeKickThickness;
    }

    if (typeof defaults.front === 'string' && this.inputs.front) {
      this.inputs.front.value = defaults.front;
      this.values.front = this.inputs.front.value;
    }

    if (this.inputs.shelves) {
      var shelves = defaults.shelves;
      if (typeof shelves !== 'number') {
        shelves = Number(shelves);
      }

      if (isFinite(shelves)) {
        shelves = Math.max(0, Math.round(shelves));
        this.inputs.shelves.value = String(shelves);
        this.values.shelves = shelves;
        this.inputs.shelves.removeAttribute('data-invalid');
        this.setFieldError('shelves', null, true);
        this.touched.shelves = false;
      }
    }

    var defaultPartitionMode = this.normalizePartitionMode(defaults.partition_mode);
    if (defaults.partitions && typeof defaults.partitions === 'object') {
      var partitions = defaults.partitions;
      var layoutMode = this.normalizePartitionsLayout(partitions.mode);

      if (layoutMode !== 'none') {
        this.partitionLayoutByMode.vertical = layoutMode;
        this.partitionLayoutByMode.horizontal = layoutMode;
      }

      var count = partitions.count;
      if (typeof count !== 'number') {
        count = Number(count);
      }
      if (!isFinite(count)) {
        count = layoutMode === 'even' ? null : 0;
      } else {
        count = Math.max(0, Math.round(count));
      }

      this.values.partitions.count = count;
      if (this.inputs.partitions_count) {
        if (layoutMode === 'even' && count != null) {
          this.inputs.partitions_count.value = String(count);
        } else {
          this.inputs.partitions_count.value = '';
        }
        this.inputs.partitions_count.removeAttribute('data-invalid');
      }
      this.setFieldError('partitions_count', null, true);
      this.touched.partitions_count = false;

      var positions = Array.isArray(partitions.positions_mm)
        ? partitions.positions_mm.slice()
        : [];
      if (layoutMode === 'positions') {
        this.values.partitions.positions_mm = positions;
        if (this.inputs.partitions_positions) {
          if (positions.length) {
            var formattedPositions = positions.map(formatLength);
            this.inputs.partitions_positions.value = formattedPositions.join(', ');
          } else {
            this.inputs.partitions_positions.value = '';
          }
          this.inputs.partitions_positions.removeAttribute('data-invalid');
        }
      } else {
        this.values.partitions.positions_mm = [];
        if (this.inputs.partitions_positions) {
          this.inputs.partitions_positions.value = '';
          this.inputs.partitions_positions.removeAttribute('data-invalid');
        }
      }

      var baysArray = Array.isArray(partitions.bays) ? partitions.bays : [];
      this.setBayArray(baysArray, { selectedIndex: 0 });

      this.setFieldError('partitions_positions', null, true);
      this.touched.partitions_positions = false;
    } else {
      this.setBayArray([], { selectedIndex: 0 });
    }

    this.setPartitionsLayout(
      this.normalizePartitionsLayout(
        defaults.partitions && typeof defaults.partitions === 'object'
          ? defaults.partitions.mode
          : 'none'
      ),
      {
        notify: false,
        resetValues: false,
        ensureLength: false,
        updateInsertButton: false,
        force: true
      }
    );
    this.setPartitionMode(defaultPartitionMode, {
      notify: false,
      resetSelection: false,
      restoreLayout: false,
      ensureLength: false,
      updateInsertButton: false,
      announce: false
    });
    this.touched.partitions_mode = false;
    this.setFieldError('partitions_mode', null, true);

    this.ensureBayLength();

    this.updateInsertButtonState();
  };

  FormController.prototype.configureMode = function configureMode(options) {
    if (options === void 0) {
      options = {};
    }

    var mode = options.mode === 'edit' ? 'edit' : 'insert';
    this.mode = mode;
    if (options && typeof options.placementNotice === 'string') {
      this.placementNotice = options.placementNotice;
    }
    this.setPlacingState(false);

    var copy = MODE_COPY[mode] || MODE_COPY.insert;
    if (this.dialogTitle) {
      this.dialogTitle.textContent = copy.title;
    }

    if (this.dialogSubtitle) {
      this.dialogSubtitle.innerHTML = copy.subtitle;
    }

    this.primaryActionLabel = copy.primaryLabel;

    if (this.scopeSection) {
      var showScope = mode === 'edit';
      this.scopeSection.classList.toggle('is-hidden', !showScope);
    }

    if (mode === 'edit') {
      this.scopeDefault = options.scopeDefault === 'all' ? 'all' : 'instance';
      var selectionProvided = options.selectionProvided === true;
      this.selectionProvided = selectionProvided;
      var selection = selectionProvided && options.selection && typeof options.selection === 'object'
        ? {
            instancesCount: options.selection.instancesCount,
            definitionName: options.selection.definitionName,
            sharesDefinition: options.selection.sharesDefinition
          }
        : defaultSelectionInfo();
      this.selectionInfo = selection;

      this.scopeDisplayMode = this.determineScopeDisplayMode(selection);
      this.applyScopeDisplayMode();

      var scopeValue =
        options.scope === 'all'
          ? 'all'
          : options.scope === 'instance'
          ? 'instance'
          : this.scopeDefault;
      this.setScope(scopeValue);
    } else {
      this.scopeDefault = 'instance';
      this.selectionInfo = defaultSelectionInfo();
      this.scopeDisplayMode = 'hidden';
      this.selectionProvided = false;
      this.applyScopeDisplayMode();
      this.setScope('instance');
    }

    this.updateScopeNoteText();
    this.updatePrimaryActionLabel();

    this.updateInsertButtonState();
  };

  FormController.prototype.determineScopeDisplayMode =
    function determineScopeDisplayMode(selection) {
      if (this.mode !== 'edit') {
        return 'hidden';
      }

      var info = selection || this.selectionInfo || defaultSelectionInfo();
      var count = info.instancesCount;
      var hasCount = typeof count === 'number' && isFinite(count);
      var selectionProvided = this.selectionProvided === true;
      if (!hasCount) {
        if (selectionProvided && info.sharesDefinition === false) {
          return 'note';
        }
        return 'controls';
      }

      var normalized = Math.max(0, Math.round(count));
      if (normalized <= 1) {
        return selectionProvided ? 'note' : 'controls';
      }

      if (normalized > 1) {
        return 'controls';
      }

      return 'controls';
    };

  FormController.prototype.applyScopeDisplayMode =
    function applyScopeDisplayMode() {
      var mode = this.scopeDisplayMode;
      var showControls = mode === 'controls';
      var showNote = mode === 'note';

      if (this.scopeSection) {
        this.scopeSection.classList.toggle(
          'dialog__scope--note-only',
          showNote
        );
      }

      if (this.scopeControls) {
        this.scopeControls.hidden = !showControls;
        this.scopeControls.classList.toggle('is-hidden', !showControls);
      }

      if (!showControls && this.scopeHint) {
        this.scopeHint.textContent = '';
        this.scopeHint.hidden = true;
      }

      if (this.scopeNote) {
        this.scopeNote.hidden = !showNote;
        this.scopeNote.classList.toggle('is-hidden', !showNote);
        if (showNote) {
          this.updateScopeNoteText();
        }
      }
    };

  FormController.prototype.updateScopeNoteText =
    function updateScopeNoteText() {
      if (!this.scopeNote || this.scopeDisplayMode !== 'note') {
        return;
      }

      var info = this.selectionInfo || defaultSelectionInfo();
      var name = info.definitionName;
      var label = 'This cabinet';
      if (typeof name === 'string') {
        var trimmed = name.trim();
        if (trimmed) {
          label = trimmed;
        }
      }

      this.scopeNote.textContent =
        'Scope: ' + label + ' (already unique).';
    };

  FormController.prototype.setScope = function setScope(value) {
    var normalized = value === 'all' ? 'all' : 'instance';
    this.scope = normalized;

    if (!this.scopeInputs.length) {
      this.updateScopeHint();
      this.updatePrimaryActionLabel();
      return;
    }

    this.scopeInputs.forEach(function (input) {
      input.checked = input.value === normalized;
    });

    this.updateScopeHint();
    this.updatePrimaryActionLabel();
  };

  FormController.prototype.updateScopeHint = function updateScopeHint() {
    if (!this.scopeHint) {
      return;
    }

    if (this.mode !== 'edit' || this.scopeDisplayMode !== 'controls') {
      this.scopeHint.textContent = '';
      this.scopeHint.hidden = true;
      return;
    }

    var info = this.selectionInfo || defaultSelectionInfo();
    var instancesCount = info.instancesCount;
    if (typeof instancesCount !== 'number' || !isFinite(instancesCount)) {
      instancesCount = 0;
    }
    instancesCount = Math.max(0, Math.round(instancesCount));

    var sharesDefinition = info.sharesDefinition;
    if (typeof sharesDefinition !== 'boolean') {
      sharesDefinition = instancesCount > 1;
    }

    var message = '';
    if (this.scope === 'all') {
      var noun = instancesCount === 1 ? 'instance' : 'instances';
      var name = info.definitionName;
      var namePart = '';
      if (typeof name === 'string' && name.trim()) {
        namePart = " of '" + name.trim() + "'";
      } else {
        namePart = ' of this cabinet';
      }
      message = 'Will update ' + instancesCount + ' ' + noun + namePart + '.';
    } else if (sharesDefinition) {
      message = 'Will make this cabinet unique.';
    }

    this.scopeHint.textContent = message;
    this.scopeHint.hidden = !message;
  };

  FormController.prototype.updatePrimaryActionLabel =
    function updatePrimaryActionLabel() {
      if (!this.insertButton) {
        return;
      }

      var label = this.primaryActionLabel || '';
      this.insertButton.textContent = label;

      if (this.mode === 'edit') {
        if (this.scopeDisplayMode === 'controls') {
          var scopeDescription =
            this.scope === 'all' ? 'all instances' : 'this instance only';
          var ariaLabel = label;
          if (scopeDescription) {
            ariaLabel = label + ' (' + scopeDescription + ')';
          }
          this.insertButton.setAttribute('aria-label', ariaLabel);
        } else if (label) {
          this.insertButton.setAttribute('aria-label', label);
        } else {
          this.insertButton.removeAttribute('aria-label');
        }
      } else if (label) {
        this.insertButton.setAttribute('aria-label', label);
      } else {
        this.insertButton.removeAttribute('aria-label');
      }
    };

  FormController.prototype.updateUnitsNotice = function updateUnitsNotice() {
    if (!this.unitsNote) {
      return;
    }

    var unitName = this.lengthService.settings.unit_name;
    this.unitsNote.textContent =
      'Values without a suffix use the model\'s display unit (' +
      unitName +
      '). Examples: 600, 450mm, 2\' 3-1/2", 24 in.';
  };

  FormController.prototype.reformatValidatedLengths = function reformatValidatedLengths() {
    var self = this;
    LENGTH_FIELDS.forEach(function (name) {
      var value = self.values.lengths[name];
      if (value != null) {
        self.inputs[name].value = self.lengthService.format(value);
      }
    });
  };

  FormController.prototype.reformatPartitionPositions = function reformatPartitionPositions() {
    if (
      this.values.partitions.mode === 'positions' &&
      this.values.partitions.positions_mm.length &&
      this.inputs.partitions_positions
    ) {
      var formatted = this.values.partitions.positions_mm.map(
        this.lengthService.format.bind(this.lengthService)
      );
      this.inputs.partitions_positions.value = formatted.join(', ');
    }
  };

  FormController.prototype.handleLengthInput = function handleLengthInput(name) {
    var input = this.inputs[name];
    var result = this.lengthService.parse(input.value);
    if (result.ok) {
      this.values.lengths[name] = result.value_mm;
      input.dataset.mmValue = String(result.value_mm);
      this.setFieldError(name, null, false);
      input.removeAttribute('data-invalid');
    } else {
      this.values.lengths[name] = null;
      delete input.dataset.mmValue;
      if (this.touched[name]) {
        this.setFieldError(name, result.error, true);
        input.setAttribute('data-invalid', 'true');
      } else {
        this.setFieldError(name, null, false);
        input.removeAttribute('data-invalid');
      }
    }

    this.updateInsertButtonState();
  };

  FormController.prototype.handleLengthBlur = function handleLengthBlur(name) {
    this.touched[name] = true;
    var input = this.inputs[name];
    var result = this.lengthService.parse(input.value);
    if (result.ok) {
      this.values.lengths[name] = result.value_mm;
      input.dataset.mmValue = String(result.value_mm);
      input.value = this.lengthService.format(result.value_mm);
      this.setFieldError(name, null, true);
      input.removeAttribute('data-invalid');
    } else {
      this.values.lengths[name] = null;
      delete input.dataset.mmValue;
      this.setFieldError(name, result.error, true);
      input.setAttribute('data-invalid', 'true');
    }

    this.updateInsertButtonState();
  };

  FormController.prototype.handleIntegerInput = function handleIntegerInput(name) {
    var input = this.inputs[name];
    var result = parseNonNegativeInteger(input.value);
    if (result.ok) {
      this.applyIntegerValue(name, result.value);
      this.setFieldError(name, null, false);
      input.removeAttribute('data-invalid');
    } else {
      this.applyIntegerValue(name, null);
      if (this.touched[name]) {
        this.setFieldError(name, result.error, true);
        input.setAttribute('data-invalid', 'true');
      } else {
        this.setFieldError(name, null, false);
        input.removeAttribute('data-invalid');
      }
    }

    this.updateInsertButtonState();
  };

  FormController.prototype.handleIntegerBlur = function handleIntegerBlur(name) {
    this.touched[name] = true;
    var input = this.inputs[name];
    var result = parseNonNegativeInteger(input.value);
    if (result.ok) {
      this.applyIntegerValue(name, result.value);
      this.setFieldError(name, null, true);
      input.value = String(result.value);
      input.removeAttribute('data-invalid');
    } else {
      this.applyIntegerValue(name, null);
      this.setFieldError(name, result.error, true);
      input.setAttribute('data-invalid', 'true');
    }

    this.updateInsertButtonState();
  };

  FormController.prototype.applyIntegerValue = function applyIntegerValue(name, value) {
    if (name === 'shelves') {
      this.values.shelves = value;
    } else if (name === 'partitions_count') {
      this.values.partitions.count = value;
      this.ensureBayLength();
      if (this.values.partition_mode !== 'none' && value != null && isFinite(value)) {
        this.notifyPartitionCountChange(value);
      }
    }
  };

  FormController.prototype.resetBaySelection = function resetBaySelection() {
    this.ensureBayLength();
    this.selectedBayIndex = 0;
    this.pendingSelectedBayIndex = 0;
    if (this.bayController) {
      this.bayController.setSelectedIndex(0, { emit: false });
    }
    invokeSketchUp('ui_select_bay', JSON.stringify({ index: 0 }));
  };

  FormController.prototype.setPartitionMode = function setPartitionMode(mode, options) {
    options = options || {};
    var normalized = this.normalizePartitionMode(mode);
    var previous = this.values.partition_mode;

    this.values.partition_mode = normalized;
    if (this.partitionModeInputs) {
      this.partitionModeInputs.forEach(function (input) {
        input.checked = input.value === normalized;
      });
    }

    if (normalized === 'none') {
      if (options.restoreLayout !== false) {
        this.setPartitionsLayout('none', {
          notify: options.notifyLayout === true,
          resetValues: false,
          ensureLength: options.ensureLength,
          updateInsertButton: options.updateInsertButton,
          force: true
        });
      }
    } else if (options.restoreLayout !== false) {
      var cached = this.partitionLayoutByMode[normalized];
      if (!cached || cached === 'none') {
        cached = 'even';
      }
      this.setPartitionsLayout(cached, {
        notify: options.notifyLayout !== false,
        resetValues: options.resetLayoutValues !== false,
        ensureLength: options.ensureLength,
        updateInsertButton: options.updateInsertButton,
        force: true
      });
    }

    var shouldReset = options.resetSelection;
    if (shouldReset == null) {
      shouldReset = previous !== normalized;
    }
    if (shouldReset) {
      this.resetBaySelection();
    }

    this.applyUiVisibility(this.deriveVisibilityFromPartitionMode(normalized));

    if (options.announce !== false && previous !== normalized) {
      var modeStatusKey;
      if (normalized === 'vertical') {
        modeStatusKey = 'partition_mode_status_vertical';
      } else if (normalized === 'horizontal') {
        modeStatusKey = 'partition_mode_status_horizontal';
      } else {
        modeStatusKey = 'partition_mode_status_none';
      }
      this.announce(translate(modeStatusKey), { immediate: true });
    }

    if (options.notify !== false) {
      this.notifyPartitionModeChange(normalized);
    }
  };

  FormController.prototype.setPartitionsLayout = function setPartitionsLayout(mode, options) {
    options = options || {};
    var normalized = this.normalizePartitionsLayout(mode);
    var previous = this.values.partitions.mode;
    if (normalized === previous && options.force !== true) {
      return;
    }

    this.values.partitions.mode = normalized;
    if (this.inputs.partitions_mode) {
      this.inputs.partitions_mode.value = normalized;
    }
    this.updatePartitionsLayoutUI(normalized);

    if (options.resetValues !== false) {
      if (normalized === 'even') {
        this.values.partitions.count = null;
        if (this.inputs.partitions_count) {
          this.inputs.partitions_count.value = '';
          this.inputs.partitions_count.removeAttribute('data-invalid');
        }
        this.setFieldError('partitions_count', null, true);
        this.touched.partitions_count = false;
      } else if (normalized !== 'positions') {
        this.values.partitions.count = 0;
        if (this.inputs.partitions_count) {
          this.inputs.partitions_count.value = '';
          this.inputs.partitions_count.removeAttribute('data-invalid');
        }
        this.setFieldError('partitions_count', null, true);
        this.touched.partitions_count = false;
      }

      if (normalized !== 'positions') {
        this.values.partitions.positions_mm = [];
        if (this.inputs.partitions_positions) {
          this.inputs.partitions_positions.value = '';
          this.inputs.partitions_positions.removeAttribute('data-invalid');
        }
        this.setFieldError('partitions_positions', null, true);
        this.touched.partitions_positions = false;
      }
    }

    if (this.values.partition_mode === 'vertical' || this.values.partition_mode === 'horizontal') {
      if (normalized !== 'none') {
        this.partitionLayoutByMode[this.values.partition_mode] = normalized;
      }
    }

    if (options.ensureLength !== false) {
      this.ensureBayLength();
    }
    if (options.updateInsertButton !== false) {
      this.updateInsertButtonState();
    }

    if (options.notify !== false) {
      this.notifyPartitionsLayoutChange(normalized);
    }
  };

  FormController.prototype.updatePartitionsLayoutUI = function updatePartitionsLayoutUI(mode) {
    if (this.partitionsEvenField) {
      this.partitionsEvenField.classList.toggle('is-hidden', mode !== 'even');
    }

    if (this.partitionsPositionsField) {
      this.partitionsPositionsField.classList.toggle('is-hidden', mode !== 'positions');
    }
  };

  FormController.prototype.handlePartitionsLayoutChange = function handlePartitionsLayoutChange(mode) {
    this.setPartitionsLayout(mode);
  };

  FormController.prototype.handlePartitionsPositionsInput = function handlePartitionsPositionsInput() {
    var input = this.inputs.partitions_positions;
    if (!input) {
      return;
    }

    var result = this.parsePartitionPositions(input.value);
    if (result.ok) {
      this.values.partitions.positions_mm = result.values_mm;
      this.setFieldError('partitions_positions', null, false);
      input.removeAttribute('data-invalid');
      this.ensureBayLength();
    } else {
      this.values.partitions.positions_mm = [];
      if (this.touched.partitions_positions) {
        this.setFieldError('partitions_positions', result.error, true);
        input.setAttribute('data-invalid', 'true');
      } else {
        this.setFieldError('partitions_positions', null, false);
        input.removeAttribute('data-invalid');
      }
    }

    this.updateInsertButtonState();
  };

  FormController.prototype.handlePartitionsPositionsBlur = function handlePartitionsPositionsBlur() {
    this.touched.partitions_positions = true;
    var input = this.inputs.partitions_positions;
    if (!input) {
      return;
    }

    var result = this.parsePartitionPositions(input.value);
    if (result.ok) {
      this.values.partitions.positions_mm = result.values_mm;
      var formatted = result.values_mm.map(this.lengthService.format.bind(this.lengthService));
      input.value = formatted.join(', ');
      this.setFieldError('partitions_positions', null, true);
      input.removeAttribute('data-invalid');
      this.ensureBayLength();
    } else {
      this.values.partitions.positions_mm = [];
      this.setFieldError('partitions_positions', result.error, true);
      input.setAttribute('data-invalid', 'true');
    }

    this.updateInsertButtonState();
  };

  FormController.prototype.parsePartitionPositions = function parsePartitionPositions(value) {
    var raw = String(value == null ? '' : value).trim();
    if (!raw) {
      return { ok: false, error: 'Enter one or more positions separated by commas.' };
    }

    var tokens = raw
      .split(/[,;]+/)
      .map(function (token) {
        return token.trim();
      })
      .filter(function (token) {
        return token.length > 0;
      });

    if (!tokens.length) {
      return { ok: false, error: 'Enter one or more positions separated by commas.' };
    }

    var values = [];
    for (var i = 0; i < tokens.length; i += 1) {
      var token = tokens[i];
      var result = this.lengthService.parse(token);
      if (!result.ok) {
        return { ok: false, error: 'Position ' + (i + 1) + ': ' + result.error };
      }

      if (result.value_mm < 0) {
        return { ok: false, error: 'Positions must be non-negative.' };
      }

      values.push(result.value_mm);
    }

    for (var j = 1; j < values.length; j += 1) {
      if (values[j] <= values[j - 1]) {
        return { ok: false, error: 'Positions must increase from left to right.' };
      }
    }

    return { ok: true, values_mm: values };
  };

  FormController.prototype.setFieldError = function setFieldError(name, message, persist) {
    if (persist === void 0) {
      persist = true;
    }

    var element = this.errorElements[name];
    var input = this.inputs[name];
    var previous = this.fieldErrorMessages[name] || '';
    var text = message ? String(message) : '';

    if (element) {
      if (text) {
        element.textContent = text;
      } else if (persist) {
        element.textContent = '';
      } else {
        element.textContent = '';
      }
    }

    this.fieldErrorMessages[name] = text;

    if (input) {
      if (text) {
        input.setAttribute('aria-invalid', 'true');
      } else {
        input.removeAttribute('aria-invalid');
      }
    }

    if (text && text !== previous) {
      var label = this.fieldLabels[name];
      var announcement = label ? label + ': ' + text : text;
      this.announce(announcement, { immediate: true });
    }
  };

  FormController.prototype.setBanner = function setBanner(type, message, options) {
    if (options === void 0) {
      options = {};
    }

    if (!this.bannerElement) {
      return;
    }

    window.clearTimeout(this.bannerTimer);
    this.bannerTimer = null;

    var element = this.bannerElement;
    element.classList.remove('form__banner--error', 'form__banner--success', 'form__banner--info');

    if (!message) {
      element.textContent = '';
      element.hidden = true;
      return;
    }

    element.textContent = message;
    element.hidden = false;

    if (type) {
      element.classList.add('form__banner--' + type);
    }

    if (options.autoHide) {
      var self = this;
      this.bannerTimer = window.setTimeout(function () {
        self.setBanner(null, null);
      }, options.duration || 2500);
    }
  };

  FormController.prototype.clearBanner = function clearBanner() {
    this.setBanner(null, null);
  };

  FormController.prototype.isFormValid = function isFormValid() {
    var allLengthsValid = LENGTH_FIELDS.every(
      function (name) {
        return this.values.lengths[name] != null;
      }.bind(this)
    );

    if (!allLengthsValid) {
      return false;
    }

    if (this.values.shelves == null) {
      return false;
    }

    if (this.values.partitions.mode === 'even') {
      if (this.values.partitions.count == null) {
        return false;
      }
    }

    if (this.values.partitions.mode === 'positions') {
      if (!this.values.partitions.positions_mm.length) {
        return false;
      }
    }

    return true;
  };

  FormController.prototype.updateInsertButtonState = function updateInsertButtonState() {
    if (!this.insertButton) {
      return;
    }

    this.insertButton.disabled = this.isSubmitting || this.isPlacing || !this.isFormValid();
  };

  FormController.prototype.setPlacingState = function setPlacingState(active, options) {
    var isActive = !!active;
    var payload = options && typeof options === 'object' ? options : {};
    var keepSecondaryAction = payload.keepSecondaryAction === true;
    this.isPlacing = isActive;
    this.cancelPending = false;

    if (isActive) {
      if (!keepSecondaryAction) {
        this.setSecondaryAction('cancel-placement', this.secondaryPlacementLabel);
      }
    } else if (!keepSecondaryAction) {
      this.setSecondaryAction('cancel', this.secondaryDefaultLabel);
    }

    var message = typeof payload.message === 'string' ? payload.message.trim() : '';
    if (!message) {
      message = this.placementNotice || '';
    }

    if (this.placingIndicator) {
      if (isActive && message) {
        this.placingIndicator.textContent = message;
        this.placingIndicator.hidden = false;
      } else {
        this.placingIndicator.hidden = true;
      }
    }

    if (this.dialogRoot) {
      this.dialogRoot.classList.toggle('is-placing', isActive);
    }

    this.toggleFormDisabled(isActive);

    if (isActive) {
      this.clearBanner();
    }

    this.updateInsertButtonState();
  };

  FormController.prototype.setSecondaryAction = function setSecondaryAction(action, label) {
    if (!this.secondaryButton) {
      return;
    }

    var nextAction = typeof action === 'string' && action.trim() ? action.trim() : 'cancel';
    var text;

    if (label == null) {
      text = this.secondaryDefaultLabel;
    } else {
      text = String(label);
      if (!text.trim()) {
        text = this.secondaryDefaultLabel;
      }
    }

    this.secondaryCurrentAction = nextAction;
    this.secondaryButton.setAttribute('data-action', nextAction);
    this.secondaryButton.textContent = text;
  };

  FormController.prototype.toggleFormDisabled = function toggleFormDisabled(disabled) {
    if (!this.interactiveElements || !this.interactiveElements.length) {
      if (this.bayController) {
        this.bayController.setButtonsDisabled(disabled);
      }
      return;
    }

    var self = this;
    this.interactiveElements.forEach(function (element) {
      var originallyDisabled = self.disabledByPlacement.get(element);
      if (disabled) {
        if (!originallyDisabled) {
          element.disabled = true;
        }
      } else if (!originallyDisabled) {
        element.disabled = false;
      }
    });

    if (this.bayController) {
      this.bayController.setButtonsDisabled(disabled);
    }
  };

  FormController.prototype.buildPayload = function buildPayload() {
    var lengths = this.values.lengths;
    var partitions = this.values.partitions;

    var payload = {
      ui_version: UI_PAYLOAD_VERSION,
      width_mm: lengths.width,
      depth_mm: lengths.depth,
      height_mm: lengths.height,
      panel_thickness_mm: lengths.panel_thickness,
      toe_kick_height_mm: lengths.toe_kick_height,
      toe_kick_depth_mm: lengths.toe_kick_depth,
      toe_kick_thickness_mm:
        lengths.toe_kick_thickness != null
          ? lengths.toe_kick_thickness
          : lengths.panel_thickness,
      front: this.values.front,
      shelves: this.values.shelves,
      partition_mode: this.values.partition_mode,
      partitions: {
        mode: partitions.mode,
        bays: (partitions.bays || []).map(
          function (bay) {
            var normalized = this.normalizeBay(bay);
            return {
              mode: normalized.mode,
              shelf_count: normalized.shelf_count,
              door_mode: normalized.door_mode,
              fronts_shelves_state: {
                shelf_count:
                  normalized.fronts_shelves_state &&
                  typeof normalized.fronts_shelves_state.shelf_count === 'number'
                    ? normalized.fronts_shelves_state.shelf_count
                    : normalized.shelf_count,
                door_mode:
                  normalized.fronts_shelves_state &&
                  Object.prototype.hasOwnProperty.call(normalized.fronts_shelves_state, 'door_mode')
                    ? normalized.fronts_shelves_state.door_mode
                    : normalized.door_mode
              },
              subpartitions_state: {
                count:
                  normalized.subpartitions_state &&
                  typeof normalized.subpartitions_state.count === 'number'
                    ? normalized.subpartitions_state.count
                    : 0
              }
            };
          }.bind(this)
        )
      }
    };

    if (partitions.mode === 'even') {
      payload.partitions.count = partitions.count != null ? partitions.count : 0;
      payload.partitions.positions_mm = [];
    } else if (partitions.mode === 'positions') {
      payload.partitions.positions_mm = partitions.positions_mm.slice();
    } else {
      payload.partitions.count = 0;
      payload.partitions.positions_mm = [];
    }

    if (payload.partition_mode === 'none') {
      payload.partitions.mode = 'none';
      payload.partitions.count = 0;
      payload.partitions.positions_mm = [];
    }

    if (this.mode === 'edit') {
      payload.scope = this.scope === 'all' ? 'all' : 'instance';
    }

    return payload;
  };

  FormController.prototype.handleSubmit = function handleSubmit() {
    if (this.isPlacing) {
      return;
    }

    if (this.isSubmitting) {
      return;
    }

    if (!this.isFormValid()) {
      this.setBanner('error', 'Resolve validation errors before continuing.');
      return;
    }

    var sketchupBridgeAvailable =
      window.sketchup && typeof window.sketchup.aicb_submit_params === 'function';

    if (!sketchupBridgeAvailable) {
      this.setBanner('error', 'SketchUp bridge is unavailable.');
      return;
    }

    var payload;
    try {
      payload = JSON.stringify(this.buildPayload());
    } catch (error) {
      this.setBanner('error', 'Unable to serialize the parameter payload.');
      return;
    }

    this.clearBanner();
    this.isSubmitting = true;
    this.updateInsertButtonState();
    invokeSketchUp('aicb_submit_params', payload);
  };

  FormController.prototype.handleSubmitAck = function handleSubmitAck(ack) {
    this.isSubmitting = false;
    this.updateInsertButtonState();

    if (!ack || typeof ack !== 'object') {
      this.setBanner('error', 'SketchUp returned an unexpected response.');
      return;
    }

    if (ack.ok) {
      if (ack.placement) {
        this.clearBanner();
      } else {
        this.setBanner('success', 'Parameters sent to SketchUp.', { autoHide: true });
      }
      return;
    }

    var error = ack.error || {};
    if (error.field) {
      this.applyAckFieldError(error.field, error.message);
    }

    var message = error.message || 'SketchUp reported an error.';
    this.setBanner('error', message);
  };

  FormController.prototype.applyAckFieldError = function applyAckFieldError(fieldKey, message) {
    var mapped = ACK_FIELD_TO_INPUT[fieldKey];
    if (!mapped) {
      return;
    }

    var input = this.inputs[mapped];
    if (!input) {
      return;
    }

    this.touched[mapped] = true;
    var text = message || 'Please update this value.';
    this.setFieldError(mapped, text, true);
    input.setAttribute('data-invalid', 'true');
    if (typeof input.focus === 'function') {
      input.focus();
    }
  };

  function parseNonNegativeInteger(value) {
    var text = String(value == null ? '' : value).trim();
    if (!text) {
      return { ok: false, error: 'Enter a whole number.' };
    }

    if (!/^\d+$/.test(text)) {
      return { ok: false, error: 'Enter a whole number.' };
    }

    var number = parseInt(text, 10);
    if (number < 0) {
      return { ok: false, error: 'Value must be zero or greater.' };
    }

    return { ok: true, value: number };
  }

  namespace.bootstrap = function bootstrap(settings) {
    if (controller) {
      controller.setUnits(settings);
    } else {
      pendingUnitSettings = settings;
    }
  };

  namespace.configure = function configure(options) {
    var normalized = normalizeConfiguration(options);
    if (controller) {
      controller.configureMode(normalized);
    } else {
      pendingConfiguration = normalized;
    }
  };

  namespace.applyDefaults = function applyDefaults(defaults) {
    if (controller) {
      controller.applyDefaults(defaults);
    } else {
      pendingDefaults = defaults;
    }
  };

  namespace.state_init = function state_init(payload) {
    var data = parsePayload(payload);
    if (!data || typeof data !== 'object') {
      return;
    }

    if (controller) {
      controller.applyBayStateInit(data);
    } else {
      pendingBayState = pendingBayState ? Object.assign({}, pendingBayState, data) : data;
    }
  };

  namespace.state_bays_changed = function state_bays_changed(payload) {
    var data = parsePayload(payload);
    if (!data || typeof data !== 'object') {
      return;
    }

    if (controller) {
      controller.applyBayStateInit(data);
    } else {
      pendingBayState = pendingBayState ? Object.assign({}, pendingBayState, data) : data;
    }
  };

  namespace.state_update_visibility = function state_update_visibility(payload) {
    var flags = parsePayload(payload);
    if (!flags || typeof flags !== 'object') {
      return;
    }

    if (controller) {
      controller.applyUiVisibility(flags);
    } else {
      if (!pendingBayState) {
        pendingBayState = {};
      }
      pendingBayState.ui = flags;
    }
  };

  namespace.state_update_bay = function state_update_bay(index, bayPayload) {
    var bay = parsePayload(bayPayload);
    if (controller) {
      controller.updateBayFromSketchUp(index, bay);
      return;
    }

    if (!pendingBayState) {
      pendingBayState = { bays: [] };
    }
    if (!Array.isArray(pendingBayState.bays)) {
      pendingBayState.bays = [];
    }
    pendingBayState.bays[index] = bay;
  };

  namespace.state_set_double_validity = function state_set_double_validity(index, payload) {
    var data = parsePayload(payload);
    if (controller) {
      controller.applyDoubleValidity(index, data);
      return;
    }

    pendingBayValidity.push({ index: index, payload: data });
  };

  namespace.toast = function toast(message) {
    if (controller) {
      controller.showToast(message);
    } else if (message) {
      pendingToasts.push(message);
    }
  };

  insertFormNamespace.onSubmitAck = function onSubmitAck(ack) {
    if (controller) {
      controller.handleSubmitAck(ack);
    }
  };

  namespace.beginPlacement = function beginPlacement(options) {
    var payload = options && typeof options === 'object' ? options : {};
    if (controller) {
      controller.setPlacingState(true, payload);
      requestSketchUpFocus();
    } else {
      pendingPlacementEvents.push({ type: 'begin', options: payload, shouldBlur: true });
    }
  };

  namespace.finishPlacement = function finishPlacement(options) {
    var payload = options && typeof options === 'object' ? options : {};
    if (controller) {
      handlePlacementFinish(payload);
    } else {
      pendingPlacementEvents.push({ type: 'finish', options: payload });
    }
  };

  function handleButtonClick(event) {
    var target = event.target;
    if (!(target instanceof HTMLButtonElement)) {
      return;
    }

    if (target.disabled) {
      return;
    }

    var action = target.getAttribute('data-action');
    if (!action) {
      return;
    }

    if (action === 'insert') {
      if (controller) {
        controller.handleSubmit();
      }
      return;
    }

    if (action === 'cancel-placement') {
      invokeSketchUp('cancel_placement');
      return;
    }

    if (action === 'close') {
      invokeSketchUp('cancel');
      return;
    }

    invokeSketchUp(action);
  }

  function handleDialogKeyDown(event) {
    if (!event) {
      return;
    }

    var isEscape = false;
    if (event.key === 'Escape' || event.key === 'Esc') {
      isEscape = true;
    } else if (event.keyCode === 27) {
      isEscape = true;
    }

    if (!isEscape) {
      return;
    }

    if (!controller || !controller.isPlacing) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    if (controller.cancelPending) {
      return;
    }

    controller.cancelPending = true;
    invokeSketchUp('cancel_placement');
  }

  function handlePlacementFinish(options) {
    if (!controller) {
      return;
    }

    var payload = {};
    if (options && typeof options === 'object') {
      Object.keys(options).forEach(function (key) {
        payload[key] = options[key];
      });
    }
    payload.keepSecondaryAction = true;

    controller.setPlacingState(false, payload);
    controller.cancelPending = false;

    var status = options && typeof options.status === 'string' ? options.status.toLowerCase() : '';
    var message = options && typeof options.message === 'string' ? options.message : '';

    if (status === 'error' && message) {
      controller.setBanner('error', message);
      return;
    }

    if (status === 'placed') {
      controller.setSecondaryAction('close', controller.secondaryCloseLabel);
    } else {
      controller.setSecondaryAction('cancel', controller.secondaryDefaultLabel);
    }

    controller.clearBanner();
    restoreDialogFocus();
  }

  function normalizeConfiguration(options) {
    var normalized = {
      mode: 'insert',
      scope: 'instance',
      scopeDefault: 'instance',
      selection: null,
      selectionProvided: false,
      placementNotice: ''
    };
    if (!options || typeof options !== 'object') {
      return normalized;
    }

    if (options.mode === 'edit') {
      normalized.mode = 'edit';
    }

    if (options.scope_default === 'all' || options.scope_default === 'definition') {
      normalized.scopeDefault = 'all';
    }

    if (options.scope === 'all' || options.scope === 'definition') {
      normalized.scope = 'all';
    } else if (options.scope === 'instance') {
      normalized.scope = 'instance';
    } else {
      normalized.scope = normalized.scopeDefault;
    }

    if (normalized.mode === 'edit') {
      normalized.selectionProvided = !!options.selection;
      normalized.selection = normalizeSelection(options.selection);
    } else {
      normalized.scope = 'instance';
      normalized.scopeDefault = 'instance';
      normalized.selection = null;
      normalized.selectionProvided = false;
    }

    if (options && typeof options.placement_notice === 'string') {
      normalized.placementNotice = options.placement_notice;
    }

    return normalized;
  }

  function normalizeSelection(selection) {
    var normalized = defaultSelectionInfo();
    if (!selection || typeof selection !== 'object') {
      return normalized;
    }

    var countValue = selection.instances_count;
    if (countValue == null) {
      countValue = selection.instancesCount;
    }
    countValue = Number(countValue);
    if (isFinite(countValue)) {
      normalized.instancesCount = Math.max(0, Math.round(countValue));
    }

    var nameValue = selection.definition_name;
    if (nameValue == null) {
      nameValue = selection.definitionName;
    }
    if (typeof nameValue === 'string') {
      var trimmed = nameValue.trim();
      normalized.definitionName = trimmed ? trimmed : null;
    }

    var sharesValue = selection.shares_definition;
    if (sharesValue == null) {
      sharesValue = selection.sharesDefinition;
    }
    if (typeof sharesValue === 'boolean') {
      normalized.sharesDefinition = sharesValue;
    } else {
      normalized.sharesDefinition = normalized.instancesCount > 1;
    }

    return normalized;
  }

  function initialize() {
    var form = document.querySelector('[data-role="insert-form"]');
    if (!form) {
      return;
    }

    controller = new FormController(form);
    namespace.controller = controller;
    if (pendingConfiguration) {
      controller.configureMode(pendingConfiguration);
      pendingConfiguration = null;
    } else {
      controller.configureMode({
        mode: 'insert',
        scope: 'instance',
        scopeDefault: 'instance',
        selection: null
      });
    }
    if (pendingUnitSettings) {
      controller.setUnits(pendingUnitSettings);
      pendingUnitSettings = null;
    }
    if (pendingDefaults) {
      controller.applyDefaults(pendingDefaults);
      pendingDefaults = null;
    }

    if (pendingPlacementEvents.length) {
      pendingPlacementEvents.forEach(function (event) {
        if (event.type === 'begin') {
          controller.setPlacingState(true, event.options);
          if (event.shouldBlur) {
            requestSketchUpFocus();
          }
        } else if (event.type === 'finish') {
          handlePlacementFinish(event.options);
        }
      });
      pendingPlacementEvents = [];
    }

    if (pendingBayState) {
      controller.applyBayStateInit(pendingBayState);
      pendingBayState = null;
    }

    if (pendingBayValidity.length) {
      pendingBayValidity.forEach(function (entry) {
        controller.applyDoubleValidity(entry.index, entry.payload);
      });
      pendingBayValidity = [];
    }

    if (pendingToasts.length) {
      pendingToasts.forEach(function (message) {
        controller.showToast(message);
      });
      pendingToasts = [];
    }

    invokeSketchUp('dialog_ready');
    invokeSketchUp('request_defaults');
    invokeSketchUp('ui_init_ready');

    if (testSupport.enabled && testSupport.readyResolve) {
      var resolve = testSupport.readyResolve;
      testSupport.readyResolve = null;
      resolve(collectState());
      invokeSketchUp('__aicabinets_test_boot', 'app-ready');
    }
  }

  if (testSupport.enabled) {
    window.AICabinetsTest = buildTestApi();
  }

  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('click', handleButtonClick);
  document.addEventListener('keydown', handleDialogKeyDown, true);
  window.addEventListener('unload', function () {
    controller = null;
  });
})();
