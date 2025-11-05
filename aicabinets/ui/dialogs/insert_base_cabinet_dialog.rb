# frozen_string_literal: true

require 'json'

require 'aicabinets/defaults'
require 'aicabinets/params_sanitizer'
require 'aicabinets/ui/localization'
require 'aicabinets/ui_visibility'
require 'aicabinets/door_mode_rules'

module AICabinets
  module UI
    module Dialogs
      module InsertBaseCabinet
        module_function

        Localization = AICabinets::UI::Localization
        private_constant :Localization

        INSERT_DIALOG_TITLE = 'AI Cabinets — Insert Base Cabinet'
        EDIT_DIALOG_TITLE = 'AI Cabinets — Edit Base Cabinet'
        PREFERENCES_KEY = 'AICabinets.InsertBaseCabinet'
        HTML_FILENAME = 'insert_base_cabinet.html'
        MAX_LENGTH_MM = 100_000.0
        VALID_FRONT_VALUES = %w[empty doors_left doors_right doors_double].freeze
        VALID_PARTITION_MODES = %w[none vertical horizontal].freeze
        VALID_PARTITION_LAYOUTS = %w[none even positions].freeze
        DEFAULT_PARTITION_LAYOUT = 'even'
        LENGTH_FIELD_NAMES = {
          width_mm: 'Width',
          depth_mm: 'Depth',
          height_mm: 'Height',
          panel_thickness_mm: 'Panel thickness',
          toe_kick_height_mm: 'Toe kick height',
          toe_kick_depth_mm: 'Toe kick depth',
          toe_kick_thickness_mm: 'Toe kick thickness'
        }.freeze
        CONFIRM_EDIT_ALL_COPY = {
          title: 'AI Cabinets — Edit All Instances',
          message: 'This change will update %{count} instances of this cabinet.',
          hint: 'Apply to all (%{count}) — choose Yes. Cancel — choose No.'
        }.freeze

        class PayloadError < StandardError
          attr_reader :code, :field

          def initialize(code, message, field = nil)
            super(message)
            @code = code
            @field = field
          end
        end
        private_constant :PayloadError
        private_constant :MAX_LENGTH_MM, :VALID_FRONT_VALUES, :VALID_PARTITION_MODES,
                        :VALID_PARTITION_LAYOUTS, :DEFAULT_PARTITION_LAYOUT, :LENGTH_FIELD_NAMES

        # Shows the Insert Base Cabinet dialog, creating it if necessary.
        # Subsequent invocations focus the existing dialog to avoid duplicates.
        def show
          return unless ensure_html_dialog_support

          dialog = ensure_dialog
          set_dialog_context(mode: :insert, prefill: nil, selection: nil)
          update_dialog_title(dialog)
          show_dialog(dialog)
          dialog
        end

        def show_for_edit(instance)
          return unless ensure_html_dialog_support
          return unless defined?(Sketchup::ComponentInstance)
          return unless instance.is_a?(Sketchup::ComponentInstance)

          params = extract_definition_params(instance)
          unless params
            warn('AI Cabinets: Selected cabinet is missing stored parameters.')
            return nil
          end

          selection_details = selection_details_for(instance)

          dialog = ensure_dialog
          set_dialog_context(mode: :edit, prefill: params, selection: selection_details)
          update_dialog_title(dialog)
          show_dialog(dialog)
          dialog
        end

        def ensure_dialog
          @dialog ||= build_dialog
        end
        private_class_method :ensure_dialog

        def build_dialog
          options = {
            dialog_title: INSERT_DIALOG_TITLE,
            preferences_key: PREFERENCES_KEY,
            style: ::UI::HtmlDialog::STYLE_DIALOG,
            resizable: true,
            width: 400,
            height: 360
          }

          dialog = ::UI::HtmlDialog.new(options)
          attach_callbacks(dialog)
          set_dialog_file(dialog)
          dialog.set_on_closed do
            cancel_active_placement(dialog)
            @dialog = nil
          end
          dialog
        end
        private_class_method :build_dialog

        def dialog_context
          @dialog_context ||= { mode: :insert, prefill: nil, selection: nil }
        end
        private_class_method :dialog_context

        def dialog_state
          @dialog_state ||= {}
        end
        private_class_method :dialog_state

        def reset_dialog_state!
          @dialog_state = {}
        end
        private_class_method :reset_dialog_state!

        def set_dialog_context(mode:, prefill: nil, selection: nil)
          dialog_context[:mode] = mode
          dialog_context[:prefill] = normalize_prefill(prefill)
          dialog_context[:selection] = selection.is_a?(Hash) ? selection.dup : nil
          reset_dialog_state!
        end
        private_class_method :set_dialog_context

        def normalize_prefill(prefill)
          return nil unless prefill.is_a?(Hash)

          copy = deep_copy_params(prefill)
          unless copy.key?(:toe_kick_thickness_mm)
            panel_value = copy[:panel_thickness_mm] || copy['panel_thickness_mm']
            copy[:toe_kick_thickness_mm] = panel_value if panel_value
          end
          copy
        end
        private_class_method :normalize_prefill

        def dialog_defaults
          dialog_state[:defaults] ||= AICabinets::Defaults.load_effective_mm
        end
        private_class_method :dialog_defaults

        def store_dialog_params(params)
          return unless params.is_a?(Hash)

          copy = deep_copy_params(params)
          AICabinets::ParamsSanitizer.sanitize!(copy, global_defaults: dialog_defaults)
          dialog_state[:params] = copy
        end
        private_class_method :store_dialog_params

        def current_params
          dialog_state[:params]
        end
        private_class_method :current_params

        def ensure_dialog_params
          params = current_params
          return params if params.is_a?(Hash)

          defaults = dialog_defaults
          store_dialog_params(defaults)
          dialog_state[:params]
        end
        private_class_method :ensure_dialog_params

        def fetch_partitions(params)
          container = params[:partitions] || params['partitions']
          container.is_a?(Hash) ? container : {}
        end
        private_class_method :fetch_partitions

        def fetch_partition_mode(params)
          return 'none' unless params.is_a?(Hash)

          value = params[:partition_mode] || params['partition_mode']
          normalize_partition_mode(value)
        end
        private_class_method :fetch_partition_mode

        def partition_layout_cache
          dialog_state[:partition_layout_cache] ||= {}
        end
        private_class_method :partition_layout_cache

        def cache_layout_for(mode, layout)
          return unless %w[vertical horizontal].include?(mode)

          normalized = normalize_partition_layout_mode(layout)
          return if normalized == 'none'

          partition_layout_cache[mode.to_sym] = normalized
        end
        private_class_method :cache_layout_for

        def cached_layout_for(mode)
          value = partition_layout_cache[mode.to_sym]
          normalized = normalize_partition_layout_mode(value)
          normalized == 'none' ? nil : normalized
        end
        private_class_method :cached_layout_for

        def default_partition_layout
          defaults = dialog_defaults
          partitions = fetch_partitions(defaults)
          candidate = partitions[:mode] || partitions['mode']
          normalized = normalize_partition_layout_mode(candidate)
          normalized == 'none' ? DEFAULT_PARTITION_LAYOUT : normalized
        end
        private_class_method :default_partition_layout

        def fetch_bays_array(params)
          partitions = fetch_partitions(params)
          bays = partitions[:bays] || partitions['bays']
          return bays if bays.is_a?(Array)

          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          partitions = fetch_partitions(params)
          partitions[:bays] || []
        end
        private_class_method :fetch_bays_array

        def default_bay_template
          partitions = fetch_partitions(dialog_defaults)
          bays = partitions[:bays]
          sample = bays.is_a?(Array) ? bays.first : nil
          template = sample.is_a?(Hash) ? sample : { shelf_count: 0, door_mode: nil }
          deep_copy_params(template)
        end
        private_class_method :default_bay_template

        def build_double_validity(params)
          bays = fetch_bays_array(params)
          return [] unless bays.is_a?(Array)

          bays.each_with_index.map do |_bay, index|
            allowed, reason = evaluate_double_validity(params, index)
            { allowed: allowed, reason: reason }
          end
        end
        private_class_method :build_double_validity

        # Queries the cabinet helper for double-door feasibility and resolves the
        # returned localization key into a user-facing string.
        def evaluate_double_validity(params, index)
          result = AICabinets::DoorModeRules.double_door_validity(params_mm: params, bay_index: index)
          allowed = result.is_a?(Array) ? result[0] : false
          reason_value = result.is_a?(Array) ? result[1] : nil
          reason =
            case reason_value
            when Symbol
              Localization.string(reason_value)
            when String
              reason_value
            else
              nil
            end
          [allowed ? true : false, reason]
        rescue StandardError => e
          warn("AI Cabinets: Unable to compute double door validity for bay #{index}: #{e.message}")
          [false, Localization.string(:door_mode_double_disabled_hint)]
        end
        private_class_method :evaluate_double_validity

        def execute_state_callback(dialog, function_name, *args)
          return unless dialog

          serialized = args.map { |arg| JSON.generate(arg) }
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (root && typeof root.#{function_name} === 'function') {
                root.#{function_name}(#{serialized.join(', ')});
              }
            })();
          JS

          dialog.execute_script(script)
        rescue StandardError => e
          warn("AI Cabinets: Unable to deliver #{function_name} message to dialog: #{e.message}")
        end
        private_class_method :execute_state_callback

        def deliver_bay_state(dialog)
          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          state = build_bay_state(params)
          execute_state_callback(dialog, 'state_init', state)
          execute_state_callback(dialog, 'state_update_visibility', state[:ui])
        end
        private_class_method :deliver_bay_state

        def deliver_state_bays_changed(dialog, params)
          state = build_bay_state(params)
          execute_state_callback(dialog, 'state_bays_changed', state)
          execute_state_callback(dialog, 'state_update_visibility', state[:ui])
        end
        private_class_method :deliver_state_bays_changed

        def build_bay_state(params)
          partition_mode = fetch_partition_mode(params)
          partitions = fetch_partitions(params)
          layout_mode = normalize_partition_layout_mode(partitions[:mode] || partitions['mode'])
          cache_layout_for(partition_mode, layout_mode)
          bays = fetch_bays_array(params).map { |bay| deep_copy_params(bay) }
          selected = AICabinets::UiVisibility.clamp_selected_index(selected_bay_index, bays.length)
          set_selected_bay_index(selected)

          {
            partition_mode: partition_mode,
            partitions: {
              mode: layout_mode,
              count: partitions[:count] || partitions['count'] || 0,
              positions_mm: partitions[:positions_mm] || partitions['positions_mm'] || []
            },
            bays: bays,
            selected_index: selected,
            can_double: build_double_validity(params),
            ui: AICabinets::UiVisibility.flags_for(params)
          }
        end
        private_class_method :build_bay_state

        def deliver_state_update_bay(dialog, index, bay)
          execute_state_callback(dialog, 'state_update_bay', index, bay)
        end
        private_class_method :deliver_state_update_bay

        def deliver_double_validity(dialog, index, allowed, reason)
          execute_state_callback(dialog, 'state_set_double_validity', index, allowed ? true : false, reason)
        end
        private_class_method :deliver_double_validity

        def deliver_double_validity_for_all(dialog, params)
          build_double_validity(params).each_with_index do |entry, index|
            deliver_double_validity(dialog, index, entry[:allowed], entry[:reason])
          end
        end
        private_class_method :deliver_double_validity_for_all

        def deliver_toast(dialog, message)
          return unless message && !message.to_s.empty?

          execute_state_callback(dialog, 'toast', message.to_s)
        end
        private_class_method :deliver_toast

        def parse_payload(payload)
          case payload
          when String
            JSON.parse(payload, symbolize_names: true)
          when Hash
            payload.each_with_object({}) do |(key, value), memo|
              memo[key.is_a?(String) ? key.to_sym : key] = value
            end
          else
            {}
          end
        rescue JSON::ParserError
          {}
        end
        private_class_method :parse_payload

        def extract_index(data)
          return nil unless data.is_a?(Hash)

          value = data[:index] || data['index']
          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end
        private_class_method :extract_index

        def extract_integer(value)
          numeric = Integer(value)
          return nil if numeric.negative?

          numeric
        rescue ArgumentError, TypeError
          nil
        end
        private_class_method :extract_integer

        def extract_string(value)
          return nil if value.nil?

          text = value.to_s.strip
          text.empty? ? nil : text
        end
        private_class_method :extract_string

        def normalize_partition_layout_mode(value)
          text = extract_string(value)
          return 'none' if text.nil?

          normalized = text.downcase
          return normalized if VALID_PARTITION_LAYOUTS.include?(normalized)

          'none'
        end
        private_class_method :normalize_partition_layout_mode

        def normalize_partition_mode(value)
          text = extract_string(value)
          return 'none' if text.nil?

          normalized = text.downcase
          return normalized if VALID_PARTITION_MODES.include?(normalized)

          warn("AI Cabinets: Unknown partition_mode '#{value}'; falling back to none.")
          'none'
        end
        private_class_method :normalize_partition_mode

        def handle_ui_init_ready(dialog)
          deliver_bay_state(dialog)
        end
        private_class_method :handle_ui_init_ready

        def handle_ui_select_bay(payload)
          data = parse_payload(payload)
          index = extract_index(data)
          return unless index

          params = ensure_dialog_params
          bays = fetch_bays_array(params)
          clamped = AICabinets::UiVisibility.clamp_selected_index(index, bays.length)
          set_selected_bay_index(clamped)
        end
        private_class_method :handle_ui_select_bay

        def handle_ui_set_partition_mode(dialog, payload)
          data = parse_payload(payload)
          raw_value = extract_string(data[:value] || data['value'])
          mode = normalize_partition_mode(raw_value)

          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          previous_mode = fetch_partition_mode(params)
          partitions = fetch_partitions(params)
          cache_layout_for(previous_mode, partitions[:mode] || partitions['mode'])

          params[:partition_mode] = mode

          if %w[vertical horizontal].include?(mode)
            restored = cached_layout_for(mode) || normalize_partition_layout_mode(partitions[:mode] || partitions['mode'])
            restored = default_partition_layout if restored == 'none'
            partitions[:mode] = restored
            cache_layout_for(mode, restored)
          end

          set_selected_bay_index(0)
          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          store_dialog_params(params)

          updated_params = ensure_dialog_params
          deliver_state_bays_changed(dialog, updated_params)
        end
        private_class_method :handle_ui_set_partition_mode

        def handle_ui_set_partitions_count(dialog, payload)
          data = parse_payload(payload)
          value = extract_integer(data[:value] || data['value'])
          return if value.nil?

          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          partitions = fetch_partitions(params)
          partitions[:count] = value

          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          store_dialog_params(params)

          updated_params = ensure_dialog_params
          deliver_state_bays_changed(dialog, updated_params)
        end
        private_class_method :handle_ui_set_partitions_count

        def handle_ui_partitions_changed(dialog, payload)
          data = parse_payload(payload)
          return unless data.is_a?(Hash)

          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          partitions = fetch_partitions(params)
          if data.key?(:count) || data.key?('count')
            value = data[:count] || data['count']
            count = extract_integer(value)
            partitions[:count] = count unless count.nil?
          end

          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          store_dialog_params(params)

          updated_params = ensure_dialog_params
          bays = fetch_bays_array(updated_params)
          length = bays.length

          requested =
            data[:selected_bay_index] ||
            data['selected_bay_index'] ||
            data[:selected_index] ||
            data['selected_index']

          selected = extract_integer(requested)
          selected = selected_bay_index if selected.nil?

          clamped = AICabinets::UiVisibility.clamp_selected_index(selected, length)
          set_selected_bay_index(clamped)

          deliver_state_bays_changed(dialog, updated_params)
        end
        private_class_method :handle_ui_partitions_changed

        def handle_ui_set_partitions_layout(dialog, payload)
          data = parse_payload(payload)
          raw_value = extract_string(data[:value] || data['value'])
          mode = normalize_partition_layout_mode(raw_value)

          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          partitions = fetch_partitions(params)
          partitions[:mode] = mode

          partition_mode = fetch_partition_mode(params)
          cache_layout_for(partition_mode, mode)

          partitions[:positions_mm] = [] if mode == 'even'

          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          store_dialog_params(params)

          updated_params = ensure_dialog_params
          deliver_state_bays_changed(dialog, updated_params)
        end
        private_class_method :handle_ui_set_partitions_layout

        def handle_ui_set_shelf_count(dialog, payload)
          data = parse_payload(payload)
          index = extract_index(data)
          return unless index && index >= 0

          value = extract_integer(data[:value] || data['value'])
          return if value.nil?

          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          bays = fetch_bays_array(params)
          while bays.length <= index
            bays << default_bay_template
          end

          bays[index][:shelf_count] = value
          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          store_dialog_params(params)

          updated_params = ensure_dialog_params
          updated_bays = fetch_bays_array(updated_params)
          deliver_state_update_bay(dialog, index, updated_bays[index])
          allowed, reason = evaluate_double_validity(updated_params, index)
          deliver_double_validity(dialog, index, allowed, reason)
        end
        private_class_method :handle_ui_set_shelf_count

        def handle_ui_set_door_mode(dialog, payload)
          data = parse_payload(payload)
          index = extract_index(data)
          return unless index && index >= 0

          raw_value = extract_string(data[:value] || data['value'])
          value = raw_value == 'none' ? nil : raw_value

          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          bays = fetch_bays_array(params)
          while bays.length <= index
            bays << default_bay_template
          end

          if value == 'doors_double'
            allowed, reason = evaluate_double_validity(params, index)
            unless allowed
              deliver_double_validity(dialog, index, allowed, reason)
              return
            end
          end

          bays[index][:door_mode] = value
          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          store_dialog_params(params)

          updated_params = ensure_dialog_params
          updated_bays = fetch_bays_array(updated_params)
          deliver_state_update_bay(dialog, index, updated_bays[index])
          allowed, reason = evaluate_double_validity(updated_params, index)
          deliver_double_validity(dialog, index, allowed, reason)
        end
        private_class_method :handle_ui_set_door_mode

        def handle_ui_apply_to_all(dialog, payload)
          data = parse_payload(payload)
          index = extract_index(data)
          return unless index && index >= 0

          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          bays = fetch_bays_array(params)
          return unless index < bays.length

          source = bays[index]
          source_shelf = extract_integer(source[:shelf_count]) || 0
          source_door = source[:door_mode]
          skipped = 0

          bays.each_with_index do |bay, bay_index|
            bay[:shelf_count] = source_shelf
            next if bay_index == index

            if source_door == 'doors_double'
              allowed, = evaluate_double_validity(params, bay_index)
              if allowed
                bay[:door_mode] = source_door
              else
                skipped += 1
              end
            else
              bay[:door_mode] = source_door
            end
          end

          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          store_dialog_params(params)

          updated_params = ensure_dialog_params
          updated_bays = fetch_bays_array(updated_params)
          updated_bays.each_with_index do |bay, bay_index|
            deliver_state_update_bay(dialog, bay_index, bay)
          end
          deliver_double_validity_for_all(dialog, updated_params)

          if skipped.positive?
            template = Localization.string(:bay_double_skip_notice)
            message = format(template, count: skipped)
            deliver_toast(dialog, message)
          end
        end
        private_class_method :handle_ui_apply_to_all

        def handle_ui_copy_left_to_right(dialog)
          params = ensure_dialog_params
          return unless params.is_a?(Hash)

          bays = fetch_bays_array(params)
          length = bays.length
          return if length < 2

          skipped = 0
          (0...(length / 2)).each do |left_index|
            dest_index = length - 1 - left_index
            next if dest_index == left_index

            source = bays[left_index]
            dest = bays[dest_index]
            next unless source.is_a?(Hash) && dest.is_a?(Hash)

            dest[:shelf_count] = extract_integer(source[:shelf_count]) || 0
            door_mode = source[:door_mode]
            if door_mode == 'doors_double'
              allowed, = evaluate_double_validity(params, dest_index)
              if allowed
                dest[:door_mode] = door_mode
              else
                skipped += 1
              end
            else
              dest[:door_mode] = door_mode
            end
          end

          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: dialog_defaults)
          store_dialog_params(params)

          updated_params = ensure_dialog_params
          updated_bays = fetch_bays_array(updated_params)
          updated_bays.each_with_index do |bay, bay_index|
            deliver_state_update_bay(dialog, bay_index, bay)
          end
          deliver_double_validity_for_all(dialog, updated_params)

          if skipped.positive?
            template = Localization.string(:bay_double_skip_notice)
            message = format(template, count: skipped)
            deliver_toast(dialog, message)
          end
        end
        private_class_method :handle_ui_copy_left_to_right

        def handle_ui_request_validity(dialog, payload)
          data = parse_payload(payload)
          index = extract_index(data)
          return unless index && index >= 0

          params = ensure_dialog_params
          allowed, reason = evaluate_double_validity(params, index)
          deliver_double_validity(dialog, index, allowed, reason)
        end
        private_class_method :handle_ui_request_validity

        def selected_bay_index
          value = dialog_state[:selected_bay]
          return value.to_i if value.is_a?(Numeric)

          0
        end
        private_class_method :selected_bay_index

        def set_selected_bay_index(index)
          dialog_state[:selected_bay] = index.to_i
        end
        private_class_method :set_selected_bay_index

        def dialog_mode
          dialog_context[:mode] || :insert
        end
        private_class_method :dialog_mode

        def dialog_prefill
          dialog_context[:prefill]
        end
        private_class_method :dialog_prefill

        def dialog_selection
          dialog_context[:selection]
        end
        private_class_method :dialog_selection

        def determine_scope_default(selection)
          default_scope = 'instance'
          return default_scope unless selection.is_a?(Hash)

          raw_count = selection[:instances_count]
          raw_count = selection['instances_count'] if raw_count.nil?

          begin
            count_value = Integer(raw_count)
          rescue ArgumentError, TypeError
            warn('AI Cabinets: Selection metadata missing instances_count; defaulting edit scope to instance.')
            return default_scope
          end

          return 'definition' if count_value > 1

          default_scope
        rescue StandardError => e
          warn("AI Cabinets: Unable to determine scope default: #{e.message}")
          default_scope
        end
        private_class_method :determine_scope_default

        def attach_callbacks(dialog)
          dialog.add_action_callback('dialog_ready') do |_action_context, _payload|
            deliver_units_bootstrap(dialog)
            deliver_dialog_configuration(dialog)
          end

          dialog.add_action_callback('request_defaults') do |_action_context, _payload|
            deliver_form_defaults(dialog)
          end

          dialog.add_action_callback('aicb_submit_params') do |_action_context, json|
            handle_submit_params(dialog, json)
          end

          dialog.add_action_callback('cancel') do |_action_context, _payload|
            dialog.close
          end

          dialog.add_action_callback('cancel_placement') do |_action_context, _payload|
            cancel_active_placement(dialog)
          end

          dialog.add_action_callback('ui_init_ready') do |_action_context, _payload|
            handle_ui_init_ready(dialog)
          end

          dialog.add_action_callback('ui_select_bay') do |_context, payload|
            handle_ui_select_bay(payload)
          end

          dialog.add_action_callback('ui_set_shelf_count') do |_context, payload|
            handle_ui_set_shelf_count(dialog, payload)
          end

          dialog.add_action_callback('ui_set_door_mode') do |_context, payload|
            handle_ui_set_door_mode(dialog, payload)
          end

          dialog.add_action_callback('ui_apply_to_all') do |_context, payload|
            handle_ui_apply_to_all(dialog, payload)
          end

          dialog.add_action_callback('ui_copy_left_to_right') do |_context, _payload|
            handle_ui_copy_left_to_right(dialog)
          end

          dialog.add_action_callback('ui_request_validity') do |_context, payload|
            handle_ui_request_validity(dialog, payload)
          end

          dialog.add_action_callback('ui_set_partition_mode') do |_context, payload|
            handle_ui_set_partition_mode(dialog, payload)
          end

          dialog.add_action_callback('ui_set_partitions_layout') do |_context, payload|
            handle_ui_set_partitions_layout(dialog, payload)
          end

          dialog.add_action_callback('ui_set_partitions_count') do |_context, payload|
            handle_ui_set_partitions_count(dialog, payload)
          end
          dialog.add_action_callback('ui_partitions_changed') do |_context, payload|
            handle_ui_partitions_changed(dialog, payload)
          end
        end
        private_class_method :attach_callbacks

        def deliver_units_bootstrap(dialog)
          payload = JSON.generate(current_unit_settings)
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (root && typeof root.bootstrap === 'function') {
                root.bootstrap(#{payload});
              }
            })();
          JS

          dialog.execute_script(script)
        end
        private_class_method :deliver_units_bootstrap

        def deliver_dialog_configuration(dialog)
          configuration = {
            mode: dialog_mode.to_s,
            placement_notice: AICabinets::UI::Localization.string(:placement_indicator)
          }
          if dialog_mode == :edit
            selection = dialog_selection
            scope_default = determine_scope_default(selection)

            configuration[:scope] = scope_default
            configuration[:scope_default] = scope_default
            configuration[:selection] = selection
          end
          payload = JSON.generate(configuration)
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (root && typeof root.configure === 'function') {
                root.configure(#{payload});
              }
            })();
          JS

          dialog.execute_script(script)
        end
        private_class_method :deliver_dialog_configuration

        def deliver_form_defaults(dialog)
          case dialog_mode
          when :edit
            deliver_edit_prefill(dialog)
          else
            deliver_insert_defaults(dialog)
          end
        end
        private_class_method :deliver_form_defaults

        def deliver_insert_defaults(dialog)
          defaults = AICabinets::Ops::Defaults.load_insert_base_cabinet
          payload = JSON.generate(defaults)
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (root && typeof root.applyDefaults === 'function') {
                root.applyDefaults(#{payload});
              }
            })();
          JS

          dialog.execute_script(script)
          store_dialog_params(defaults)
          deliver_bay_state(dialog)
        end
        private_class_method :deliver_insert_defaults

        def deliver_edit_prefill(dialog)
          prefill = dialog_prefill
          unless prefill.is_a?(Hash)
            warn('AI Cabinets: No prefill payload available for edit dialog.')
            return
          end

          payload = JSON.generate(prefill)
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (root && typeof root.applyDefaults === 'function') {
                root.applyDefaults(#{payload});
              }
            })();
          JS

          dialog.execute_script(script)
          store_dialog_params(prefill)
          deliver_bay_state(dialog)
        end
        private_class_method :deliver_edit_prefill

        def handle_submit_params(dialog, json)
          ack = nil
          params_for_tool = nil

          begin
            typed_params = parse_submit_params(json)
            store_last_valid_params(deep_copy_params(typed_params))

          if dialog_mode == :edit
            ack = apply_edit_operation(typed_params)
          else
            params_for_tool = deep_copy_params(typed_params)
            ack = { ok: true, placement: true }
          end
          rescue PayloadError => e
            ack = build_error_ack(e.code, e.message, e.field)
          rescue StandardError => e
            warn("AI Cabinets: Unexpected error while processing insert parameters: #{e.message}")
            ack = build_error_ack('internal_error', 'Unable to process the request. Try again later.')
          ensure
            deliver_submit_ack(dialog, ack) if ack
          end

          return unless ack && ack[:ok]

          if dialog_mode == :insert && params_for_tool
            params_for_tool.delete(:scope)
            activated = activate_insert_tool(dialog, params_for_tool)
            enter_placement_mode(dialog) if activated
          elsif dialog_mode == :edit
            close_dialog_if_visible(dialog)
          end
        end
        private_class_method :handle_submit_params

        def apply_edit_operation(raw_params)
          unless defined?(Sketchup) && defined?(Sketchup::Model)
            return build_error_ack('internal_error', 'SketchUp environment is unavailable.')
          end

          model = Sketchup.active_model
          unless model.is_a?(Sketchup::Model)
            return build_error_ack('internal_error', 'No active model is available for editing.')
          end

          params = deep_copy_params(raw_params)
          scope = params.delete(:scope) || 'instance'

          if scope == 'all'
            definition, selection_ack = fetch_definition_for_all_scope(model)
            return selection_ack if selection_ack

            instance_count = count_definition_instances(definition)
            if instance_count > 1 && !confirm_edit_all_instances?(instance_count)
              return build_user_cancelled_ack
            end
          end

          result = AICabinets::Ops::EditBaseCabinet.apply_to_selection!(
            model: model,
            params_mm: params,
            scope: scope
          )

          return result if result.is_a?(Hash) && result.key?(:ok)

          { ok: true }
        rescue ArgumentError => e
          build_error_ack('invalid_params', e.message)
        rescue StandardError => e
          warn("AI Cabinets: Unable to apply edit operation: #{e.message}")
          build_error_ack('internal_error', 'Unable to edit the selected cabinet.')
        end
        private_class_method :apply_edit_operation

        def parse_submit_params(json)
          if json.nil?
            raise PayloadError.new('bad_json', 'Parameter payload was empty.')
          end

          raw = JSON.parse(json, symbolize_names: true)
          unless raw.is_a?(Hash)
            raise PayloadError.new('bad_json', 'Parameter payload must be a JSON object.')
          end

          build_typed_params(raw)
        rescue JSON::ParserError, TypeError
          raise PayloadError.new('bad_json', 'Parameter payload was not valid JSON.')
        end
        private_class_method :parse_submit_params

        def build_typed_params(raw)
          partition_mode = normalize_partition_mode(raw[:partition_mode])

          params = {
            width_mm: coerce_length_field(raw, :width_mm),
            depth_mm: coerce_length_field(raw, :depth_mm),
            height_mm: coerce_length_field(raw, :height_mm),
            panel_thickness_mm: coerce_length_field(raw, :panel_thickness_mm),
            toe_kick_height_mm: coerce_length_field(raw, :toe_kick_height_mm),
            toe_kick_depth_mm: coerce_length_field(raw, :toe_kick_depth_mm),
            front: validate_front_value(raw),
            shelves: validate_shelves_value(raw),
            partitions: validate_partitions_value(raw[:partitions])
          }

          params[:partition_mode] = partition_mode

          if partition_mode == 'none'
            params[:partitions][:mode] = 'none'
            params[:partitions][:count] = 0
            params[:partitions][:positions_mm] = []
          end

          params[:toe_kick_thickness_mm] =
            if raw.key?(:toe_kick_thickness_mm)
              coerce_non_negative_length(
                raw[:toe_kick_thickness_mm],
                'toe_kick_thickness_mm',
                LENGTH_FIELD_NAMES[:toe_kick_thickness_mm]
              )
            else
              params[:panel_thickness_mm]
            end

          if raw[:ui_version].is_a?(String)
            version = raw[:ui_version].strip
            params[:ui_version] = version unless version.empty?
          end

          params[:scope] = validate_scope(raw[:scope]) if raw.key?(:scope)

          params
        end
        private_class_method :build_typed_params

        def validate_scope(value)
          return 'instance' if value.nil?

          unless value.is_a?(String)
            raise PayloadError.new('invalid_type', 'Scope selection is invalid.', 'scope')
          end

          normalized = value.strip.downcase
          case normalized
          when 'instance'
            'instance'
          when 'all'
            'all'
          else
            raise PayloadError.new('invalid_value', 'Scope selection is invalid.', 'scope')
          end
        end
        private_class_method :validate_scope

        def coerce_length_field(raw, key)
          unless raw.key?(key)
            raise PayloadError.new('invalid_type', "#{LENGTH_FIELD_NAMES[key]} is required.", key.to_s)
          end

          coerce_non_negative_length(raw[key], key.to_s, LENGTH_FIELD_NAMES[key])
        end
        private_class_method :coerce_length_field

        def validate_front_value(raw)
          value = raw[:front]
          unless value.is_a?(String) && VALID_FRONT_VALUES.include?(value)
            raise PayloadError.new('invalid_type', 'Front layout is invalid.', 'front')
          end

          value
        end
        private_class_method :validate_front_value

        def validate_shelves_value(raw)
          unless raw.key?(:shelves)
            raise PayloadError.new('invalid_type', 'Shelves value is required.', 'shelves')
          end

          value = raw[:shelves]
          unless value.is_a?(Integer)
            raise PayloadError.new('invalid_type', 'Shelves must be a whole number.', 'shelves')
          end

          if value.negative?
            raise PayloadError.new('out_of_range', 'Shelves must be zero or greater.', 'shelves')
          end

          value
        end
        private_class_method :validate_shelves_value

        def validate_partitions_value(raw)
          unless raw.is_a?(Hash)
            raise PayloadError.new('invalid_type', 'Partitions payload must be an object.', 'partitions')
          end

          mode_value = extract_string(raw[:mode])
          normalized_source = mode_value&.downcase
          unless normalized_source && VALID_PARTITION_LAYOUTS.include?(normalized_source)
            raise PayloadError.new('invalid_type', 'Partition mode is invalid.', 'partitions.mode')
          end

          mode = normalize_partition_layout_mode(mode_value)
          typed = { mode: mode, count: 0, positions_mm: [] }

          case mode
          when 'even'
            unless raw.key?(:count)
              raise PayloadError.new('invalid_type', 'Partition count is required.', 'partitions.count')
            end

            count = raw[:count]
            unless count.is_a?(Integer)
              raise PayloadError.new('invalid_type', 'Partition count must be a whole number.', 'partitions.count')
            end

            if count.negative?
              raise PayloadError.new('out_of_range', 'Partition count must be zero or greater.', 'partitions.count')
            end

            typed[:count] = count
          when 'positions'
            positions = raw[:positions_mm]
            unless positions.is_a?(Array)
              raise PayloadError.new('invalid_type', 'Partition positions must be an array.', 'partitions.positions_mm')
            end

            if positions.empty?
              raise PayloadError.new('invalid_type', 'Provide at least one partition position.', 'partitions.positions_mm')
            end

            typed_positions = []
            previous = nil
            positions.each_with_index do |value, index|
              position = coerce_non_negative_length(value, 'partitions.positions_mm', "Partition position #{index + 1}")
              if previous && position <= previous
                raise PayloadError.new('non_increasing', 'Partition positions must increase from left to right.', 'partitions.positions_mm')
              end

              typed_positions << position
              previous = position
            end

            typed[:positions_mm] = typed_positions
          end

          if raw.key?(:panel_thickness_mm) && !raw[:panel_thickness_mm].nil?
            thickness = coerce_non_negative_length(
              raw[:panel_thickness_mm],
              'partitions.panel_thickness_mm',
              'Partition thickness'
            )
            if thickness <= 0
              raise PayloadError.new('out_of_range', 'Partition thickness must be greater than 0 mm.', 'partitions.panel_thickness_mm')
            end

            typed[:panel_thickness_mm] = thickness
          end

          typed
        end
        private_class_method :validate_partitions_value

        def coerce_non_negative_length(value, field, label)
          unless value.is_a?(Numeric)
            raise PayloadError.new('invalid_type', "#{label} must be a number.", field)
          end

          numeric = Float(value)
          unless numeric.finite?
            raise PayloadError.new('invalid_type', "#{label} must be a finite number.", field)
          end

          if numeric.negative?
            raise PayloadError.new('out_of_range', "#{label} must be at least 0 mm.", field)
          end

          if numeric > MAX_LENGTH_MM
            raise PayloadError.new('out_of_range', "#{label} must be #{MAX_LENGTH_MM.to_i} mm or less.", field)
          end

          numeric
        end
        private_class_method :coerce_non_negative_length

        def build_error_ack(code, message, field = nil)
          error = { code: code, message: message }
          error[:field] = field if field
          { ok: false, error: error }
        end
        private_class_method :build_error_ack

        def build_user_cancelled_ack
          { ok: false, error: { code: 'user_cancelled' } }
        end
        private_class_method :build_user_cancelled_ack

        def fetch_definition_for_all_scope(model)
          definition, error_code = AICabinets::Ops::EditBaseCabinet.selected_cabinet_definition(model)
          if error_code
            ack = AICabinets::Ops::EditBaseCabinet.selection_error_result(error_code)
            return [nil, ack]
          end

          [definition, nil]
        rescue StandardError => e
          warn("AI Cabinets: Unable to resolve cabinet definition for edit confirmation: #{e.message}")
          [nil, build_error_ack('internal_error', 'Unable to edit the selected cabinet.')]
        end
        private_class_method :fetch_definition_for_all_scope

        def selection_details_for(instance)
          details = {
            definition_name: nil,
            instances_count: 0,
            shares_definition: false
          }

          return details unless defined?(Sketchup::ComponentInstance)
          return details unless instance.is_a?(Sketchup::ComponentInstance)

          definition = instance.definition
          return details unless definition
          return details if definition.respond_to?(:valid?) && !definition.valid?

          details[:definition_name] = sanitized_definition_name(definition)
          count = count_definition_instances(definition)
          count_value = count.respond_to?(:to_i) ? count.to_i : 0
          details[:instances_count] = count_value
          details[:shares_definition] = count_value > 1
          details
        rescue StandardError => e
          warn("AI Cabinets: Unable to build selection metadata: #{e.message}")
          details
        end

        def count_definition_instances(definition)
          return 0 unless definition && definition.respond_to?(:instances)

          instances = definition.instances
          count = if instances.respond_to?(:size)
                    instances.size
                  else
                    Array(instances).size
                  end
          count.respond_to?(:to_i) ? count.to_i : 0
        rescue StandardError
          0
        end
        private_class_method :count_definition_instances

        def sanitized_definition_name(definition)
          return unless definition.respond_to?(:name)

          name = definition.name
          return unless name.is_a?(String)

          stripped = name.strip
          stripped.empty? ? nil : stripped
        rescue StandardError
          nil
        end
        private_class_method :sanitized_definition_name

        def confirm_edit_all_instances?(instance_count)
          return true unless instance_count && instance_count > 1
          return true unless defined?(::UI) && ::UI.respond_to?(:messagebox)

          message = build_confirm_all_instances_message(instance_count)
          response = ::UI.messagebox(message, MB_YESNO, CONFIRM_EDIT_ALL_COPY[:title])
          response == IDYES
        rescue StandardError => e
          warn("AI Cabinets: Unable to show confirmation message box: #{e.message}")
          true
        end
        private_class_method :confirm_edit_all_instances?

        def build_confirm_all_instances_message(instance_count)
          body = format(CONFIRM_EDIT_ALL_COPY[:message], count: instance_count)
          hint = format(CONFIRM_EDIT_ALL_COPY[:hint], count: instance_count)
          "#{body}\n\n#{hint}"
        end
        private_class_method :build_confirm_all_instances_message

        def deliver_submit_ack(dialog, ack)
          return unless dialog && dialog.visible?

          payload = JSON.generate(ack)
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertForm;
              if (root && typeof root.onSubmitAck === 'function') {
                root.onSubmitAck(#{payload});
              }
            })();
          JS

          dialog.execute_script(script)
        rescue StandardError => e
          warn("AI Cabinets: Unable to deliver insert parameters acknowledgement: #{e.message}")
        end
        private_class_method :deliver_submit_ack

        def store_last_valid_params(params)
          @last_valid_params = params
        end
        private_class_method :store_last_valid_params

        def extract_definition_params(instance)
          dictionary_name = AICabinets::Ops::InsertBaseCabinet::DICTIONARY_NAME
          params_key = AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY
          definition = instance.definition
          return unless definition

          dict = definition.attribute_dictionary(dictionary_name)
          return unless dict

          params_json = dict[params_key]
          return unless params_json.is_a?(String) && !params_json.empty?

          params = JSON.parse(params_json, symbolize_names: true)
          defaults = AICabinets::Defaults.load_effective_mm
          AICabinets::ParamsSanitizer.sanitize!(params, global_defaults: defaults)
          params
        rescue JSON::ParserError => e
          warn("AI Cabinets: Unable to parse stored cabinet parameters: #{e.message}")
          nil
        end
        private_class_method :extract_definition_params

        def update_dialog_title(dialog)
          title = dialog_mode == :edit ? EDIT_DIALOG_TITLE : INSERT_DIALOG_TITLE
          if dialog.respond_to?(:set_title)
            dialog.set_title(title)
          elsif dialog.respond_to?(:title=)
            dialog.title = title
          end
        end
        private_class_method :update_dialog_title

        def show_dialog(dialog)
          if dialog.visible?
            dialog.bring_to_front
          else
            dialog.show
          end
        end
        private_class_method :show_dialog

        def deep_copy_params(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, val), memo|
              memo[key] = deep_copy_params(val)
            end
          when Array
            value.map { |item| deep_copy_params(item) }
          else
            value
          end
        end
        private_class_method :deep_copy_params

        def close_dialog_if_visible(dialog)
          return unless dialog&.visible?

          dialog.close if dialog.visible?
        rescue StandardError => e
          warn("AI Cabinets: Unable to close Insert Base Cabinet dialog: #{e.message}")
        end
        private_class_method :close_dialog_if_visible

        def activate_insert_tool(dialog, params_mm)
          activation_error = AICabinets::UI::Localization.string(:placement_activation_failed)

          unless defined?(Sketchup) && defined?(Sketchup::Model)
            warn('AI Cabinets: SketchUp environment is unavailable for tool activation.')
            finish_placement_mode(dialog, status: :error, message: activation_error)
            return false
          end

          unless defined?(AICabinets::UI::Tools::InsertBaseCabinetTool)
            warn('AI Cabinets: Insert Base Cabinet tool is not available.')
            finish_placement_mode(dialog, status: :error, message: activation_error)
            return false
          end

          model = Sketchup.active_model
          unless model.is_a?(Sketchup::Model)
            warn('AI Cabinets: No active model is available for insertion.')
            finish_placement_mode(dialog, status: :error, message: activation_error)
            return false
          end

          tools = model.tools
          unless tools.respond_to?(:push_tool)
            warn('AI Cabinets: Tool stack is unavailable for activation.')
            finish_placement_mode(dialog, status: :error, message: activation_error)
            return false
          end

          callbacks = placement_tool_callbacks(dialog)
          tool = AICabinets::UI::Tools::InsertBaseCabinetTool.new(
            params_mm,
            callbacks: callbacks
          )
          tools.push_tool(tool)
          register_active_placement_tool(tool)
          true
        rescue StandardError => e
          warn("AI Cabinets: Unable to activate base cabinet placement tool: #{e.message}")
          finish_placement_mode(dialog, status: :error, message: activation_error)
          false
        end
        private_class_method :activate_insert_tool

        def placement_tool_callbacks(dialog)
          {
            cancel: lambda {
              finish_placement_mode(dialog, status: :cancelled)
            },
            complete: lambda { |_instance|
              finish_placement_mode(dialog, status: :placed)
            },
            error: lambda { |message|
              finish_placement_mode(dialog, status: :error, message: message)
            }
          }
        end
        private_class_method :placement_tool_callbacks

        def enter_placement_mode(dialog)
          return unless dialog&.visible?

          payload = {
            message: AICabinets::UI::Localization.string(:placement_indicator)
          }
          deliver_dialog_script(dialog, 'beginPlacement', payload)
        end
        private_class_method :enter_placement_mode

        def finish_placement_mode(dialog, status:, message: nil)
          clear_active_placement_tool
          return unless dialog&.visible?

          status_string = status.to_s
          message = AICabinets::UI::Localization.string(:placement_failed) if status_string == 'error' && (message.nil? || message.empty?)

          payload = { status: status_string }
          payload[:message] = message if message && !message.empty?
          deliver_dialog_script(dialog, 'finishPlacement', payload)
        end
        private_class_method :finish_placement_mode

        def active_placement_tool
          defined?(@active_placement_tool) ? @active_placement_tool : nil
        end
        private_class_method :active_placement_tool

        def register_active_placement_tool(tool)
          @active_placement_tool = tool
        end
        private_class_method :register_active_placement_tool

        def clear_active_placement_tool(tool = nil)
          return unless defined?(@active_placement_tool)
          return if tool && !@active_placement_tool.equal?(tool)

          @active_placement_tool = nil
        end
        private_class_method :clear_active_placement_tool

        def cancel_active_placement(dialog)
          tool = active_placement_tool

          unless tool
            clear_active_placement_tool
            finish_placement_mode(dialog, status: :cancelled)
            return
          end

          if tool.respond_to?(:cancel_from_ui)
            tool.cancel_from_ui
            return
          end

          model = defined?(Sketchup) ? Sketchup.active_model : nil
          if model
            model.select_tool(nil)
          else
            clear_active_placement_tool
            finish_placement_mode(dialog, status: :cancelled)
          end
        rescue StandardError => e
          warn("AI Cabinets: Unable to cancel placement tool: #{e.message}")
          clear_active_placement_tool
          finish_placement_mode(dialog, status: :error, message: AICabinets::UI::Localization.string(:placement_failed))
        end
        private_class_method :cancel_active_placement

        def deliver_dialog_script(dialog, function_name, payload)
          return unless dialog&.visible?

          json = JSON.generate(payload)
          script = <<~JS
            (function () {
              var root = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.InsertBaseCabinet;
              if (root && typeof root.#{function_name} === 'function') {
                root.#{function_name}(#{json});
              }
            })();
          JS

          dialog.execute_script(script)
        rescue StandardError => e
          warn("AI Cabinets: Unable to deliver dialog script #{function_name}: #{e.message}")
        end
        private_class_method :deliver_dialog_script

        def current_unit_settings
          model = ::Sketchup.active_model
          options = model&.options&.[]('UnitsOptions')

          return default_unit_settings unless options

          unit = length_unit_to_symbol(options['LengthUnit'])
          format = length_format_to_symbol(options['LengthFormat'])
          unit = normalize_unit_for_format(unit, format)
          {
            unit: unit,
            unit_label: unit_label_for(unit),
            unit_name: unit_name_for(unit),
            format: format,
            precision: options['LengthPrecision'],
            fractional_precision: options['LengthFractionalPrecision']
          }
        rescue StandardError
          default_unit_settings
        end
        private_class_method :current_unit_settings

        def default_unit_settings
          {
            unit: 'millimeter',
            unit_label: 'mm',
            unit_name: 'millimeters',
            format: 'decimal',
            precision: 0,
            fractional_precision: 3
          }
        end
        private_class_method :default_unit_settings

        def length_unit_to_symbol(code)
          case code
          when 0
            'inch'
          when 1
            'foot'
          when 3
            'centimeter'
          when 4
            'meter'
          else
            'millimeter'
          end
        end
        private_class_method :length_unit_to_symbol

        def length_format_to_symbol(code)
          case code
          when 1
            'architectural'
          when 2
            'engineering'
          when 3
            'fractional'
          else
            'decimal'
          end
        end
        private_class_method :length_format_to_symbol

        def normalize_unit_for_format(unit, format)
          return unit unless unit == 'foot'

          if %w[architectural fractional].include?(format)
            'inch'
          else
            unit
          end
        end
        private_class_method :normalize_unit_for_format

        def unit_label_for(unit)
          case unit
          when 'inch'
            'in'
          when 'foot'
            'ft'
          when 'centimeter'
            'cm'
          when 'meter'
            'm'
          else
            'mm'
          end
        end
        private_class_method :unit_label_for

        def unit_name_for(unit)
          case unit
          when 'inch'
            'inches'
          when 'foot'
            'feet'
          when 'centimeter'
            'centimeters'
          when 'meter'
            'meters'
          else
            'millimeters'
          end
        end
        private_class_method :unit_name_for

        def set_dialog_file(dialog)
          html_path = File.join(__dir__, HTML_FILENAME)

          unless File.exist?(html_path)
            warn_missing_asset(html_path)
            return
          end

          dialog.set_file(html_path)
        end
        private_class_method :set_dialog_file

        def ensure_html_dialog_support
          return true if defined?(::UI::HtmlDialog)

          warn('UI::HtmlDialog is not available in this environment.')
          false
        end
        private_class_method :ensure_html_dialog_support

        def warn_missing_asset(path)
          warn("AI Cabinets: Unable to locate dialog asset: #{path}")
        end
        private_class_method :warn_missing_asset
      end
    end
  end
end
