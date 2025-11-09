(function () {
  'use strict';

  var SVG_NS = 'http://www.w3.org/2000/svg';
  var DEFAULT_OPTIONS = {
    padding_frac: 0.05,
    stroke_px: 1.5,
    hover_stroke_px: null,
    active_tint: '#1f7aec'
  };

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
      options: opts
    };

    var root = document.createElement('div');
    root.className = 'lp-root';
    root.setAttribute('role', 'img');
    root.setAttribute('aria-label', 'Cabinet front preview');
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

    update(state, layoutModel);

    return {
      update: function updateLayout(nextModel) {
        update(state, nextModel);
      },
      destroy: function destroy() {
        if (state.root && state.root.parentNode === containerEl) {
          containerEl.removeChild(state.root);
        }
        state.root = null;
        state.svg = null;
        state.scene = null;
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

    replaceChildren(state.scene, buildLayers(model));
  }

  function normalizeLayoutModel(layoutModel) {
    var outer = (layoutModel && layoutModel.outer) || {};
    var width = toPositiveNumber(outer.w_mm, 1);
    var height = toPositiveNumber(outer.h_mm, 1);

    var bays = Array.isArray(layoutModel && layoutModel.bays)
      ? layoutModel.bays
          .map(function (bay, index) {
            return normalizeRect(bay, index, 'bay');
          })
          .filter(Boolean)
      : [];

    var fronts = Array.isArray(layoutModel && layoutModel.fronts)
      ? layoutModel.fronts
          .map(function (front, index) {
            return normalizeRect(front, index, front && front.role ? String(front.role) : 'front');
          })
          .filter(Boolean)
      : [];

    return {
      outer: {
        w_mm: width,
        h_mm: height
      },
      bays: bays,
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

    return {
      id: id,
      role: role,
      index: index,
      x_mm: x,
      y_mm: y,
      w_mm: width,
      h_mm: height
    };
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

  function buildLayers(model) {
    var fragments = [];

    fragments.push(buildOuterLayer(model.outer));
    fragments.push(buildBaysLayer(model.bays));

    if (model.fronts.length) {
      fragments.push(buildFrontsLayer(model.fronts));
    }

    return fragments;
  }

  function buildOuterLayer(outer) {
    var group = createGroup('lp-outer', 'outer shell');

    var rect = createRect(0, 0, outer.w_mm, outer.h_mm);
    rect.setAttribute('rx', formatNumber(Math.min(outer.w_mm, outer.h_mm) * 0.012));
    group.appendChild(rect);

    return group;
  }

  function buildBaysLayer(bays) {
    var group = createGroup('lp-bays', 'bays');
    bays.forEach(function (bay, index) {
      var wrapper = document.createElementNS(SVG_NS, 'g');
      wrapper.setAttribute('data-role', 'bay');
      wrapper.setAttribute('data-index', String(index));
      wrapper.setAttribute('role', 'group');
      wrapper.setAttribute('aria-label', 'Bay ' + String(index + 1));
      if (bay.id) {
        wrapper.setAttribute('data-id', bay.id);
      }

      var rect = createRect(bay.x_mm, bay.y_mm, bay.w_mm, bay.h_mm);
      rect.setAttribute('rx', formatNumber(Math.min(bay.w_mm, bay.h_mm) * 0.05));
      wrapper.appendChild(rect);

      var title = document.createElementNS(SVG_NS, 'title');
      title.textContent = 'Bay ' + String(index + 1);
      wrapper.appendChild(title);

      group.appendChild(wrapper);
    });
    return group;
  }

  function buildFrontsLayer(fronts) {
    var group = createGroup('lp-fronts', 'fronts');
    fronts.forEach(function (front) {
      var rect = createRect(front.x_mm, front.y_mm, front.w_mm, front.h_mm);
      rect.setAttribute('data-role', front.role || 'front');
      group.appendChild(rect);
    });
    return group;
  }

  function createGroup(className, label) {
    var group = document.createElementNS(SVG_NS, 'g');
    group.setAttribute('class', className);
    if (label) {
      var title = document.createElementNS(SVG_NS, 'title');
      title.textContent = capitalize(label);
      group.appendChild(title);
    }
    return group;
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

  function replaceChildren(node, children) {
    while (node.firstChild) {
      node.removeChild(node.firstChild);
    }
    children.forEach(function (child) {
      if (child) {
        node.appendChild(child);
      }
    });
  }

  window.LayoutPreview = {
    render: render
  };
})();
