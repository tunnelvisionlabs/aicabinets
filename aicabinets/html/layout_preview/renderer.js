(function () {
  'use strict';

  var SVG_NS = 'http://www.w3.org/2000/svg';
  var DEFAULT_OPTIONS = {
    padding_frac: 0.05,
    stroke_px: 1.5,
    hover_stroke_px: null,
    active_tint: '#1f7aec'
  };

  var EPSILON_MM = 1.0e-3;

  function clampPadding(value) {
    if (!isFinite(value)) {
      return DEFAULT_OPTIONS.padding_frac;
    }
    if (value < 0) {
      return 0;
    }
    if (value > 0.48) {
      return 0.48;
    }
    return value;
  }

  function isFinite(value) {
    return typeof value === 'number' && Number.isFinite(value);
  }

  function mergeOptions(options) {
    var opts = Object.assign({}, DEFAULT_OPTIONS);
    if (options && typeof options === 'object') {
      if (typeof options.padding_frac === 'number') {
        opts.padding_frac = clampPadding(options.padding_frac);
      }
      if (typeof options.stroke_px === 'number' && options.stroke_px > 0) {
        opts.stroke_px = options.stroke_px;
      }
      if (typeof options.hover_stroke_px === 'number' && options.hover_stroke_px > 0) {
        opts.hover_stroke_px = options.hover_stroke_px;
      }
      if (typeof options.active_tint === 'string' && options.active_tint) {
        opts.active_tint = options.active_tint;
      }
    }

    if (!isFinite(opts.hover_stroke_px) || opts.hover_stroke_px <= 0) {
      opts.hover_stroke_px = opts.stroke_px * 1.5;
    }

    return opts;
  }

  var moduleState = {
    activeState: null,
    requestHandler: null
  };

  function render(containerEl, layoutModel, options) {
    if (!containerEl || typeof containerEl !== 'object') {
      throw new Error('LayoutPreview.render requires a container element.');
    }

    var opts = mergeOptions(options);

    var state = {
      container: containerEl,
      root: null,
      svg: null,
      scene: null,
      options: opts,
      activeBayId: null,
      activeScope: 'all',
      selectionGuardId: null,
      selectionGuardTimer: null,
      handleBayClick: null,
      layers: null,
      a11yHandle: null,
      a11yOptions: options && options.a11y ? options.a11y : null
    };

    var root = document.createElement('div');
    root.className = 'lp-root';
    root.setAttribute('role', 'img');
    root.setAttribute('aria-label', 'Cabinet front preview');
    root.setAttribute('tabindex', '0');
    applyCssVariables(root, opts);

    var svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('class', 'lp-svg');
    svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
    svg.setAttribute('focusable', 'false');
    svg.setAttribute('aria-hidden', 'true');

    var title = document.createElementNS(SVG_NS, 'title');
    title.textContent = 'Cabinet layout preview';
    svg.appendChild(title);

    var scene = document.createElementNS(SVG_NS, 'g');
    scene.setAttribute('class', 'lp-scene');
    svg.appendChild(scene);

    root.appendChild(svg);

    while (containerEl.firstChild) {
      containerEl.removeChild(containerEl.firstChild);
    }
    containerEl.appendChild(root);

    state.root = root;
    state.svg = svg;
    state.scene = scene;

    state.handleBayClick = function handleBayClick(event) {
      onRootClick(state, event);
    };
    root.addEventListener('click', state.handleBayClick, false);

    update(state, layoutModel);

    moduleState.activeState = state;

    return {
      update: function updateLayout(nextModel) {
        update(state, nextModel);
      },
      setActiveBay: function setActiveBayForController(bayId, opts) {
        return setActiveBayForState(state, bayId, opts);
      },
      destroy: function destroy() {
        if (state.root) {
          if (state.handleBayClick) {
            state.root.removeEventListener('click', state.handleBayClick, false);
          }
          if (state.root.parentNode === containerEl) {
            containerEl.removeChild(state.root);
          }
        }
        clearSelectionGuard(state);
        state.root = null;
        state.svg = null;
        state.scene = null;
        state.handleBayClick = null;
        state.layers = null;
        if (moduleState.activeState === state) {
          moduleState.activeState = null;
        }
      }
    };
  }

  function applyCssVariables(root, opts) {
    root.style.setProperty('--lp-stroke-px', formatPixelValue(opts.stroke_px));
    root.style.setProperty('--lp-hover-stroke-px', formatPixelValue(opts.hover_stroke_px));
    root.style.setProperty('--lp-active-color', opts.active_tint);
  }

  function formatPixelValue(value) {
    var numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric <= 0) {
      numeric = DEFAULT_OPTIONS.stroke_px;
    }
    return numeric + 'px';
  }

  function update(state, layoutModel) {
    if (!state.root || !state.svg || !state.scene) {
      return;
    }

    var model = normalizeLayoutModel(layoutModel);

    state.svg.setAttribute('viewBox', '0 0 ' + formatNumber(model.outer.w_mm) + ' ' + formatNumber(model.outer.h_mm));

    applyPaddingTransform(state.scene, model.outer, state.options.padding_frac);

    var layers = ensureSceneLayers(state);
    updateOuterLayer(layers.outer, model.outer);
    var shelfCounts = buildShelfCounts(model.shelves);
    updateBaysLayer(layers.bays, model.bays, shelfCounts);
    updateShelvesLayer(layers.shelves, model.shelves, model.bays);
    updatePartitionsLayer(layers.partitionsV, model.partitions, model.outer, 'vertical');
    updatePartitionsLayer(layers.partitionsH, model.partitions, model.outer, 'horizontal');
    updateFrontsLayer(layers.fronts, model.fronts);

    applyA11yBindings(state);
    applyActiveBayState(state);
  }

  function ensureSceneLayers(state) {
    if (!state.layers) {
      state.layers = {
        outer: ensureLayer(state.scene, 'lp-outer', 'outer shell'),
        bays: ensureLayer(state.scene, 'lp-bays', 'bays'),
        shelves: ensureLayer(state.scene, 'lp-shelves', 'shelves', { 'data-layer': 'shelves' }),
        partitionsV: ensureLayer(state.scene, 'lp-partitions-v', 'vertical partitions', {
          'data-layer': 'partitions-v'
        }),
        partitionsH: ensureLayer(state.scene, 'lp-partitions-h', 'horizontal partitions', {
          'data-layer': 'partitions-h'
        }),
        fronts: ensureLayer(state.scene, 'lp-fronts', 'fronts')
      };
    }
    return state.layers;
  }

  function ensureLayer(scene, className, label, attributes) {
    if (!scene) {
      return null;
    }

    var selector = 'g.' + className;
    var layer = scene.querySelector(selector);
    if (!layer) {
      layer = createGroup(className, label, attributes);
      scene.appendChild(layer);
    }
    return layer;
  }

  function normalizeLayoutModel(layoutModel) {
    var outer = (layoutModel && layoutModel.outer) || {};
    var width = toPositiveNumber(outer.w_mm, 1);
    var height = toPositiveNumber(outer.h_mm, 1);

    var normalizedOuter = {
      w_mm: width,
      h_mm: height
    };

    var bays = Array.isArray(layoutModel && layoutModel.bays)
      ? layoutModel.bays
          .map(function (bay, index) {
            return normalizeRect(bay, index, 'bay');
          })
          .filter(Boolean)
      : [];

    var partitions = normalizePartitions(layoutModel && layoutModel.partitions, normalizedOuter);
    var shelves = normalizeShelves(layoutModel && layoutModel.shelves);

    var fronts = Array.isArray(layoutModel && layoutModel.fronts)
      ? layoutModel.fronts
          .map(function (front, index) {
            return normalizeRect(front, index, front && front.role ? String(front.role) : 'front');
          })
          .filter(Boolean)
      : [];

    return {
      outer: normalizedOuter,
      bays: bays,
      partitions: partitions,
      shelves: shelves,
      fronts: fronts
    };
  }

  function normalizeRect(data, index, fallbackRole) {
    if (!data || typeof data !== 'object') {
      return null;
    }

    var width = toPositiveNumber(data.w_mm, null);
    var height = toPositiveNumber(data.h_mm, null);
    if (width === null || height === null) {
      return null;
    }

    var x = toNumber(data.x_mm, 0);
    var y = toNumber(data.y_mm, 0);
    var id = data.id != null ? String(data.id) : null;
    var role = data.role ? String(data.role) : fallbackRole;

    var style = null;
    if (data && Object.prototype.hasOwnProperty.call(data, 'style')) {
      style = data.style != null ? String(data.style) : null;
    }

    return {
      id: id,
      role: role,
      index: index,
      x_mm: x,
      y_mm: y,
      w_mm: width,
      h_mm: height,
      style: style
    };
  }

  function normalizePartitions(rawPartitions, outer) {
    var data = rawPartitions && typeof rawPartitions === 'object' ? rawPartitions : null;
    var orientation = 'vertical';
    if (data && typeof data.orientation === 'string') {
      var candidate = data.orientation.toLowerCase();
      orientation = candidate === 'horizontal' ? 'horizontal' : 'vertical';
    }

    var positions = Array.isArray(data && data.positions_mm)
      ? data.positions_mm
          .map(function (value) {
            return Number(value);
          })
          .filter(function (value) {
            return Number.isFinite(value);
          })
      : [];

    positions.sort(function (a, b) {
      return a - b;
    });

    var axisLimit = orientation === 'horizontal' ? outer.h_mm : outer.w_mm;
    var normalized = [];
    var last = null;
    for (var index = 0; index < positions.length; index += 1) {
      var clamped = clampAxisPosition(positions[index], axisLimit);
      if (clamped === null) {
        continue;
      }
      if (last !== null && Math.abs(clamped - last) <= EPSILON_MM) {
        continue;
      }
      normalized.push(clamped);
      last = clamped;
    }

    return {
      orientation: orientation,
      positions_mm: normalized
    };
  }

  function normalizeShelves(rawShelves) {
    if (!Array.isArray(rawShelves)) {
      return [];
    }

    return rawShelves
      .map(function (entry) {
        if (!entry || typeof entry !== 'object') {
          return null;
        }

        var bayId = null;
        if (Object.prototype.hasOwnProperty.call(entry, 'bay_id')) {
          bayId = entry.bay_id;
        } else if (Object.prototype.hasOwnProperty.call(entry, 'bayId')) {
          bayId = entry.bayId;
        }

        if (bayId != null) {
          bayId = String(bayId);
        } else {
          bayId = null;
        }

        var y = Number(entry.y_mm);
        if (!Number.isFinite(y)) {
          return null;
        }

        return {
          bay_id: bayId,
          y_mm: y
        };
      })
      .filter(function (entry) {
        return entry !== null && Number.isFinite(entry.y_mm);
      });
  }

  function clampAxisPosition(value, axisLimit) {
    var numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      return null;
    }

    if (axisLimit > 0) {
      if (numeric < 0) {
        numeric = 0;
      }
      if (numeric > axisLimit) {
        numeric = axisLimit;
      }
      if (numeric <= EPSILON_MM || Math.abs(axisLimit - numeric) <= EPSILON_MM) {
        return null;
      }
    }

    return numeric;
  }

  function toNumber(value, fallback) {
    var number = Number(value);
    if (Number.isFinite(number)) {
      return number;
    }
    return fallback;
  }

  function toPositiveNumber(value, fallback) {
    var number = Number(value);
    if (Number.isFinite(number) && number > 0) {
      return number;
    }
    return fallback;
  }

  function applyPaddingTransform(scene, outer, paddingFrac) {
    var padding = clampPadding(Number(paddingFrac));
    var scale = 1 - padding * 2;
    if (!(scale > 0)) {
      scale = 0.01;
    }

    var translateX = outer.w_mm * padding;
    var translateY = outer.h_mm * padding;
    var matrix = 'matrix(' + formatNumber(scale) + ' 0 0 ' + formatNumber(scale) + ' ' + formatNumber(translateX) + ' ' + formatNumber(translateY) + ')';

    if (padding <= 0) {
      matrix = 'matrix(1 0 0 1 0 0)';
    }

    scene.setAttribute('transform', matrix);
  }

  function updateOuterLayer(group, outer) {
    if (!group) {
      return;
    }

    var rect = group.querySelector('rect');
    if (!rect) {
      rect = createRect(0, 0, outer.w_mm, outer.h_mm);
      group.appendChild(rect);
    }

    rect.setAttribute('x', '0');
    rect.setAttribute('y', '0');
    rect.setAttribute('width', formatNumber(outer.w_mm));
    rect.setAttribute('height', formatNumber(outer.h_mm));
    rect.setAttribute('rx', formatNumber(Math.min(outer.w_mm, outer.h_mm) * 0.012));
  }

  function updateBaysLayer(group, bays, shelfCounts) {
    if (!group) {
      return;
    }

    var existing = group.querySelectorAll('[data-role="bay"]');
    if (existing.length !== bays.length) {
      rebuildBays(group, bays, shelfCounts);
      return;
    }

    for (var index = 0; index < bays.length; index += 1) {
      var bay = bays[index];
      var wrapper = existing[index];
      if (!wrapper) {
        continue;
      }

      wrapper.setAttribute('data-index', String(index));
      var fallbackId = 'bay-' + String(index + 1);
      wrapper.setAttribute('data-id', bay.id || fallbackId);
      wrapper.setAttribute('role', 'group');
      wrapper.setAttribute('data-w-mm', formatNumber(bay.w_mm));
      wrapper.setAttribute('data-h-mm', formatNumber(bay.h_mm));

      var shelfCount = resolveShelfCount(shelfCounts, bay, fallbackId);
      applyShelfMetadata(wrapper, index, shelfCount);

      var rect = wrapper.querySelector('rect');
      if (!rect) {
        rect = createRect(bay.x_mm, bay.y_mm, bay.w_mm, bay.h_mm);
        wrapper.appendChild(rect);
      }

      rect.setAttribute('x', formatNumber(bay.x_mm));
      rect.setAttribute('y', formatNumber(bay.y_mm));
      rect.setAttribute('width', formatNumber(bay.w_mm));
      rect.setAttribute('height', formatNumber(bay.h_mm));
      rect.setAttribute('rx', formatNumber(Math.min(bay.w_mm, bay.h_mm) * 0.05));

      var title = wrapper.querySelector('title');
      if (!title) {
        title = document.createElementNS(SVG_NS, 'title');
        wrapper.appendChild(title);
      }
      title.textContent = 'Bay ' + String(index + 1);
    }
  }

  function rebuildBays(group, bays, shelfCounts) {
    clearLayerChildren(group);

    bays.forEach(function (bay, index) {
      var wrapper = document.createElementNS(SVG_NS, 'g');
      wrapper.setAttribute('data-role', 'bay');
      wrapper.setAttribute('data-index', String(index));
      wrapper.setAttribute('role', 'group');
      var fallbackId = 'bay-' + String(index + 1);
      wrapper.setAttribute('data-id', bay.id || fallbackId);
      wrapper.setAttribute('data-w-mm', formatNumber(bay.w_mm));
      wrapper.setAttribute('data-h-mm', formatNumber(bay.h_mm));

      var shelfCount = resolveShelfCount(shelfCounts, bay, fallbackId);
      applyShelfMetadata(wrapper, index, shelfCount);

      var rect = createRect(bay.x_mm, bay.y_mm, bay.w_mm, bay.h_mm);
      rect.setAttribute('rx', formatNumber(Math.min(bay.w_mm, bay.h_mm) * 0.05));
      wrapper.appendChild(rect);

      var title = document.createElementNS(SVG_NS, 'title');
      title.textContent = 'Bay ' + String(index + 1);
      wrapper.appendChild(title);

      group.appendChild(wrapper);
    });
  }

  function resolveShelfCount(shelfCounts, bay, fallbackId) {
    if (!shelfCounts) {
      return 0;
    }
    var key = bay.id || fallbackId;
    if (!key || !Object.prototype.hasOwnProperty.call(shelfCounts, key)) {
      return 0;
    }
    var count = Number(shelfCounts[key]);
    return Number.isFinite(count) && count > 0 ? Math.round(count) : 0;
  }

  function applyShelfMetadata(node, index, shelfCount) {
    if (!node) {
      return;
    }
    node.setAttribute('aria-label', buildInitialBayLabel(index, shelfCount));
    if (shelfCount > 0) {
      node.setAttribute('data-shelf-count', String(shelfCount));
    } else {
      node.removeAttribute('data-shelf-count');
    }
  }

  function buildInitialBayLabel(index, shelfCount) {
    var label = 'Bay ' + String(index + 1);
    if (shelfCount > 0) {
      label += ', ' + shelfCount + ' shelf' + (shelfCount === 1 ? '' : 's');
    }
    return label;
  }

  function buildShelfCounts(shelves) {
    var counts = Object.create(null);
    if (!Array.isArray(shelves)) {
      return counts;
    }

    shelves.forEach(function (entry) {
      if (!entry || typeof entry !== 'object') {
        return;
      }
      if (entry.bay_id == null) {
        return;
      }
      var key = String(entry.bay_id);
      if (!Object.prototype.hasOwnProperty.call(counts, key)) {
        counts[key] = 0;
      }
      counts[key] += 1;
    });

    return counts;
  }

  function updateShelvesLayer(group, shelves, bays) {
    if (!group) {
      return;
    }

    if (!Array.isArray(shelves) || shelves.length === 0) {
      clearLayerChildren(group);
      return;
    }

    clearLayerChildren(group);

    var bayMap = buildBayMap(bays);
    var grouped = groupShelvesByBay(shelves);

    Object.keys(grouped).forEach(function (bayId) {
      var bay = bayMap[bayId];
      if (!bay) {
        return;
      }

      var wrapper = document.createElementNS(SVG_NS, 'g');
      wrapper.setAttribute('data-role', 'bay-shelves');
      wrapper.setAttribute('data-bay-id', bayId);

      var entries = grouped[bayId].slice().sort(function (a, b) {
        return a.y_mm - b.y_mm;
      });

      for (var index = 0; index < entries.length; index += 1) {
        var shelf = entries[index];
        var y = clampShelfY(shelf.y_mm, bay);
        if (y === null) {
          continue;
        }

        var inset = Math.max(Math.min(bay.w_mm * 0.08, 18), 4);
        var startX = bay.x_mm + inset;
        var endX = bay.x_mm + bay.w_mm - inset;
        if (endX <= startX) {
          endX = bay.x_mm + bay.w_mm;
        }

        var line = document.createElementNS(SVG_NS, 'line');
        line.setAttribute('x1', formatNumber(startX));
        line.setAttribute('x2', formatNumber(endX));
        line.setAttribute('y1', formatNumber(y));
        line.setAttribute('y2', formatNumber(y));
        line.setAttribute('data-index', String(index));
        line.setAttribute('vector-effect', 'non-scaling-stroke');
        line.setAttribute('shape-rendering', 'geometricPrecision');
        wrapper.appendChild(line);
      }

      if (wrapper.childNodes.length > 0) {
        group.appendChild(wrapper);
      }
    });
  }

  function buildBayMap(bays) {
    var map = Object.create(null);
    if (!Array.isArray(bays)) {
      return map;
    }

    for (var index = 0; index < bays.length; index += 1) {
      var bay = bays[index];
      if (!bay) {
        continue;
      }
      var id = bay.id || 'bay-' + String(index + 1);
      map[id] = bay;
    }

    return map;
  }

  function groupShelvesByBay(shelves) {
    var grouped = Object.create(null);
    shelves.forEach(function (entry) {
      if (!entry || typeof entry !== 'object') {
        return;
      }
      if (entry.bay_id == null) {
        return;
      }
      var key = String(entry.bay_id);
      if (!grouped[key]) {
        grouped[key] = [];
      }
      grouped[key].push(entry);
    });
    return grouped;
  }

  function clampShelfY(value, bay) {
    var numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      return null;
    }

    var top = bay.y_mm;
    var bottom = bay.y_mm + bay.h_mm;
    if (numeric < top + EPSILON_MM) {
      numeric = top + EPSILON_MM;
    }
    if (numeric > bottom - EPSILON_MM) {
      numeric = bottom - EPSILON_MM;
    }
    return numeric;
  }

  function updatePartitionsLayer(group, partitions, outer, orientation) {
    if (!group) {
      return;
    }

    var expected = orientation === 'horizontal' ? 'horizontal' : 'vertical';
    var positions =
      partitions && partitions.orientation === expected && Array.isArray(partitions.positions_mm)
        ? partitions.positions_mm
        : [];

    if (!positions.length) {
      clearLayerChildren(group);
      return;
    }

    clearLayerChildren(group);

    var axisLimit = expected === 'horizontal' ? outer.h_mm : outer.w_mm;
    for (var index = 0; index < positions.length; index += 1) {
      var clamped = clampAxisPosition(positions[index], axisLimit);
      if (clamped === null) {
        continue;
      }

      var line = document.createElementNS(SVG_NS, 'line');
      if (expected === 'vertical') {
        line.setAttribute('x1', formatNumber(clamped));
        line.setAttribute('x2', formatNumber(clamped));
        line.setAttribute('y1', '0');
        line.setAttribute('y2', formatNumber(outer.h_mm));
      } else {
        line.setAttribute('x1', '0');
        line.setAttribute('x2', formatNumber(outer.w_mm));
        line.setAttribute('y1', formatNumber(clamped));
        line.setAttribute('y2', formatNumber(clamped));
      }
      line.setAttribute('data-index', String(index));
      line.setAttribute('vector-effect', 'non-scaling-stroke');
      line.setAttribute('shape-rendering', 'geometricPrecision');
      group.appendChild(line);
    }
  }

  function updateFrontsLayer(group, fronts) {
    if (!group) {
      return;
    }

    var existing = group.querySelectorAll('[data-role="front"]');
    if (existing.length !== fronts.length) {
      rebuildFronts(group, fronts);
      return;
    }

    for (var index = 0; index < fronts.length; index += 1) {
      var front = fronts[index];
      var wrapper = existing[index];
      if (!wrapper) {
        continue;
      }
      updateFrontNode(wrapper, front);
    }
  }

  function rebuildFronts(group, fronts) {
    clearLayerChildren(group);

    fronts.forEach(function (front) {
      var node = createFrontNode(front);
      if (node) {
        group.appendChild(node);
      }
    });
  }

  function createFrontNode(front) {
    if (!front) {
      return null;
    }

    var wrapper = document.createElementNS(SVG_NS, 'g');
    wrapper.setAttribute('data-role', 'front');
    wrapper.setAttribute('data-front', front.role || 'front');
    if (front.id) {
      wrapper.setAttribute('data-id', front.id);
    }
    if (front.role === 'door' && front.style) {
      wrapper.setAttribute('data-style', front.style);
    }

    var rect = createRect(front.x_mm, front.y_mm, front.w_mm, front.h_mm);
    rect.setAttribute('class', 'lp-front-rect');
    wrapper.appendChild(rect);

    applyDoorDecor(wrapper, front);
    return wrapper;
  }

  function updateFrontNode(wrapper, front) {
    if (!wrapper || !front) {
      return;
    }

    wrapper.setAttribute('data-front', front.role || 'front');
    if (front.id) {
      wrapper.setAttribute('data-id', front.id);
    } else {
      wrapper.removeAttribute('data-id');
    }

    if (front.role === 'door' && front.style) {
      wrapper.setAttribute('data-style', front.style);
    } else {
      wrapper.removeAttribute('data-style');
    }

    var rect = wrapper.querySelector('rect.lp-front-rect');
    if (!rect) {
      rect = createRect(front.x_mm, front.y_mm, front.w_mm, front.h_mm);
      rect.setAttribute('class', 'lp-front-rect');
      wrapper.insertBefore(rect, wrapper.firstChild);
    }

    rect.setAttribute('x', formatNumber(front.x_mm));
    rect.setAttribute('y', formatNumber(front.y_mm));
    rect.setAttribute('width', formatNumber(front.w_mm));
    rect.setAttribute('height', formatNumber(front.h_mm));

    var details = wrapper.querySelectorAll('.lp-door-hinge, .lp-door-gap');
    for (var index = 0; index < details.length; index += 1) {
      wrapper.removeChild(details[index]);
    }

    applyDoorDecor(wrapper, front);
  }

  function applyDoorDecor(wrapper, front) {
    if (!wrapper || !front || front.role !== 'door') {
      return;
    }

    var style = front.style || '';
    if (style === 'doors_left' || style === 'doors_right') {
      var hinge = document.createElementNS(SVG_NS, 'line');
      var inset = Math.max(Math.min(front.w_mm * 0.1, 20), 4);
      var x = style === 'doors_left' ? front.x_mm + inset : front.x_mm + front.w_mm - inset;
      var top = front.y_mm + Math.min(front.h_mm * 0.12, 30);
      var bottom = front.y_mm + front.h_mm - Math.min(front.h_mm * 0.12, 30);
      hinge.setAttribute('x1', formatNumber(x));
      hinge.setAttribute('x2', formatNumber(x));
      hinge.setAttribute('y1', formatNumber(top));
      hinge.setAttribute('y2', formatNumber(bottom));
      hinge.setAttribute('class', 'lp-door-hinge');
      hinge.setAttribute('vector-effect', 'non-scaling-stroke');
      hinge.setAttribute('shape-rendering', 'geometricPrecision');
      wrapper.appendChild(hinge);
      return;
    }

    if (style === 'doors_double') {
      var gap = document.createElementNS(SVG_NS, 'line');
      var center = front.x_mm + front.w_mm / 2;
      gap.setAttribute('x1', formatNumber(center));
      gap.setAttribute('x2', formatNumber(center));
      gap.setAttribute('y1', formatNumber(front.y_mm));
      gap.setAttribute('y2', formatNumber(front.y_mm + front.h_mm));
      gap.setAttribute('class', 'lp-door-gap');
      gap.setAttribute('vector-effect', 'non-scaling-stroke');
      gap.setAttribute('shape-rendering', 'geometricPrecision');
      wrapper.appendChild(gap);
    }
  }

  function createGroup(className, label, attributes) {
    var group = document.createElementNS(SVG_NS, 'g');
    group.setAttribute('class', className);
    if (attributes && typeof attributes === 'object') {
      Object.keys(attributes).forEach(function (key) {
        group.setAttribute(key, attributes[key]);
      });
    }
    if (label) {
      var title = document.createElementNS(SVG_NS, 'title');
      title.textContent = capitalize(label);
      group.appendChild(title);
    }
    return group;
  }

  function clearLayerChildren(group) {
    if (!group) {
      return;
    }

    var title = group.querySelector('title');
    while (group.firstChild) {
      group.removeChild(group.firstChild);
    }

    if (title) {
      group.appendChild(title);
    }
  }

  function capitalize(text) {
    if (typeof text !== 'string' || !text.length) {
      return '';
    }
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  function createRect(x, y, width, height) {
    var rect = document.createElementNS(SVG_NS, 'rect');
    rect.setAttribute('x', formatNumber(x));
    rect.setAttribute('y', formatNumber(y));
    rect.setAttribute('width', formatNumber(width));
    rect.setAttribute('height', formatNumber(height));
    rect.setAttribute('vector-effect', 'non-scaling-stroke');
    rect.setAttribute('shape-rendering', 'geometricPrecision');
    return rect;
  }

  function formatNumber(value) {
    var number = Number(value);
    if (!Number.isFinite(number)) {
      number = 0;
    }
    var fixed = number.toFixed(3);
    return fixed.replace(/\.0+$/, '').replace(/(\.\d*[1-9])0+$/, '$1');
  }

  function onRootClick(state, event) {
    if (!state || !state.root) {
      return;
    }

    var bayNode = findBayNode(event && event.target, state.root);
    if (!bayNode) {
      return;
    }

    var bayIdentifier = extractBayIdentifier(bayNode);
    var normalizedId = normalizeBayId(bayIdentifier);

    activateBayFromInteraction(state, normalizedId);

    if (!shouldSuppressSelectionRequest(state, normalizedId)) {
      dispatchRequestSelectBay(bayIdentifier);
    }
  }

  function activateBayFromInteraction(state, bayId) {
    if (!state) {
      return false;
    }

    state.activeBayId = bayId;
    applyActiveBayState(state);
    return true;
  }

  function setActiveBayForState(state, bayId, opts) {
    if (!state) {
      return false;
    }

    var normalizedId = normalizeBayId(bayId);
    var scope = normalizeScope(opts && opts.scope);

    if (scope) {
      state.activeScope = scope;
    }

    state.activeBayId = normalizedId;
    registerSelectionGuard(state, normalizedId);
    applyActiveBayState(state);
    return true;
  }

  function applyActiveBayState(state) {
    if (!state || !state.root) {
      return;
    }

    var root = state.root;
    var activeId = state.activeBayId;
    var scope = state.activeScope || 'all';

    if (scope === 'single') {
      root.classList.add('scope-single');
    } else {
      root.classList.remove('scope-single');
    }

    var bays = root.querySelectorAll('[data-role="bay"]');
    for (var index = 0; index < bays.length; index += 1) {
      var bayNode = bays[index];
      var nodeId = normalizeBayId(extractBayIdentifier(bayNode));
      var isActive = activeId !== null && nodeId === activeId;
      var deemphasize = scope === 'single' && activeId !== null && !isActive;
      toggleClass(bayNode, 'is-active', isActive);
      toggleClass(bayNode, 'is-deemphasized', deemphasize);
      if (isActive) {
        bayNode.setAttribute('aria-selected', 'true');
      } else {
        bayNode.setAttribute('aria-selected', 'false');
      }
    }

    notifyA11yActive(state);
  }

  function applyA11yBindings(state) {
    if (!state || !state.root) {
      return;
    }

    var module = window.LayoutPreview && window.LayoutPreview.a11y;
    if (!module || typeof module.init !== 'function') {
      return;
    }

    var options = state.a11yOptions || null;
    var handle = module.init(state.root, options || {});
    if (handle && typeof handle.updateBays === 'function') {
      handle.updateBays();
    } else if (typeof module.updateBays === 'function') {
      try {
        module.updateBays(state.root);
      } catch (error) {
        if (window.console && typeof window.console.warn === 'function') {
          window.console.warn('LayoutPreview.a11y.updateBays failed:', error);
        }
      }
    }

    state.a11yHandle = handle || state.a11yHandle || null;
  }

  function notifyA11yActive(state) {
    if (!state) {
      return;
    }

    var module = window.LayoutPreview && window.LayoutPreview.a11y;
    if (!module || typeof module.setActiveBay !== 'function') {
      return;
    }

    try {
      module.setActiveBay(state.activeBayId, state.root || null);
    } catch (error) {
      if (window.console && typeof window.console.warn === 'function') {
        window.console.warn('LayoutPreview.a11y.setActiveBay failed:', error);
      }
    }
  }

  function toggleClass(element, className, force) {
    if (!element || typeof element.classList === 'undefined') {
      return;
    }

    if (typeof element.classList.toggle === 'function') {
      element.classList.toggle(className, !!force);
      return;
    }

    if (force) {
      element.className = element.className + ' ' + className;
    } else {
      element.className = element.className.replace(new RegExp('\\b' + className + '\\b', 'g'), '').trim();
    }
  }

  function findBayNode(node, root) {
    var current = node;
    while (current && current !== root) {
      if (current.getAttribute && current.getAttribute('data-role') === 'bay') {
        return current;
      }
      current = current.parentNode;
    }
    if (current && current.getAttribute && current.getAttribute('data-role') === 'bay') {
      return current;
    }
    return null;
  }

  function extractBayIdentifier(node) {
    if (!node || typeof node.getAttribute !== 'function') {
      return null;
    }
    var identifier = node.getAttribute('data-id');
    if (identifier == null || identifier === '') {
      identifier = node.getAttribute('data-index');
    }
    return identifier;
  }

  function normalizeBayId(value) {
    if (value == null) {
      return null;
    }
    var text = String(value);
    return text.length ? text : null;
  }

  function normalizeScope(value) {
    if (value === 'single' || value === 'all') {
      return value;
    }
    if (typeof value === 'string') {
      var lowered = value.toLowerCase();
      if (lowered === 'single' || lowered === 'all') {
        return lowered;
      }
    }
    return null;
  }

  function registerSelectionGuard(state, bayId) {
    clearSelectionGuard(state);
    if (!state || bayId === null) {
      return;
    }
    state.selectionGuardId = bayId;
    state.selectionGuardTimer = window.setTimeout(function () {
      clearSelectionGuard(state);
    }, 180);
  }

  function clearSelectionGuard(state) {
    if (!state) {
      return;
    }
    if (state.selectionGuardTimer !== null) {
      window.clearTimeout(state.selectionGuardTimer);
    }
    state.selectionGuardTimer = null;
    state.selectionGuardId = null;
  }

  function shouldSuppressSelectionRequest(state, bayId) {
    if (!state) {
      return false;
    }
    if (state.selectionGuardId === null || bayId === null) {
      return false;
    }
    return state.selectionGuardId === bayId;
  }

  function dispatchRequestSelectBay(bayId) {
    var handler = moduleState.requestHandler;
    if (typeof handler === 'function') {
      try {
        handler(bayId);
        return;
      } catch (error) {
        if (window && window.console && typeof window.console.error === 'function') {
          window.console.error('LayoutPreview.onRequestSelectBay failed:', error);
        }
      }
    }

    if (window.sketchup && typeof window.sketchup.requestSelectBay === 'function') {
      try {
        window.sketchup.requestSelectBay(bayId);
      } catch (error2) {
        if (window.console && typeof window.console.warn === 'function') {
          window.console.warn('LayoutPreview.requestSelectBay bridge failed:', error2);
        }
      }
    }
  }

  window.LayoutPreview = {
    render: render,
    setActiveBay: function setActiveBayGlobal(bayId, opts) {
      if (!moduleState.activeState) {
        return false;
      }
      return setActiveBayForState(moduleState.activeState, bayId, opts);
    }
  };

  Object.defineProperty(window.LayoutPreview, 'onRequestSelectBay', {
    get: function getOnRequestSelectBay() {
      return moduleState.requestHandler;
    },
    set: function setOnRequestSelectBay(callback) {
      if (typeof callback === 'function' || callback === null) {
        moduleState.requestHandler = callback;
      }
    }
  });
})();
