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

  var root = (window.AICabinets = window.AICabinets || {});
  var uiRoot = (root.UI = root.UI || {});
  var namespace = (uiRoot.InsertBaseCabinet = uiRoot.InsertBaseCabinet || {});
  var insertFormNamespace = (uiRoot.InsertForm = uiRoot.InsertForm || {});

  var controller = null;
  var pendingUnitSettings = null;
  var pendingDefaults = null;
  var pendingConfiguration = null;

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
    this.touched = {};
    this.values = {
      lengths: {},
      front: 'empty',
      shelves: 0,
      partitions: {
        mode: 'none',
        count: 0,
        positions_mm: []
      }
    };
    this.values.lengths.toe_kick_thickness = null;

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
    this.primaryActionLabel = MODE_COPY.insert.primaryLabel;

    this.initializeElements();
    this.bindEvents();
    this.updatePartitionMode('none');
    this.updateInsertButtonState();
  }

  FormController.prototype.initializeElements = function initializeElements() {
    var self = this;
    LENGTH_FIELDS.forEach(function (name) {
      var input = self.form.querySelector('[name="' + name + '"]');
      self.inputs[name] = input;
      self.errorElements[name] = self.form.querySelector('[data-error-for="' + name + '"]');
      self.values.lengths[name] = null;
      self.touched[name] = false;
    });

    INTEGER_FIELDS.forEach(function (name) {
      self.inputs[name] = self.form.querySelector('[name="' + name + '"]');
      self.errorElements[name] = self.form.querySelector('[data-error-for="' + name + '"]');
      self.touched[name] = false;
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

    if (this.inputs.shelves) {
      this.inputs.shelves.value = '0';
      this.values.shelves = 0;
    }

    if (this.inputs.front) {
      this.values.front = this.inputs.front.value;
    }
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
        self.handlePartitionModeChange(event.target.value);
        self.touched.partitions_mode = true;
        self.setFieldError('partitions_mode', null, true);
        event.target.removeAttribute('data-invalid');
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

    if (defaults.partitions && typeof defaults.partitions === 'object') {
      var partitions = defaults.partitions;
      var mode = typeof partitions.mode === 'string' ? partitions.mode : null;

      if (mode) {
        if (this.inputs.partitions_mode) {
          this.inputs.partitions_mode.value = mode;
        }
        this.values.partitions.mode = mode;
        this.updatePartitionMode(mode);
      }

      var count = partitions.count;
      if (typeof count !== 'number') {
        count = Number(count);
      }
      if (!isFinite(count)) {
        count = mode === 'even' ? null : 0;
      } else {
        count = Math.max(0, Math.round(count));
      }

      this.values.partitions.count = count;
      if (this.inputs.partitions_count) {
        if (mode === 'even' && count != null) {
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
      if (mode === 'positions') {
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

      this.setFieldError('partitions_positions', null, true);
      this.touched.partitions_positions = false;
    }

    this.updateInsertButtonState();
  };

  FormController.prototype.configureMode = function configureMode(options) {
    if (options === void 0) {
      options = {};
    }

    var mode = options.mode === 'edit' ? 'edit' : 'insert';
    this.mode = mode;

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
      var selection = options.selection && typeof options.selection === 'object'
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
      if (!hasCount) {
        return 'controls';
      }

      var normalized = Math.max(0, Math.round(count));
      if (normalized === 1) {
        return 'note';
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
      }

      if (!showControls && this.scopeHint) {
        this.scopeHint.textContent = '';
        this.scopeHint.hidden = true;
      }

      if (this.scopeNote) {
        this.scopeNote.hidden = !showNote;
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
    }
  };

  FormController.prototype.handlePartitionModeChange = function handlePartitionModeChange(mode) {
    this.values.partitions.mode = mode;
    this.updatePartitionMode(mode);
    this.updateInsertButtonState();
  };

  FormController.prototype.updatePartitionMode = function updatePartitionMode(mode) {
    if (this.partitionsEvenField) {
      this.partitionsEvenField.classList.toggle('is-hidden', mode !== 'even');
    }

    if (this.partitionsPositionsField) {
      this.partitionsPositionsField.classList.toggle('is-hidden', mode !== 'positions');
    }

    if (mode === 'even') {
      this.values.partitions.count = null;
      if (this.inputs.partitions_count) {
        this.inputs.partitions_count.value = '';
        this.inputs.partitions_count.removeAttribute('data-invalid');
      }
      this.setFieldError('partitions_count', null, true);
      this.touched.partitions_count = false;
    } else {
      this.values.partitions.count = 0;
      if (this.inputs.partitions_count) {
        this.inputs.partitions_count.value = '';
        this.inputs.partitions_count.removeAttribute('data-invalid');
      }
      this.setFieldError('partitions_count', null, true);
      this.touched.partitions_count = false;
    }

    if (mode !== 'positions') {
      this.values.partitions.positions_mm = [];
      if (this.inputs.partitions_positions) {
        this.inputs.partitions_positions.value = '';
        this.inputs.partitions_positions.removeAttribute('data-invalid');
      }
      this.setFieldError('partitions_positions', null, true);
      this.touched.partitions_positions = false;
    }
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
    if (!element) {
      return;
    }

    if (message) {
      element.textContent = message;
    } else if (persist) {
      element.textContent = '';
    } else {
      element.textContent = '';
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

    this.insertButton.disabled = this.isSubmitting || !this.isFormValid();
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
      partitions: {
        mode: partitions.mode
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

    if (this.mode === 'edit') {
      payload.scope = this.scope === 'all' ? 'all' : 'instance';
    }

    return payload;
  };

  FormController.prototype.handleSubmit = function handleSubmit() {
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
      this.setBanner('success', 'Parameters sent to SketchUp.', { autoHide: true });
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

  insertFormNamespace.onSubmitAck = function onSubmitAck(ack) {
    if (controller) {
      controller.handleSubmitAck(ack);
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

    invokeSketchUp(action);
  }

  function normalizeConfiguration(options) {
    var normalized = {
      mode: 'insert',
      scope: 'instance',
      scopeDefault: 'instance',
      selection: null
    };
    if (!options || typeof options !== 'object') {
      return normalized;
    }

    if (options.mode === 'edit') {
      normalized.mode = 'edit';
    }

    if (options.scope_default === 'all') {
      normalized.scopeDefault = 'all';
    }

    if (options.scope === 'all') {
      normalized.scope = 'all';
    } else if (options.scope === 'instance') {
      normalized.scope = 'instance';
    } else {
      normalized.scope = normalized.scopeDefault;
    }

    if (normalized.mode === 'edit') {
      normalized.selection = normalizeSelection(options.selection);
    } else {
      normalized.scope = 'instance';
      normalized.scopeDefault = 'instance';
      normalized.selection = null;
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

    invokeSketchUp('dialog_ready');
    invokeSketchUp('request_defaults');
  }

  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('click', handleButtonClick);
  window.addEventListener('unload', function () {
    controller = null;
  });
})();
