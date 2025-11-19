(function () {
  var DEFAULT_MESSAGE =
    'Select a single AI Cabinets front, a tagged door part, or a cabinet that contains exactly one front.';

  var form = {
    doorStyle: document.getElementById('door-style'),
    insideProfile: document.getElementById('inside-profile'),
    stileWidth: document.getElementById('stile-width'),
    railWidth: document.getElementById('rail-width'),
    panelStyle: document.getElementById('panel-style'),
    panelThickness: document.getElementById('panel-thickness'),
    panelCoveRadius: document.getElementById('panel-cove-radius'),
    panelClearance: document.getElementById('panel-clearance'),
    grooveDepth: document.getElementById('groove-depth'),
    grooveWidth: document.getElementById('groove-width'),
    drawerRailWidth: document.getElementById('drawer-rail-width'),
    minDrawerRailWidth: document.getElementById('min-drawer-rail-width'),
    minPanelOpening: document.getElementById('min-panel-opening'),
    scopeInstance: document.getElementById('scope-instance'),
    fivePieceSection: document.getElementById('five-piece-fields'),
    drawerMessages: document.getElementById('drawer-messages'),
    banner: document.getElementById('banner'),
    targetLabel: document.getElementById('target-label'),
    chooserSection: document.getElementById('choose-front'),
    chooserMessage: document.getElementById('choose-front-message'),
    candidateList: document.getElementById('front-candidates'),
  };

  var currentMode = 'message';
  var interactiveControls = [];

  function toggleFivePieceFields() {
    var show = form.doorStyle.value !== 'slab';
    form.fivePieceSection.classList.toggle('is-hidden', !show);
    syncInsideProfileControl();
  }

  function syncInsideProfileControl() {
    if (!form.insideProfile) return;
    var fivePiece = form.doorStyle.value !== 'slab';
    var ready = currentMode === 'ready';
    if (fivePiece && !form.insideProfile.value) {
      form.insideProfile.value = 'shaker_inside';
    }
    form.insideProfile.disabled = !(ready && fivePiece);
  }

  function clearErrors() {
    var nodes = document.querySelectorAll('[data-error-for]');
    Array.prototype.forEach.call(nodes, function (node) {
      node.textContent = '';
    });
    form.banner.textContent = '';
    form.banner.className = 'banner';
    if (form.drawerMessages) {
      form.drawerMessages.textContent = '';
    }
  }

  function applyFormatted(field, value) {
    if (!value || !field) return;
    field.value = value;
  }

  function receiveState(payload) {
    clearErrors();
    var mode = (payload && payload.mode) || 'ready';

    if (mode === 'ready') {
      if (!payload || !payload.params) {
        setMode('message');
        showBanner('error', 'Unable to load fronts state.');
        return;
      }

      setMode('ready');
      renderTarget(payload.target);
      renderReadyState(payload);
      return;
    }

    if (mode === 'choose') {
      setMode('choose');
      renderChooser(payload);
      showBanner(payload.level || 'info', payload.text || DEFAULT_MESSAGE);
      return;
    }

    if (mode === 'message') {
      setMode('message');
      showBanner(payload.level || 'info', payload.text || DEFAULT_MESSAGE);
      return;
    }

    setMode('message');
    showBanner('error', 'Unable to load fronts state.');
  }

  function renderReadyState(payload) {
    var formatted = payload.formatted || {};
    var params = payload.params || {};

    form.doorStyle.value = payload.door_style || 'five_piece_cope_stick';
    toggleFivePieceFields();
    applyFormatted(form.stileWidth, formatted.stile_width || params.stile_width_mm);
    applyFormatted(form.railWidth, formatted.rail_width || '');
    applyFormatted(form.panelThickness, formatted.panel_thickness || params.panel_thickness_mm);
    applyFormatted(form.panelCoveRadius, formatted.panel_cove_radius || params.panel_cove_radius_mm);
    applyFormatted(form.panelClearance, formatted.panel_clearance_per_side || params.panel_clearance_per_side_mm);
    applyFormatted(form.grooveDepth, formatted.groove_depth || params.groove_depth_mm);
    applyFormatted(form.grooveWidth, formatted.groove_width || '');
    applyFormatted(form.drawerRailWidth, formatted.drawer_rail_width || params.drawer_rail_width_mm || '');
    applyFormatted(
      form.minDrawerRailWidth,
      formatted.min_drawer_rail_width || params.min_drawer_rail_width_mm
    );
    applyFormatted(form.minPanelOpening, formatted.min_panel_opening || params.min_panel_opening_mm);
    form.insideProfile.value = params.inside_profile_id || 'shaker_inside';
    form.panelStyle.value = params.panel_style || 'flat';

    if (form.drawerMessages) {
      if (payload.last_drawer_rules_action === 'slab') {
        form.drawerMessages.textContent = 'Front previously fell back to slab based on drawer rules.';
      } else {
        form.drawerMessages.textContent = '';
      }
    }
  }

  function showBanner(kind, message) {
    form.banner.textContent = message || '';
    form.banner.className = 'banner banner--' + kind;
  }

  function validationError(messages) {
    clearErrors();
    if (!messages || !messages.length) return;
    var last = messages[messages.length - 1];
    showBanner('error', last);
  }

  function notify(payload) {
    if (!payload) return;
    if (payload.kind === 'warning' && form.drawerMessages) {
      form.drawerMessages.textContent = payload.message || '';
    }
    showBanner(payload.kind || 'info', payload.message || '');
  }

  function setMode(mode) {
    currentMode = mode;
    setFormEnabled(mode === 'ready');
    if (form.chooserSection) {
      form.chooserSection.classList.toggle('is-hidden', mode !== 'choose');
    }
    if (mode !== 'choose' && form.candidateList) {
      form.candidateList.innerHTML = '';
    }
    if (mode !== 'ready' && form.targetLabel) {
      form.targetLabel.textContent = '';
      form.targetLabel.classList.add('is-hidden');
    }
    syncInsideProfileControl();
  }

  function setFormEnabled(enabled) {
    interactiveControls.forEach(function (control) {
      if (!control) return;
      var alwaysDisabled = control.dataset && control.dataset.staticDisabled === 'true';
      if (alwaysDisabled) {
        control.disabled = true;
        return;
      }
      control.disabled = !enabled;
    });
    if (form.apply) form.apply.disabled = !enabled;
    if (form.reset) form.reset.disabled = !enabled;
    syncInsideProfileControl();
  }

  function renderTarget(target) {
    if (!form.targetLabel) return;
    if (target && (target.path_hint || target.name)) {
      form.targetLabel.textContent = 'Editing: ' + (target.path_hint || target.name);
      form.targetLabel.classList.remove('is-hidden');
    } else {
      form.targetLabel.textContent = '';
      form.targetLabel.classList.add('is-hidden');
    }
  }

  function renderChooser(payload) {
    if (!form.candidateList) return;
    form.candidateList.innerHTML = '';
    var message = (payload && payload.text) || DEFAULT_MESSAGE;
    if (form.chooserMessage) {
      form.chooserMessage.textContent = message;
    }
    var candidates = (payload && payload.candidates) || [];
    candidates.forEach(function (candidate) {
      var item = document.createElement('li');
      item.className = 'candidate-list__item';
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'candidate-list__button';
      button.textContent = candidate.name || candidate.path_hint || 'Front';
      button.dataset.persistentId = candidate.persistent_id;
      button.addEventListener('click', function () {
        chooseTarget(button.dataset.persistentId);
      });
      item.appendChild(button);
      if (candidate.path_hint && candidate.path_hint !== candidate.name) {
        var hint = document.createElement('div');
        hint.className = 'candidate-list__hint';
        hint.textContent = candidate.path_hint;
        item.appendChild(hint);
      }
      form.candidateList.appendChild(item);
    });
  }

  function buildPayload() {
    return {
      door_style: form.doorStyle.value,
      inside_profile_id: form.insideProfile.value,
      stile_width: form.stileWidth.value,
      rail_width: form.railWidth.value,
      panel_style: form.panelStyle.value,
      panel_thickness: form.panelThickness.value,
      panel_cove_radius: form.panelCoveRadius.value,
      panel_clearance_per_side: form.panelClearance.value,
      groove_depth: form.grooveDepth.value,
      groove_width: form.grooveWidth.value,
      drawer_rail_width: form.drawerRailWidth.value,
      min_drawer_rail_width: form.minDrawerRailWidth.value,
      min_panel_opening: form.minPanelOpening.value,
      scope: form.scopeInstance.checked ? 'instance' : 'definition',
    };
  }

  function requestState() {
    if (window.sketchup && typeof window.sketchup['fronts:get_state'] === 'function') {
      window.sketchup['fronts:get_state']();
    }
  }

  function chooseTarget(persistentId) {
    if (!persistentId) return;
    if (window.sketchup && typeof window.sketchup['fronts:choose_target'] === 'function') {
      window.sketchup['fronts:choose_target']({ persistent_id: persistentId });
    }
  }

  function requestDefaults() {
    if (currentMode !== 'ready') {
      requestState();
      return;
    }
    if (window.sketchup && typeof window.sketchup['fronts:reset_defaults'] === 'function') {
      window.sketchup['fronts:reset_defaults']();
    }
  }

  function requestApply() {
    clearErrors();
    if (currentMode !== 'ready') {
      showBanner('warning', DEFAULT_MESSAGE);
      return;
    }
    if (window.sketchup && typeof window.sketchup['fronts:apply'] === 'function') {
      window.sketchup['fronts:apply'](buildPayload());
    }
  }

  function init() {
    toggleFivePieceFields();
    form.doorStyle.addEventListener('change', toggleFivePieceFields);
    form.apply = document.getElementById('apply');
    form.reset = document.getElementById('reset');
    form.close = document.getElementById('close');

    interactiveControls = [
      form.doorStyle,
      form.insideProfile,
      form.stileWidth,
      form.railWidth,
      form.panelStyle,
      form.panelThickness,
      form.panelCoveRadius,
      form.panelClearance,
      form.grooveDepth,
      form.grooveWidth,
      form.drawerRailWidth,
      form.minDrawerRailWidth,
      form.minPanelOpening,
      form.scopeInstance,
    ];

    form.apply.addEventListener('click', function () {
      requestApply();
    });

    form.reset.addEventListener('click', function () {
      requestDefaults();
    });

    form.close.addEventListener('click', function () {
      window.close();
    });

    requestState();
  }

  window.AICabinetsFronts = {
    receiveState: receiveState,
    validationError: validationError,
    notify: notify,
    receiveFormatted: function () {},
  };

  document.addEventListener('DOMContentLoaded', init);
})();
