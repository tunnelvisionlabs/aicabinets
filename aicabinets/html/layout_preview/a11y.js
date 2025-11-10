(function () {
  'use strict';

  var stateMap = new WeakMap();
  var registry = [];

  function init(root, options) {
    if (!root || typeof root.querySelectorAll !== 'function') {
      return null;
    }

    var state = stateMap.get(root);
    if (!state) {
      state = createState(root, options || {});
      stateMap.set(root, state);
      registry.push(state);
      installListeners(state);
    } else if (options && typeof options.unitLabel === 'function') {
      state.unitLabel = options.unitLabel;
    }

    refresh(state);

    return state.api;
  }

  function setActiveBay(bayId, root) {
    var normalized = normalizeBayId(bayId);
    pruneRegistry();

    for (var index = 0; index < registry.length; index += 1) {
      var state = registry[index];
      if (!state || state.destroyed) {
        continue;
      }
      if (root && state.root !== root) {
        continue;
      }

      state.activeId = normalized;
      syncFocusedAnchors(state);
      updateAriaSelected(state);
      updateRovingTabindex(state);
    }
  }

  function createState(root, options) {
    var state = {
      root: root,
      unitLabel: typeof options.unitLabel === 'function' ? options.unitLabel : null,
      bays: [],
      activeId: null,
      focusedId: null,
      rovingId: null,
      destroyed: false,
      hasFocusWithin: false,
      api: null,
      handlers: null
    };

    if (!root.hasAttribute('tabindex')) {
      root.setAttribute('tabindex', '0');
    }

    state.api = {
      updateBays: function updateBays() {
        refresh(state);
      }
    };

    return state;
  }

  function installListeners(state) {
    if (!state || !state.root) {
      return;
    }

    var focusInHandler = function handleFocusIn(event) {
      if (!state || state.destroyed) {
        return;
      }
      if (!state.root.contains(event.target)) {
        return;
      }

      if (event.target === state.root) {
        state.hasFocusWithin = true;
        queueFocusToAnchor(state);
        return;
      }

      var entry = findEntryByNode(state, event.target);
      if (!entry) {
        return;
      }

      state.hasFocusWithin = true;
      state.focusedId = entry.id;
      state.rovingId = entry.id;
      addFocusClass(state, entry.node);
      updateRovingTabindex(state);
    };

    var focusOutHandler = function handleFocusOut(event) {
      if (!state || state.destroyed) {
        return;
      }

      if (event.target && state.root.contains(event.target)) {
        removeFocusClass(state, event.target);
      }

      var nextTarget = event.relatedTarget;
      if (nextTarget && state.root.contains(nextTarget)) {
        return;
      }

      state.hasFocusWithin = false;
      state.focusedId = null;
      updateRovingTabindex(state);
    };

    var keyHandler = function handleKeydown(event) {
      if (!state || state.destroyed) {
        return;
      }

      if (!state.root.contains(event.target)) {
        return;
      }

      handleKeyNavigation(state, event);
    };

    state.handlers = {
      focusin: focusInHandler,
      focusout: focusOutHandler,
      keydown: keyHandler
    };

    state.root.addEventListener('focusin', focusInHandler, true);
    state.root.addEventListener('focusout', focusOutHandler, true);
    state.root.addEventListener('keydown', keyHandler, false);
  }

  function refresh(state) {
    if (!state || !state.root) {
      return;
    }
    if (state.destroyed) {
      return;
    }
    if (!state.root.isConnected) {
      state.destroyed = true;
      return;
    }

    var nodes = state.root.querySelectorAll('[data-role="bay"]');
    var bays = [];
    for (var index = 0; index < nodes.length; index += 1) {
      var node = nodes[index];
      bays.push(buildBayEntry(node, index));
    }
    state.bays = bays;

    reconcileFocusTargets(state);
    updateLabels(state);
    updateAriaSelected(state);
    updateRovingTabindex(state);
  }

  function buildBayEntry(node, index) {
    var id = normalizeBayId(node.getAttribute('data-id'));
    if (!id) {
      id = normalizeBayId(node.getAttribute('data-index'));
    }
    if (!id) {
      id = String(index);
    }

    var width = parseFloat(node.getAttribute('data-w-mm'));
    var height = parseFloat(node.getAttribute('data-h-mm'));

    if (!Number.isFinite(width)) {
      width = null;
    }
    if (!Number.isFinite(height)) {
      height = null;
    }

    return {
      id: id,
      index: index,
      width: width,
      height: height,
      node: node
    };
  }

  function reconcileFocusTargets(state) {
    if (!state.bays || state.bays.length === 0) {
      state.focusedId = null;
      state.rovingId = null;
      return;
    }

    if (state.focusedId && !findEntryById(state, state.focusedId)) {
      state.focusedId = null;
    }

    if (state.rovingId && !findEntryById(state, state.rovingId)) {
      state.rovingId = null;
    }

    if (!state.rovingId) {
      var activeEntry = state.activeId ? findEntryById(state, state.activeId) : null;
      state.rovingId = activeEntry ? activeEntry.id : state.bays[0].id;
    }
  }

  function updateLabels(state) {
    for (var index = 0; index < state.bays.length; index += 1) {
      var entry = state.bays[index];
      if (!entry || !entry.node) {
        continue;
      }

      var label = buildBayLabel(state, entry);
      if (label) {
        entry.node.setAttribute('aria-label', label);
      }
      entry.node.setAttribute('role', 'group');
      entry.node.setAttribute('tabindex', '-1');
      entry.node.setAttribute('aria-selected', 'false');
    }
  }

  function buildBayLabel(state, entry) {
    var ordinal = entry.index + 1;
    var widthText = formatMeasurement(state, entry.width);
    var heightText = formatMeasurement(state, entry.height);
    var shelfCount = parseShelfCount(entry.node);
    var shelfText = buildShelfText(shelfCount);

    var label;
    if (!widthText || !heightText) {
      label = 'Bay ' + String(ordinal);
    } else {
      var suffix = state.unitLabel ? '' : ' millimeters';
      label = 'Bay ' + String(ordinal) + ', ' + widthText + ' by ' + heightText + suffix;
    }

    if (shelfText) {
      label += ', ' + shelfText;
    }

    return label;
  }

  function formatMeasurement(state, value) {
    if (state.unitLabel) {
      try {
        var formatted = state.unitLabel(value);
        if (typeof formatted === 'string' && formatted.trim().length) {
          return formatted.trim();
        }
      } catch (error) {
        // Fall back to millimeters formatting if custom formatter throws.
      }
    }

    if (!Number.isFinite(value)) {
      return '';
    }

    var fixed = Number(value).toFixed(3);
    return fixed.replace(/\.0+$/, '').replace(/(\.\d*[1-9])0+$/, '$1');
  }

  function parseShelfCount(node) {
    if (!node || typeof node.getAttribute !== 'function') {
      return 0;
    }
    var attr = node.getAttribute('data-shelf-count');
    if (!attr) {
      return 0;
    }
    var count = parseInt(attr, 10);
    return Number.isFinite(count) && count > 0 ? count : 0;
  }

  function buildShelfText(count) {
    if (!Number.isFinite(count) || count <= 0) {
      return '';
    }
    return String(count) + ' shelf' + (count === 1 ? '' : 's');
  }

  function updateAriaSelected(state) {
    for (var index = 0; index < state.bays.length; index += 1) {
      var entry = state.bays[index];
      if (!entry || !entry.node) {
        continue;
      }
      var selected = state.activeId !== null && entry.id === state.activeId;
      entry.node.setAttribute('aria-selected', selected ? 'true' : 'false');
    }
  }

  function updateRovingTabindex(state) {
    if (!state.root) {
      return;
    }

    if (!state.bays || state.bays.length === 0) {
      state.root.setAttribute('tabindex', '0');
      return;
    }

    state.root.setAttribute('tabindex', '-1');

    var anchorId = state.focusedId || state.rovingId;
    if (anchorId && !findEntryById(state, anchorId)) {
      anchorId = null;
    }
    if (!anchorId) {
      var activeEntry = state.activeId ? findEntryById(state, state.activeId) : null;
      anchorId = activeEntry ? activeEntry.id : state.bays[0].id;
    }

    var anchorFound = false;
    for (var index = 0; index < state.bays.length; index += 1) {
      var entry = state.bays[index];
      if (!entry || !entry.node) {
        continue;
      }
      var value = entry.id === anchorId ? '0' : '-1';
      entry.node.setAttribute('tabindex', value);
      if (value === '0') {
        anchorFound = true;
        state.rovingId = entry.id;
      }
    }

    if (!anchorFound && state.bays.length > 0) {
      var first = state.bays[0];
      first.node.setAttribute('tabindex', '0');
      state.rovingId = first.id;
    }
  }

  function queueFocusToAnchor(state) {
    if (!state.bays || state.bays.length === 0) {
      return;
    }

    var target = state.activeId ? findEntryById(state, state.activeId) : null;
    if (!target) {
      target = state.rovingId ? findEntryById(state, state.rovingId) : null;
    }
    if (!target) {
      target = state.bays[0];
    }
    if (!target) {
      return;
    }

    state.focusedId = target.id;
    state.rovingId = target.id;
    updateRovingTabindex(state);

    focusEntry(state, target);
  }

  function focusEntry(state, entry) {
    if (!entry || !entry.node) {
      return false;
    }

    state.focusedId = entry.id;
    state.rovingId = entry.id;
    updateRovingTabindex(state);
    addFocusClass(state, entry.node);

    if (typeof entry.node.focus === 'function') {
      try {
        entry.node.focus({ preventScroll: true });
      } catch (error) {
        entry.node.focus();
      }
    }
    return true;
  }

  function handleKeyNavigation(state, event) {
    var key = event.key;

    if (typeof key !== 'string') {
      return;
    }

    if (!state.bays || state.bays.length === 0) {
      return;
    }

    var entry = findEntryByNode(state, event.target);
    if (!entry) {
      entry = state.focusedId ? findEntryById(state, state.focusedId) : null;
      if (!entry) {
        entry = state.rovingId ? findEntryById(state, state.rovingId) : state.bays[0];
      }
    }

    if (!entry) {
      return;
    }

    if (key === 'ArrowRight') {
      event.preventDefault();
      focusByOffset(state, entry.index, 1);
      return;
    }
    if (key === 'ArrowLeft') {
      event.preventDefault();
      focusByOffset(state, entry.index, -1);
      return;
    }
    if (key === 'Home') {
      event.preventDefault();
      focusByIndex(state, 0);
      return;
    }
    if (key === 'End') {
      event.preventDefault();
      focusByIndex(state, state.bays.length - 1);
      return;
    }
    if (key === 'Enter' || key === ' ' || key === 'Spacebar' || key === 'Space') {
      event.preventDefault();
      dispatchSelect(entry);
    }
  }

  function focusByOffset(state, startIndex, delta) {
    var nextIndex = startIndex + delta;
    if (nextIndex < 0) {
      nextIndex = 0;
    }
    if (nextIndex >= state.bays.length) {
      nextIndex = state.bays.length - 1;
    }
    focusByIndex(state, nextIndex);
  }

  function focusByIndex(state, index) {
    if (index < 0 || index >= state.bays.length) {
      return;
    }
    var target = state.bays[index];
    focusEntry(state, target);
  }

  function dispatchSelect(entry) {
    if (!entry || !entry.node) {
      return;
    }

    var event;
    try {
      event = new MouseEvent('click', { bubbles: true, cancelable: true });
    } catch (error) {
      event = document.createEvent('MouseEvents');
      event.initEvent('click', true, true);
    }
    entry.node.dispatchEvent(event);
  }

  function findEntryByNode(state, node) {
    if (!node || !state || !state.bays) {
      return null;
    }

    for (var index = 0; index < state.bays.length; index += 1) {
      var entry = state.bays[index];
      if (entry && entry.node === node) {
        return entry;
      }
    }
    return null;
  }

  function findEntryById(state, id) {
    if (!state || !state.bays || !id) {
      return null;
    }

    for (var index = 0; index < state.bays.length; index += 1) {
      var entry = state.bays[index];
      if (entry && entry.id === id) {
        return entry;
      }
    }
    return null;
  }

  function addFocusClass(state, node) {
    if (!node || typeof node.classList === 'undefined') {
      return;
    }
    node.classList.add('is-focused');
  }

  function removeFocusClass(state, node) {
    if (!node || typeof node.classList === 'undefined') {
      return;
    }
    node.classList.remove('is-focused');
  }

  function syncFocusedAnchors(state) {
    if (state.hasFocusWithin) {
      var focusedEntry = state.focusedId ? findEntryById(state, state.focusedId) : null;
      if (focusedEntry) {
        state.rovingId = focusedEntry.id;
        return;
      }
    }

    if (state.activeId && findEntryById(state, state.activeId)) {
      state.rovingId = state.activeId;
      return;
    }

    if (state.bays && state.bays.length > 0 && !state.rovingId) {
      state.rovingId = state.bays[0].id;
    }
  }

  function pruneRegistry() {
    for (var index = registry.length - 1; index >= 0; index -= 1) {
      var state = registry[index];
      if (!state || !state.root || state.destroyed || !state.root.isConnected) {
        registry.splice(index, 1);
      }
    }
  }

  function normalizeBayId(value) {
    if (value === null || typeof value === 'undefined') {
      return null;
    }
    var text = String(value);
    return text.length ? text : null;
  }

  if (!window.LayoutPreview) {
    window.LayoutPreview = {};
  }

  window.LayoutPreview.a11y = {
    init: init,
    setActiveBay: setActiveBay
  };
})();
