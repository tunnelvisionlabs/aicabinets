(function () {
  'use strict';

  var root = (window.AICabinets = window.AICabinets || {});
  var uiRoot = (root.UI = root.UI || {});
  var stringsNamespace = (uiRoot.Strings = uiRoot.Strings || {});

  var STRINGS = {
    bay_section_title: 'Bays',
    bay_selector_label: 'Select bay',
    bay_chip_label: 'Bay %{index}',
    bay_chip_selected_label: 'Selected bay %{index}',
    shelf_stepper_label: 'Shelves in this bay',
    shelf_stepper_decrease: 'Decrease shelf count',
    shelf_stepper_increase: 'Increase shelf count',
    shelf_input_aria: 'Shelf count for this bay',
    door_mode_group_label: 'Door mode',
    door_mode_none: 'None',
    door_mode_left: 'Left hinge',
    door_mode_right: 'Right hinge',
    door_mode_double: 'Double',
    door_mode_double_disabled_hint: 'Bay too narrow for double doors.',
    apply_to_all_label: 'Apply to all',
    copy_left_to_right_label: 'Copy L→R',
    apply_to_all_announcement: 'Copied bay %{source} settings to all bays.',
    copy_left_to_right_announcement: 'Copied bays from left to right.',
    bay_double_skip_notice: 'Skipped %{count} bay(s); too narrow for double doors.',
    live_region_title: 'Status updates',
    shelves_value_status: '%{count} shelf(s) in this bay.',
    door_mode_status_none: 'Door mode set to none.',
    door_mode_status_left: 'Door mode set to left hinge.',
    door_mode_status_right: 'Door mode set to right hinge.',
    door_mode_status_double: 'Door mode set to double.',
    bay_count_status: '%{count} bays available.',
    bay_selection_status: 'Selected bay %{index} of %{total}.',
    bay_chip_home: 'First bay',
    bay_chip_end: 'Last bay'
  };

  function format(template, params) {
    if (!params) {
      return template;
    }

    return template.replace(/%\{(\w+)\}/g, function (_, key) {
      if (Object.prototype.hasOwnProperty.call(params, key)) {
        return String(params[key]);
      }
      return '%{' + key + '}';
    });
  }

  stringsNamespace.dictionary = STRINGS;
  stringsNamespace.t = function t(key, params) {
    var value = STRINGS[key];
    if (typeof value !== 'string') {
      return key;
    }
    return format(value, params);
  };
})();
