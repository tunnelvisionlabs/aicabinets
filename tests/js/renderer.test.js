const fs = require('fs');
const path = require('path');

const RENDERER_PATH = path.resolve(__dirname, '../../aicabinets/html/layout_preview/renderer.js');
const FIXTURES_PATH = path.resolve(__dirname, 'fixtures');

function loadRenderer() {
  if (window.LayoutPreview && typeof window.LayoutPreview.render === 'function') {
    return;
  }
  const source = fs.readFileSync(RENDERER_PATH, 'utf8');
  window.eval(source);
}

function loadFixture(name) {
  const filePath = path.join(FIXTURES_PATH, name);
  const raw = fs.readFileSync(filePath, 'utf8');
  return JSON.parse(raw);
}

const NUMERIC_ATTRS = new Set([
  'x',
  'y',
  'width',
  'height',
  'x1',
  'x2',
  'y1',
  'y2',
  'cx',
  'cy',
  'rx',
  'ry',
  'stroke-width',
  'strokeWidth'
]);

function roundNumeric(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return String(value);
  }
  const fixed = Number(numeric.toFixed(3));
  return Number.isFinite(fixed) ? String(fixed) : String(value);
}

function sanitizeAttributeValue(name, value) {
  if (NUMERIC_ATTRS.has(name)) {
    return roundNumeric(value);
  }
  if (name === 'viewBox') {
    return value
      .trim()
      .split(/[\s,]+/)
      .filter(Boolean)
      .map(roundNumeric)
      .join(' ');
  }
  if (name === 'transform') {
    return value.replace(/-?\d*\.?\d+/g, (match) => roundNumeric(match));
  }
  return value;
}

function sanitizeForSnapshot(element) {
  const lines = [];
  const indent = (level) => '  '.repeat(level);

  const visit = (node, depth) => {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent.trim();
      if (text) {
        lines.push(`${indent(depth)}${text}`);
      }
      return;
    }

    if (node.nodeType !== Node.ELEMENT_NODE) {
      return;
    }

    const tag = node.tagName.toLowerCase();
    const attributePairs = Array.from(node.attributes)
      .map((attr) => ({ name: attr.name, value: sanitizeAttributeValue(attr.name, attr.value) }))
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
      .map((attr) => `${attr.name}="${attr.value}"`);

    const open = attributePairs.length ? `<${tag} ${attributePairs.join(' ')}>` : `<${tag}>`;
    const children = Array.from(node.childNodes).filter((child) => {
      if (child.nodeType === Node.TEXT_NODE) {
        return child.textContent.trim().length > 0;
      }
      return true;
    });

    if (children.length === 0) {
      lines.push(`${indent(depth)}${open}</${tag}>`);
      return;
    }

    if (
      children.length === 1 &&
      children[0].nodeType === Node.TEXT_NODE &&
      children[0].textContent.trim().length > 0
    ) {
      const text = children[0].textContent.trim();
      lines.push(`${indent(depth)}${open}${text}</${tag}>`);
      return;
    }

    lines.push(`${indent(depth)}${open}`);
    children.forEach((child) => visit(child, depth + 1));
    lines.push(`${indent(depth)}</${tag}>`);
  };

  visit(element, 0);
  return lines.join('\n');
}

describe('LayoutPreview renderer', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
    loadRenderer();
  });

  it('renders expected svg structure for the canonical three-bay layout', () => {
    const model = loadFixture('layout_3bay.json');
    const container = document.createElement('div');
    document.body.appendChild(container);

    const controller = window.LayoutPreview.render(container, model);
    expect(controller).toBeTruthy();

    const svg = container.querySelector('svg');
    expect(svg).not.toBeNull();
    expect(svg.getAttribute('preserveAspectRatio')).toBe('xMidYMid meet');

    const viewBox = svg.getAttribute('viewBox');
    expect(viewBox).toBe('0 0 762 762');

    const scene = svg.querySelector('g.lp-scene');
    expect(scene).not.toBeNull();
    expect(scene.querySelector('g.lp-outer')).not.toBeNull();
    expect(scene.querySelector('g.lp-bays')).not.toBeNull();
    expect(scene.querySelector('g.lp-fronts')).not.toBeNull();

    const bayGroups = scene.querySelectorAll('g.lp-bays [data-role="bay"]');
    expect(bayGroups).toHaveLength(3);

    const offsets = Array.from(bayGroups).map((group) => {
      const rect = group.querySelector('rect');
      return rect ? Number(rect.getAttribute('x')) : NaN;
    });
    expect(offsets).toEqual([0, 254, 508]);

    const snapshot = sanitizeForSnapshot(svg);
    expect(snapshot).toMatchInlineSnapshot(`
"<svg aria-hidden="true" class="lp-svg" focusable="false" preserveAspectRatio="xMidYMid meet" viewBox="0 0 762 762">
  <title>Cabinet layout preview</title>
  <g class="lp-scene" transform="matrix(0.9 0 0 0.9 38.1 38.1)">
    <g class="lp-outer">
      <title>Outer shell</title>
      <rect height="762" rx="9.144" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" width="762" x="0" y="0"></rect>
    </g>
    <g class="lp-bays">
      <title>Bays</title>
      <g aria-label="Bay 1, 2 shelfs" aria-selected="false" data-h-mm="762" data-id="bay-left" data-index="0" data-role="bay" data-shelf-count="2" data-w-mm="254" role="group">
        <rect height="762" rx="12.7" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" width="254" x="0" y="0"></rect>
        <title>Bay 1</title>
      </g>
      <g aria-label="Bay 2" aria-selected="false" data-h-mm="762" data-id="bay-center" data-index="1" data-role="bay" data-w-mm="254" role="group">
        <rect height="762" rx="12.7" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" width="254" x="254" y="0"></rect>
        <title>Bay 2</title>
      </g>
      <g aria-label="Bay 3, 1 shelf" aria-selected="false" data-h-mm="762" data-id="bay-right" data-index="2" data-role="bay" data-shelf-count="1" data-w-mm="254" role="group">
        <rect height="762" rx="12.7" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" width="254" x="508" y="0"></rect>
        <title>Bay 3</title>
      </g>
    </g>
    <g class="lp-shelves" data-layer="shelves">
      <title>Shelves</title>
      <g data-bay-id="bay-left" data-role="bay-shelves">
        <line data-index="0" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" x1="18" x2="236" y1="254" y2="254"></line>
        <line data-index="1" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" x1="18" x2="236" y1="508" y2="508"></line>
      </g>
      <g data-bay-id="bay-right" data-role="bay-shelves">
        <line data-index="0" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" x1="526" x2="744" y1="381" y2="381"></line>
      </g>
    </g>
    <g class="lp-partitions-v" data-layer="partitions-v">
      <title>Vertical partitions</title>
      <line data-index="0" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" x1="254" x2="254" y1="0" y2="762"></line>
      <line data-index="1" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" x1="508" x2="508" y1="0" y2="762"></line>
    </g>
    <g class="lp-partitions-h" data-layer="partitions-h">
      <title>Horizontal partitions</title>
    </g>
    <g class="lp-fronts">
      <title>Fronts</title>
      <g data-front="door" data-id="front-left" data-role="front" data-style="doors_left">
        <rect class="lp-front-rect" height="762" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" width="254" x="0" y="0"></rect>
        <line class="lp-door-hinge" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" x1="20" x2="20" y1="30" y2="732"></line>
      </g>
      <g data-front="drawer_group" data-id="front-center" data-role="front">
        <rect class="lp-front-rect" height="762" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" width="254" x="254" y="0"></rect>
      </g>
      <g data-front="door" data-id="front-right" data-role="front" data-style="doors_right">
        <rect class="lp-front-rect" height="762" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" width="254" x="508" y="0"></rect>
        <line class="lp-door-hinge" shape-rendering="geometricPrecision" vector-effect="non-scaling-stroke" x1="742" x2="742" y1="30" y2="732"></line>
      </g>
    </g>
  </g>
</svg>"
`);

    if (controller && typeof controller.destroy === 'function') {
      controller.destroy();
    }
  });
});
