(function () {
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
    scopeInstance: document.getElementById('scope-instance'),
    fivePieceSection: document.getElementById('five-piece-fields'),
    banner: document.getElementById('banner'),
  };

  function toggleFivePieceFields() {
    var show = form.doorStyle.value !== 'slab';
    form.fivePieceSection.classList.toggle('is-hidden', !show);
  }

  function clearErrors() {
    var nodes = document.querySelectorAll('[data-error-for]');
    Array.prototype.forEach.call(nodes, function (node) {
      node.textContent = '';
    });
    form.banner.textContent = '';
    form.banner.className = 'banner';
  }

  function applyFormatted(field, value) {
    if (!value) return;
    field.value = value;
  }

  function receiveState(payload) {
    clearErrors();
    if (!payload || !payload.params) {
      showBanner('error', 'Unable to load fronts state.');
      return;
    }

    form.doorStyle.value = payload.door_style || 'five_piece_cope_stick';
    toggleFivePieceFields();

    var formatted = payload.formatted || {};
    var params = payload.params || {};
    applyFormatted(form.stileWidth, formatted.stile_width || params.stile_width_mm);
    applyFormatted(form.railWidth, formatted.rail_width || '');
    applyFormatted(form.panelThickness, formatted.panel_thickness || params.panel_thickness_mm);
    applyFormatted(form.panelCoveRadius, formatted.panel_cove_radius || params.panel_cove_radius_mm);
    applyFormatted(form.panelClearance, formatted.panel_clearance_per_side || params.panel_clearance_per_side_mm);
    applyFormatted(form.grooveDepth, formatted.groove_depth || params.groove_depth_mm);
    applyFormatted(form.grooveWidth, formatted.groove_width || '');
    form.insideProfile.value = params.inside_profile_id || 'shaker_inside';
    form.panelStyle.value = params.panel_style || 'flat';
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
    showBanner(payload.kind || 'info', payload.message || '');
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
      scope: form.scopeInstance.checked ? 'instance' : 'definition',
    };
  }

  function requestState() {
    if (window.sketchup && typeof window.sketchup['fronts:get_state'] === 'function') {
      window.sketchup['fronts:get_state']();
    }
  }

  function requestDefaults() {
    if (window.sketchup && typeof window.sketchup['fronts:reset_defaults'] === 'function') {
      window.sketchup['fronts:reset_defaults']();
    }
  }

  function requestApply() {
    clearErrors();
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
