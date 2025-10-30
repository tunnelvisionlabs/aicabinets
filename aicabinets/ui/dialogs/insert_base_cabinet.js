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
  var pendingUnitSettings = null;
  var pendingDefaults = null;
  var pendingConfiguration = null;
  var pendingPlacementEvents = [];
  var pendingBayState = null;
  var pendingBayValidity = [];
  var pendingToasts = [];

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

  function BayController(options) {
    options = options || {};

    this.root = options.root || null;
    this.onSelect = typeof options.onSelect === 'function' ? options.onSelect : function () {};
    this.onShelfChange =
      typeof options.onShelfChange === 'function' ? options.onShelfChange : function () {};
    this.onDoorChange =
      typeof options.onDoorChange === 'function' ? options.onDoorChange : function () {};
    this.onApplyToAll =
      typeof options.onApplyToAll === 'function' ? options.onApplyToAll : function () {};
    this.onCopyLeftToRight =
      typeof options.onCopyLeftToRight === 'function' ? options.onCopyLeftToRight : function () {};
    this.onRequestValidity =
      typeof options.onRequestValidity === 'function' ? options.onRequestValidity : function () {};
    this.announceCallback =
      typeof options.onAnnounce === 'function' ? options.onAnnounce : function () {};
    this.translate = typeof options.translate === 'function' ? options.translate : translate;

    this.selectedIndex = 0;
    this.bays = [];
    this.doubleValidity = [];
    this.template = { shelf_count: 0, door_mode: null };
    this.shelfLock = false;
    this.doorLock = false;

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
      this.doorFieldset = null;
      this.doorLegend = null;
      this.doorInputs = [];
      this.doubleDoorInput = null;
      this.hint = null;
      this.applyAllButton = null;
      this.copyButton = null;
      this.statusRegion = null;
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
    this.statusRegion = this.root.querySelector('[data-role="bay-status"]');
  };

  BayController.prototype.initializeText = function initializeText() {
    if (!this.root) {
      return;
    }

    if (this.sectionTitle) {
      this.sectionTitle.textContent = this.translate('bay_section_title');
    }
    if (this.selector) {
      this.selector.setAttribute('aria-label', this.translate('bay_selector_label'));
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
    if (this.statusRegion) {
      this.statusRegion.setAttribute('aria-label', this.translate('live_region_title'));
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
  };

  BayController.prototype.renderChips = function renderChips() {
    if (!this.chipsContainer) {
      return;
    }

    var self = this;
    this.chipsContainer.innerHTML = '';
    this.chipButtons = [];

    this.bays.forEach(function (_bay, index) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'bay-chip';
      button.textContent = self.translate('bay_chip_label', { index: index + 1 });
      button.setAttribute('data-index', String(index));
      button.setAttribute('aria-pressed', index === self.selectedIndex ? 'true' : 'false');
      button.tabIndex = index === self.selectedIndex ? 0 : -1;
      button.addEventListener('click', function () {
        self.setSelectedIndex(index, { emit: true, focus: true });
      });
      button.addEventListener('keydown', function (event) {
        self.handleChipKeyDown(event, index);
      });
      self.chipsContainer.appendChild(button);
      self.chipButtons.push(button);
    });

    this.updateActionsVisibility();
    this.announce(this.translate('bay_count_status', { count: this.bays.length }));
  };

  BayController.prototype.handleChipKeyDown = function handleChipKeyDown(event, index) {
    if (!event) {
      return;
    }

    var key = event.key || event.keyCode;
    var handled = false;
    if (key === 'ArrowRight' || key === 'Right' || key === 39) {
      this.focusChip(index + 1);
      handled = true;
    } else if (key === 'ArrowLeft' || key === 'Left' || key === 37) {
      this.focusChip(index - 1);
      handled = true;
    } else if (key === 'Home' || key === 36) {
      this.focusChip(0);
      handled = true;
    } else if (key === 'End' || key === 35) {
      this.focusChip(this.bays.length - 1);
      handled = true;
    }

    if (handled) {
      event.preventDefault();
      event.stopPropagation();
    }
  };

  BayController.prototype.focusChip = function focusChip(index) {
    if (!this.chipButtons || !this.chipButtons.length) {
      return;
    }

    var clamped = Math.max(0, Math.min(index, this.chipButtons.length - 1));
    var button = this.chipButtons[clamped];
    if (!button) {
      return;
    }

    this.setSelectedIndex(clamped, { emit: true, focus: true });
  };

  BayController.prototype.setSelectedIndex = function setSelectedIndex(index, options) {
    if (index == null || index < 0 || index >= this.bays.length) {
      return;
    }

    options = options || {};
    var previous = this.selectedIndex;
    this.selectedIndex = index;

    if (this.chipButtons) {
      this.chipButtons.forEach(function (button, buttonIndex) {
        var pressed = buttonIndex === index ? 'true' : 'false';
        button.setAttribute('aria-pressed', pressed);
        button.tabIndex = buttonIndex === index ? 0 : -1;
      });
      if (options.focus && this.chipButtons[index] && typeof this.chipButtons[index].focus === 'function') {
        this.chipButtons[index].focus();
      }
    }

    this.updateShelfControls();
    this.updateDoorControls();

    this.announce(
      this.translate('bay_selection_status', { index: index + 1, total: this.bays.length })
    );

    if (options.emit && index !== previous) {
      this.onSelect(index);
    }

    this.requestValidity();
  };

  BayController.prototype.updateShelfControls = function updateShelfControls() {
    if (!this.shelfInput) {
      return;
    }

    var bay = this.bays[this.selectedIndex] || { shelf_count: 0 };
    var value = typeof bay.shelf_count === 'number' ? bay.shelf_count : 0;
    this.shelfLock = true;
    this.shelfInput.value = String(value);
    this.shelfLock = false;
  };

  BayController.prototype.updateDoorControls = function updateDoorControls() {
    var bay = this.bays[this.selectedIndex] || { door_mode: null };
    var mode = bay.door_mode;
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
    this.applyDoubleValidityState();
  };

  BayController.prototype.setBays = function setBays(bays, options) {
    options = options || {};
    this.bays = Array.isArray(bays) ? bays.slice() : [];
    this.template = this.bays.length ? cloneBay(this.bays[0]) : { shelf_count: 0, door_mode: null };
    var desiredIndex = options.selectedIndex != null ? options.selectedIndex : this.selectedIndex;
    desiredIndex = Math.max(0, Math.min(desiredIndex, this.bays.length - 1));
    this.selectedIndex = desiredIndex;
    this.renderChips();
    this.setSelectedIndex(desiredIndex, { emit: options.emit === true });
  };

  function cloneBay(bay) {
    if (!bay || typeof bay !== 'object') {
      return { shelf_count: 0, door_mode: null };
    }

    return {
      shelf_count: typeof bay.shelf_count === 'number' ? bay.shelf_count : 0,
      door_mode: bay.door_mode == null ? null : bay.door_mode
    };
  }

  BayController.prototype.setBayValue = function setBayValue(index, bay) {
    if (index < 0 || index >= this.bays.length) {
      return;
    }

    this.bays[index] = cloneBay(bay);
    if (index === this.selectedIndex) {
      this.updateShelfControls();
      this.updateDoorControls();
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

  BayController.prototype.applyDoubleValidityState = function applyDoubleValidityState() {
    if (!this.doubleDoorInput) {
      return;
    }

    var validity = this.doubleValidity[this.selectedIndex];
    if (!validity) {
      this.doubleDoorInput.disabled = false;
      this.clearHint();
      return;
    }

    if (validity.allowed) {
      this.doubleDoorInput.disabled = false;
      this.clearHint();
      return;
    }

    this.doubleDoorInput.disabled = true;
    var current = this.bays[this.selectedIndex] || {};
    if (current.door_mode === 'doors_double') {
      this.handleDoorChange('none');
    }
    this.showHint(validity.reason || this.translate('door_mode_double_disabled_hint'));
  };

  BayController.prototype.setDoubleValidity = function setDoubleValidity(index, allowed, reason) {
    this.doubleValidity[index] = { allowed: !!allowed, reason: reason || null };
    if (index === this.selectedIndex) {
      this.applyDoubleValidityState();
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
    this.onRequestValidity(this.selectedIndex);
  };

  BayController.prototype.updateActionsVisibility = function updateActionsVisibility() {
    if (this.copyButton) {
      this.copyButton.hidden = this.bays.length < 2;
    }
  };

  BayController.prototype.announce = function announce(message) {
    if (!message) {
      return;
    }
    if (this.statusRegion) {
      this.statusRegion.textContent = message;
    }
    this.announceCallback(message);
  };

  BayController.prototype.setButtonsDisabled = function setButtonsDisabled(disabled) {
    if (this.decreaseButton) {
      this.decreaseButton.disabled = disabled;
    }
    if (this.increaseButton) {
      this.increaseButton.disabled = disabled;
    }
    if (this.shelfInput) {
      this.shelfInput.disabled = disabled;
    }
    this.doorInputs.forEach(function (input) {
      input.disabled = disabled;
    });
    if (this.applyAllButton) {
      this.applyAllButton.disabled = disabled;
    }
    if (this.copyButton) {
      this.copyButton.disabled = disabled || this.bays.length < 2;
    }
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
    this.touched = {};
    this.values = {
      lengths: {},
      front: 'empty',
      shelves: 0,
      partitions: {
        mode: 'none',
        count: 0,
        positions_mm: [],
        bays: []
      }
    };
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
    this.bayTemplate = { shelf_count: 0, door_mode: null };

    this.initializeElements();
    this.bindEvents();
    this.updatePartitionMode('none');
    this.updateInsertButtonState();
    this.setSecondaryAction('cancel', this.secondaryDefaultLabel);

    this.bayController = new BayController({
      root: form.querySelector('[data-role="bay-controls"]'),
      onSelect: this.handleBaySelection.bind(this),
      onShelfChange: this.handleBayShelfChange.bind(this),
      onDoorChange: this.handleBayDoorChange.bind(this),
      onApplyToAll: this.handleApplyBayToAll.bind(this),
      onCopyLeftToRight: this.handleCopyLeftToRight.bind(this),
      onRequestValidity: this.handleRequestBayValidity.bind(this),
      onAnnounce: this.handleBayAnnouncement.bind(this)
    });
  }

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

  FormController.prototype.normalizeBay = function normalizeBay(bay) {
    var shelf = 0;
    var door = null;
    if (bay && typeof bay === 'object') {
      if (typeof bay.shelf_count === 'number' && isFinite(bay.shelf_count)) {
        shelf = Math.max(0, Math.round(bay.shelf_count));
      }
      if (typeof bay.door_mode === 'string' && bay.door_mode.trim()) {
        door = bay.door_mode.trim();
      } else if (bay.door_mode === null) {
        door = null;
      }
    }

    return { shelf_count: shelf, door_mode: door };
  };

  FormController.prototype.setBayArray = function setBayArray(bays, options) {
    var sanitized = Array.isArray(bays)
      ? bays.map(this.normalizeBay, this)
      : [this.normalizeBay(this.bayTemplate)];
    if (!sanitized.length) {
      sanitized = [this.normalizeBay(this.bayTemplate)];
    }

    this.values.partitions.bays = sanitized;
    this.bayTemplate = cloneBay(sanitized[0]);
    this.selectedBayIndex = Math.max(0, Math.min(this.selectedBayIndex, sanitized.length - 1));

    if (this.bayController) {
      this.bayController.setBays(sanitized.map(cloneBay), {
        selectedIndex:
          options && typeof options.selectedIndex === 'number'
            ? options.selectedIndex
            : this.selectedBayIndex,
        emit: options && options.emit === true
      });
    }
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
    this.selectedBayIndex = Math.max(0, Math.min(this.selectedBayIndex, bays.length - 1));
    if (this.bayController) {
      this.bayController.setBays(bays.map(cloneBay), {
        selectedIndex: this.selectedBayIndex
      });
    }
  };

  FormController.prototype.handleBaySelection = function handleBaySelection(index) {
    if (typeof index !== 'number' || !isFinite(index)) {
      return;
    }

    var bays = this.values.partitions.bays || [];
    if (!bays.length) {
      return;
    }

    this.selectedBayIndex = Math.max(0, Math.min(index, bays.length - 1));
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
    bays[index].shelf_count = numeric;
    this.bayTemplate.shelf_count = bays[0] ? bays[0].shelf_count : numeric;
    if (this.bayController) {
      this.bayController.setBayValue(index, bays[index]);
    }
    this.updateInsertButtonState();
    this.sendBayShelfUpdate(index, numeric);
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
    bays[index].door_mode = normalized;
    if (index === 0) {
      this.bayTemplate.door_mode = normalized;
    }
    if (this.bayController) {
      this.bayController.setBayValue(index, bays[index]);
    }
    this.updateInsertButtonState();
    this.sendBayDoorUpdate(index, normalized);
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

  FormController.prototype.handleBayAnnouncement = function handleBayAnnouncement(message) {
    if (!message) {
      return;
    }
    this.announce(message);
  };

  FormController.prototype.sendBayShelfUpdate = function sendBayShelfUpdate(index, value) {
    var payload = { index: index, value: value };
    invokeSketchUp('ui_set_shelf_count', JSON.stringify(payload));
  };

  FormController.prototype.sendBayDoorUpdate = function sendBayDoorUpdate(index, value) {
    var payload = { index: index, value: value };
    invokeSketchUp('ui_set_door_mode', JSON.stringify(payload));
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
    this.updateInsertButtonState();
  };

  FormController.prototype.applyBayStateInit = function applyBayStateInit(state) {
    if (!state || typeof state !== 'object') {
      return;
    }

    if (state.partitions && typeof state.partitions.count === 'number') {
      var count = Math.max(0, Math.round(state.partitions.count));
      this.values.partitions.count = count;
    }

    if (state.partitions && Array.isArray(state.partitions.positions_mm)) {
      this.values.partitions.positions_mm = state.partitions.positions_mm.slice();
    }

    var bays = Array.isArray(state.bays) ? state.bays : [];
    var selected = this.selectedBayIndex;
    if (typeof state.selected_index === 'number' && isFinite(state.selected_index)) {
      selected = Math.max(0, Math.round(state.selected_index));
      this.selectedBayIndex = selected;
    }

    this.setBayArray(bays, { selectedIndex: selected });
    this.ensureBayLength();

    if (Array.isArray(state.can_double)) {
      state.can_double.forEach(
        function (entry, index) {
          if (!entry || typeof entry !== 'object') {
            return;
          }
          this.applyDoubleValidity(index, entry.allowed, entry.reason);
        }.bind(this)
      );
    }
  };

  FormController.prototype.applyDoubleValidity = function applyDoubleValidity(index, allowed, reason) {
    if (this.bayController) {
      this.bayController.setDoubleValidity(index, !!allowed, reason || null);
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

      var baysArray = Array.isArray(partitions.bays) ? partitions.bays : [];
      this.setBayArray(baysArray, { selectedIndex: 0 });

      this.setFieldError('partitions_positions', null, true);
      this.touched.partitions_positions = false;
    } else {
      this.setBayArray([], { selectedIndex: 0 });
    }

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
    }
  };

  FormController.prototype.handlePartitionModeChange = function handlePartitionModeChange(mode) {
    this.values.partitions.mode = mode;
    this.updatePartitionMode(mode);
    this.ensureBayLength();
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
      partitions: {
        mode: partitions.mode,
        bays: (partitions.bays || []).map(
          function (bay) {
            var normalized = this.normalizeBay(bay);
            return {
              shelf_count: normalized.shelf_count,
              door_mode: normalized.door_mode
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
      pendingBayState = data;
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

  namespace.state_set_double_validity = function state_set_double_validity(index, allowed, reason) {
    if (controller) {
      controller.applyDoubleValidity(index, allowed, reason);
      return;
    }

    pendingBayValidity.push({ index: index, allowed: allowed, reason: reason });
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
        controller.applyDoubleValidity(entry.index, entry.allowed, entry.reason);
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
  }

  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('click', handleButtonClick);
  document.addEventListener('keydown', handleDialogKeyDown, true);
  window.addEventListener('unload', function () {
    controller = null;
  });
})();
