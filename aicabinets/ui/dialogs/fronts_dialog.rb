# frozen_string_literal: true

require 'json'
require 'set' # rubocop:disable Lint/RedundantRequireStatement -- required for Set usage

require 'aicabinets/geometry/five_piece'
require 'aicabinets/geometry/five_piece_panel'
require 'aicabinets/generator/fronts'
require 'aicabinets/metadata'
require 'aicabinets/ops/tags'
require 'aicabinets/ops/units'
require 'aicabinets/params/five_piece'
require 'aicabinets/rules/five_piece'
require 'aicabinets/ui/dialog_console_bridge'
require 'aicabinets/validation_error'

module AICabinets
  module UI
    module Dialogs
      module FrontsDialog
        extend self
        module_function

        ConsoleBridge = AICabinets::UI::DialogConsoleBridge unless const_defined?(:ConsoleBridge, false)
        Units = AICabinets::Ops::Units unless const_defined?(:Units, false)
        MIN_PANEL_OPENING_MM = 1.0 unless const_defined?(:MIN_PANEL_OPENING_MM, false)
        private_constant :ConsoleBridge, :Units, :MIN_PANEL_OPENING_MM

        DIALOG_TITLE = 'AI Cabinets — Fronts' unless const_defined?(:DIALOG_TITLE, false)
        PREFERENCES_KEY = 'AICabinets.FrontsDialog' unless const_defined?(:PREFERENCES_KEY, false)
        HTML_FILENAME = 'fronts_dialog.html' unless const_defined?(:HTML_FILENAME, false)
        DEFAULT_GUIDANCE =
          'Select a single AI Cabinets front, one of its tagged parts, or a cabinet that contains doors or drawers.'
            .freeze unless const_defined?(:DEFAULT_GUIDANCE, false)
        FRONT_TAG_NAMES =
          [
            AICabinets::Generator::Fronts::FRONTS_TAG_NAME,
            'Fronts',
            'Fronts (AI Cabinets)'
          ].freeze unless const_defined?(:FRONT_TAG_NAMES, false)

        def show
          dialog = ensure_dialog
          return unless dialog

          show_dialog(dialog)
          deliver_state(dialog)
          dialog
        end

        def ensure_dialog
          return if test_mode?
          return @dialog if @dialog
          return unless html_dialog_available?

          @dialog = build_dialog
        end
        private_class_method :ensure_dialog

        def current_dialog
          return nil if test_mode?

          @dialog
        end
        private_class_method :current_dialog

        def build_dialog
          options = {
            dialog_title: DIALOG_TITLE,
            preferences_key: PREFERENCES_KEY,
            style: ::UI::HtmlDialog::STYLE_DIALOG,
            resizable: true,
            width: 520,
            height: 520
          }

          dialog = ::UI::HtmlDialog.new(options)
          ConsoleBridge.register_dialog(dialog)
          attach_callbacks(dialog)
          set_dialog_file(dialog)
          dialog.set_on_closed do
            ConsoleBridge.unregister_dialog(dialog)
            @dialog = nil
          end
          dialog
        end
        private_class_method :build_dialog

        def attach_callbacks(dialog)
          dialog.add_action_callback('fronts:get_state') do |_context, _payload|
            deliver_state(dialog)
          end

          dialog.add_action_callback('fronts:apply') do |_context, payload|
            handle_apply(dialog, payload)
          end

          dialog.add_action_callback('fronts:reset_defaults') do |_context, _payload|
            deliver_defaults(dialog)
          end

          dialog.add_action_callback('fronts:choose_target') do |_context, payload|
            handle_choose_target(dialog, payload)
          end

          dialog.add_action_callback('fronts:format_length') do |_context, payload|
            handle_format_length(dialog, payload)
          end
        end
        private_class_method :attach_callbacks

        def show_dialog(dialog)
          dialog.bring_to_front
          dialog.show
        end
        private_class_method :show_dialog

        def deliver_state(dialog)
          payload = build_state_payload
          send_state(dialog, payload)
        rescue StandardError => e
          notify(dialog, 'error', "Unable to load current state: #{e.message}")
        end
        private_class_method :deliver_state

        def deliver_defaults(dialog)
          payload = build_state_payload(defaults: true)
          send_state(dialog, payload)
        rescue StandardError => e
          notify(dialog, 'error', "Unable to load defaults: #{e.message}")
        end
        private_class_method :deliver_defaults

        def handle_apply(dialog, payload)
          instance = current_front_instance
          unless instance
            payload = build_state_payload
            send_state(dialog, payload)
            notify(dialog, 'warning', DEFAULT_GUIDANCE)
            return
          end

          params = parse_payload(payload)
          scope = normalize_scope(payload)
          door_style = payload.is_a?(Hash) ? payload['door_style'] : nil

          target = scope == :instance ? ensure_unique_instance(instance) : instance.definition
          if door_style == 'slab'
            clear_five_piece_attributes(target)
            rebuild_slab(target)
            notify(dialog, 'info', 'Reverted to slab front.')
          else
            sanitized = AICabinets::Params::FivePiece.write!(target, params: params, scope: scope)
            result = regenerate_front_impl(target, sanitized)
            Array(result[:warnings]).each do |message|
              notify(dialog, 'warning', message)
            end
            if result[:decision]&.action == :slab
              notify(dialog, 'info', 'Front regenerated as slab based on drawer rules.')
            else
              notify(dialog, 'info', 'Five-piece settings applied.')
            end
          end

          deliver_state(dialog)
        rescue AICabinets::ValidationError => e
          send_validation_error(dialog, Array(e.messages))
        rescue StandardError => e
          notify(dialog, 'error', "Apply failed: #{e.message}")
        end
        private_class_method :handle_apply

        def handle_choose_target(dialog, payload)
          persistent_id = payload.is_a?(Hash) ? payload['persistent_id'] : nil
          unless persistent_id
            notify(dialog, 'warning', 'Pick a door or drawer front to edit.')
            return
          end

          selection = current_selection
          reset_target_if_selection_changed(selection)
          candidates = selection_candidates(selection)
          candidate = candidates.find { |item| item[:persistent_id] == persistent_id.to_s }

          unless candidate
            payload = build_state_payload
            send_state(dialog, payload)
            notify(dialog, 'warning', 'Unable to resolve the selected front. Please choose again.')
            return
          end

          instance = candidate[:instance]
          remember_target(instance, selection)
          params = read_params(instance)
          ready_payload = build_ready_payload(instance, params)
          send_state(dialog, ready_payload)
        rescue StandardError => e
          notify(dialog, 'error', "Unable to choose a front: #{e.message}")
        end
        private_class_method :handle_choose_target

        def handle_format_length(dialog, payload)
          value = payload && payload['value']
          length = parse_length(value)
          return unless length

          formatted = format_length(length)
          js = format('window.AICabinetsFronts && window.AICabinetsFronts.receiveFormatted(%s);',
                      JSON.generate(formatted))
          dialog.execute_script(js)
        rescue StandardError => e
          notify(dialog, 'error', "Format error: #{e.message}")
        end
        private_class_method :handle_format_length

        def send_state(dialog, payload)
          json = JSON.generate(payload)
          script = format('window.AICabinetsFronts && window.AICabinetsFronts.receiveState(%s);', json)
          dialog.execute_script(script)
        end
        private_class_method :send_state

        def send_validation_error(dialog, messages)
          json = JSON.generate(Array(messages))
          script = format('window.AICabinetsFronts && window.AICabinetsFronts.validationError(%s);', json)
          dialog.execute_script(script)
        end
        private_class_method :send_validation_error

        def notify(dialog, kind, message)
          payload = { kind: kind, message: message.to_s }
          json = JSON.generate(payload)
          script = format('window.AICabinetsFronts && window.AICabinetsFronts.notify(%s);', json)
          dialog.execute_script(script)
        end
        private_class_method :notify

        def front_tagged?(entity)
          layer = entity.layer if entity.respond_to?(:layer)
          return false unless layer

          layer_name = layer.respond_to?(:name) ? layer.name.to_s : ''
          return true if FRONT_TAG_NAMES.include?(layer_name)

          if layer_name.start_with?(AICabinets::Tags::OWNED_TAG_PREFIX)
            base_name = layer_name.split('/', 2).last
            return base_name == 'Fronts'
          end

          false
        end
        private_class_method :front_tagged?

        def read_params(instance)
          definition = instance.definition
          params = AICabinets::Params::FivePiece.read(definition)
          params[:door_thickness_mm] ||= Units.length_to_mm(definition.bounds.depth)
          params
        end
        private_class_method :read_params

        def serialize_state(instance, params)
          definition = instance.definition
          bbox = definition.bounds

          widths = {
            width_mm: Units.length_to_mm(bbox.width),
            height_mm: Units.length_to_mm(bbox.height),
            depth_mm: Units.length_to_mm(bbox.depth)
          }

          rail_width = params[:rail_width_mm]
          rail_width = params[:stile_width_mm] unless rail_width.is_a?(Numeric)

          drawer_action = last_drawer_rules_action(definition)
          door_style =
            if drawer_action == 'slab' || !five_piece_present?(definition)
              'slab'
            else
              params[:joint_type] == 'miter' ? 'five_piece_miter' : 'five_piece_cope_stick'
            end

          {
            ok: true,
            door_style: door_style,
            params: {
              stile_width_mm: params[:stile_width_mm],
              rail_width_mm: rail_width,
              drawer_rail_width_mm: params[:drawer_rail_width_mm],
              min_drawer_rail_width_mm: params[:min_drawer_rail_width_mm],
              min_panel_opening_mm: params[:min_panel_opening_mm],
              panel_style: params[:panel_style] || 'flat',
              panel_thickness_mm: params[:panel_thickness_mm],
              groove_depth_mm: params[:groove_depth_mm],
              groove_width_mm: params[:groove_width_mm],
              panel_cove_radius_mm: params[:panel_cove_radius_mm],
              panel_clearance_per_side_mm: params[:panel_clearance_per_side_mm],
              inside_profile_id: params[:inside_profile_id] || 'shaker_inside'
            },
            formatted: {
              stile_width: format_length(params[:stile_width_mm]),
              rail_width: format_length(rail_width),
              drawer_rail_width: format_length(params[:drawer_rail_width_mm]),
              min_drawer_rail_width: format_length(params[:min_drawer_rail_width_mm]),
              min_panel_opening: format_length(params[:min_panel_opening_mm]),
              panel_thickness: format_length(params[:panel_thickness_mm]),
              groove_depth: format_length(params[:groove_depth_mm]),
              groove_width: format_length(params[:groove_width_mm]),
              panel_cove_radius: format_length(params[:panel_cove_radius_mm]),
              panel_clearance_per_side: format_length(params[:panel_clearance_per_side_mm])
            },
            bounds_mm: widths,
            last_drawer_rules_action: last_drawer_rules_action(definition)
          }
        end
        private_class_method :serialize_state

        def build_ready_payload(instance, params)
          payload = serialize_state(instance, params)
          payload[:mode] = 'ready'
          payload[:target] = {
            persistent_id: persistent_id(instance),
            name: entity_label(instance),
            path_hint: entity_label(instance)
          }
          payload
        end
        private_class_method :build_ready_payload

        def build_choose_payload(candidates, text = nil)
          {
            mode: 'choose',
            candidates: candidates.map { |candidate| candidate_payload(candidate) },
            level: 'info',
            text: text || 'Multiple fronts found. Choose one to edit.'
          }
        end
        private_class_method :build_choose_payload

        def build_message_payload(level, text)
          {
            mode: 'message',
            level: level || 'info',
            text: text || DEFAULT_GUIDANCE
          }
        end
        private_class_method :build_message_payload

        def build_state_payload(defaults: false)
          selection = current_selection
          reset_target_if_selection_changed(selection)

          resolution = resolve_selection(selection, prefer_pid: @target_persistent_id)
          case resolution[:mode]
          when :ready
            instance = resolution[:instance]
            remember_target(instance, selection)
            params = defaults ? AICabinets::Params::FivePiece.defaults : read_params(instance)
            build_ready_payload(instance, params)
          when :choose
            build_choose_payload(resolution[:candidates], resolution[:text])
          when :message
            build_message_payload(resolution[:level], resolution[:text])
          else
            build_message_payload('warning', DEFAULT_GUIDANCE)
          end
        end
        private_class_method :build_state_payload

        def current_front_instance
          selection = current_selection
          reset_target_if_selection_changed(selection)
          resolution = resolve_selection(selection, prefer_pid: @target_persistent_id)
          return nil unless resolution[:mode] == :ready

          instance = resolution[:instance]
          remember_target(instance, selection)
          instance
        end
        private_class_method :current_front_instance

        def resolve_selection(selection, prefer_pid: nil)
          unless selection&.count == 1
            return { mode: :message, level: 'info', text: DEFAULT_GUIDANCE }
          end

          entity = selection.first
          front_instance = direct_front_instance(entity)
          front_instance ||= front_instance_from_active_path(Sketchup.active_model)
          front_instance ||= front_instance_from_part(entity)

          return { mode: :ready, instance: front_instance } if front_instance

          candidates = selection_candidates(selection)
          if candidates.empty?
            return {
              mode: :message,
              level: 'warning',
              text: 'The selected component does not contain AI Cabinets fronts.'
            }
          end

          if prefer_pid
            candidate = candidates.find { |item| item[:persistent_id] == prefer_pid.to_s }
            return { mode: :ready, instance: candidate[:instance] } if candidate
          end

          return { mode: :ready, instance: candidates.first[:instance] } if candidates.length == 1

          { mode: :choose, candidates: candidates, text: 'Multiple fronts found. Choose one to edit.' }
        end
        private_class_method :resolve_selection

        def direct_front_instance(entity)
          return unless entity&.valid?
          return entity if entity.is_a?(Sketchup::ComponentInstance) && front_tagged?(entity)

          nil
        end
        private_class_method :direct_front_instance

        def front_instance_from_part(entity)
          return unless entity&.valid?
          return unless front_tagged?(entity)

          instance = front_instance_from_active_path(Sketchup.active_model)
          return instance if instance

          definition = entity_parent_definition(entity)
          candidates = definition&.instances&.grep(Sketchup::ComponentInstance)&.select { |inst| front_tagged?(inst) }
          return candidates.first if candidates&.length == 1

          nil
        end
        private_class_method :front_instance_from_part

        def entity_parent_definition(entity)
          parent_entities = entity.respond_to?(:parent) ? entity.parent : nil
          return unless parent_entities.respond_to?(:parent)

          parent_entities.parent if parent_entities.parent.is_a?(Sketchup::ComponentDefinition)
        end
        private_class_method :entity_parent_definition

        def front_instance_from_active_path(model)
          path = current_active_path(model)
          return unless path.respond_to?(:reverse_each)

          path.reverse_each do |item|
            next unless item.is_a?(Sketchup::ComponentInstance)
            return item if front_tagged?(item)
          end

          nil
        end
        private_class_method :front_instance_from_active_path

        def selection_candidates(selection)
          return [] unless selection&.count == 1

          entity = selection.first
          candidates_for_entity(entity)
        end
        private_class_method :selection_candidates

        def candidates_for_entity(entity)
          case entity
          when Sketchup::ComponentInstance
            definition = entity.definition
            collect_front_candidates(definition&.entities, base_path: [entity_label(entity)])
          when Sketchup::Group
            collect_front_candidates(entity.entities, base_path: [entity_label(entity)])
          else
            []
          end
        end
        private_class_method :candidates_for_entity

        def collect_front_candidates(entities, base_path:, depth: 0, visited: Set.new)
          return [] unless entities.is_a?(Sketchup::Entities)
          return [] if depth > 10

          entities.each_with_object([]) do |child, memo|
            next unless child&.valid?

            if child.is_a?(Sketchup::ComponentInstance)
              if front_tagged?(child)
                pid = persistent_id(child)
                next unless pid

                memo << {
                  instance: child,
                  persistent_id: pid,
                  name: entity_label(child),
                  path_hint: build_path_hint(base_path, child)
                }
                next
              end

              definition = child.definition
              next unless definition

              key = definition.object_id
              next if visited.include?(key)

              visited << key
              child_path = base_path + [entity_label(child)]
              memo.concat(collect_front_candidates(definition.entities,
                                                   base_path: child_path,
                                                   depth: depth + 1,
                                                   visited: visited))
            elsif child.is_a?(Sketchup::Group)
              child_path = base_path + [entity_label(child)]
              memo.concat(collect_front_candidates(child.entities,
                                                   base_path: child_path,
                                                   depth: depth + 1,
                                                   visited: visited))
            end
          end
        end
        private_class_method :collect_front_candidates

        def candidate_payload(candidate)
          {
            persistent_id: candidate[:persistent_id],
            name: candidate[:name],
            path_hint: candidate[:path_hint]
          }
        end
        private_class_method :candidate_payload

        def remember_target(instance, selection)
          @target_persistent_id = persistent_id(instance)
          @target_selection_signature = selection_signature(selection)
        end
        private_class_method :remember_target

        def reset_target_if_selection_changed(selection)
          signature = selection_signature(selection)
          return if @target_selection_signature == signature

          @target_selection_signature = signature
          @target_persistent_id = nil
        end
        private_class_method :reset_target_if_selection_changed

        def selection_signature(selection)
          model = Sketchup.active_model
          path = current_active_path(model)
          ids =
            if path && !path.empty?
              path.filter_map { |entity| persistent_id(entity) }
            elsif selection && selection.respond_to?(:each)
              selection.map { |entity| persistent_id(entity) }
            else
              []
            end

          ids.empty? ? nil : ids
        end
        private_class_method :selection_signature

        def current_active_path(model)
          override = @active_path_override
          return Array(override) if override

          return unless model.respond_to?(:active_path)

          model.active_path
        end
        private_class_method :current_active_path

        def current_selection
          return nil unless defined?(Sketchup)

          model = Sketchup.active_model
          model&.selection
        end
        private_class_method :current_selection

        def persistent_id(entity)
          return unless entity&.valid?
          return unless entity.respond_to?(:persistent_id)

          value = entity.persistent_id
          value ? value.to_s : nil
        rescue StandardError
          nil
        end
        private_class_method :persistent_id

        def entity_label(entity)
          return '' unless entity

          name = entity.respond_to?(:name) ? entity.name.to_s : ''
          return name unless name.empty?

          definition = entity.respond_to?(:definition) ? entity.definition : nil
          definition_name = definition && definition.respond_to?(:name) ? definition.name.to_s : ''
          return definition_name unless definition_name.empty?

          entity.respond_to?(:typename) ? entity.typename.to_s : entity.class.name
        end
        private_class_method :entity_label

        def build_path_hint(base_path, entity)
          (Array(base_path) + [entity_label(entity)]).compact.join(' › ')
        end
        private_class_method :build_path_hint

        def parse_payload(payload)
          data = payload.is_a?(Hash) ? payload : {}
          params = {}

          params[:door_type] = 'five_piece'
          params[:joint_type] = parse_joint_type(data['door_style'])
          params[:inside_profile_id] = data['inside_profile_id'] || 'square_inside'
          params[:stile_width_mm] = parse_length(data['stile_width'])
          params[:rail_width_mm] = parse_optional_length(data['rail_width'])
          params[:drawer_rail_width_mm] = parse_optional_length(data['drawer_rail_width'])
          params[:min_drawer_rail_width_mm] = parse_length(data['min_drawer_rail_width'])
          params[:min_panel_opening_mm] = parse_length(data['min_panel_opening'])
          params[:panel_style] = parse_panel_style(data['panel_style'])
          params[:panel_thickness_mm] = parse_length(data['panel_thickness'])
          params[:groove_depth_mm] = parse_length(data['groove_depth'])
          params[:groove_width_mm] = parse_optional_length(data['groove_width'])
          params[:panel_cove_radius_mm] = parse_optional_length(data['panel_cove_radius'])
          params[:panel_clearance_per_side_mm] = parse_length(data['panel_clearance_per_side'])
          params[:door_thickness_mm] = parse_length(data['door_thickness']) if data.key?('door_thickness')

          params
        end
        private_class_method :parse_payload

        def parse_joint_type(value)
          case value
          when 'five_piece_miter'
            'miter'
          else
            'cope_stick'
          end
        end
        private_class_method :parse_joint_type

        def parse_panel_style(value)
          case value
          when 'raised', :raised
            :raised
          when 'reverse_raised', :reverse_raised
            :reverse_raised
          else
            :flat
          end
        end
        private_class_method :parse_panel_style

        def parse_length(value)
          length = parse_length_value(value)
          Units.length_to_mm(length)
        end
        private_class_method :parse_length

        def parse_optional_length(value)
          return nil if value.nil? || value.to_s.strip.empty?

          parse_length(value)
        end
        private_class_method :parse_optional_length

        def parse_length_value(value)
          raise AICabinets::ValidationError, ['Length value is required'] if value.nil? || value.to_s.strip.empty?

          numeric =
            case value
            when Numeric
              value
            else
              begin
                value.to_s.to_l
              rescue StandardError
                nil
              end
            end
          raise AICabinets::ValidationError, ['Enter a numeric length with units (e.g., 57 mm).'] unless numeric

          numeric
        end
        private_class_method :parse_length_value

        def normalize_scope(payload)
          scope = payload.is_a?(Hash) ? payload['scope'] : nil
          scope == 'instance' ? :instance : :definition
        end
        private_class_method :normalize_scope

        def ensure_unique_instance(instance)
          return instance.definition unless instance.respond_to?(:make_unique)

          instance.make_unique
          instance.definition
        end
        private_class_method :ensure_unique_instance

        def regenerate_front_impl(target, params)
          definition = ensure_definition(target)
          bbox = definition.bounds
          width_mm = Units.length_to_mm(bbox.width)
          height_mm = Units.length_to_mm(bbox.depth)
          thickness_mm = params[:door_thickness_mm] || Units.length_to_mm(bbox.height)

          params[:door_thickness_mm] = thickness_mm
          params[:rail_width_mm] ||= params[:stile_width_mm]

          result = { decision: nil, warnings: [] }
          drawer = drawer_front?(target)

          if drawer
            decision = AICabinets::Rules::FivePiece.evaluate_drawer_front(
              _open_outside_w_mm: width_mm,
              open_outside_h_mm: height_mm,
              params: params
            )
            record_drawer_decision(definition, decision)
            result[:decision] = decision
            result[:warnings].concat(Array(decision.messages))

            case decision.action
            when :slab
              rebuild_slab(definition)
              return result
            when :five_piece
              params[:rail_width_mm] = decision.effective_rail_mm
            end
          end

          clamp_frame_member_widths!(
            params,
            finished_w_mm: width_mm,
            finished_h_mm: height_mm,
            min_panel_opening_mm: drawer ? params[:min_panel_opening_mm].to_f : MIN_PANEL_OPENING_MM,
            min_rail_width_mm: drawer ? params[:min_drawer_rail_width_mm].to_f : nil
          )

          definition.entities.clear!

          frame_result = AICabinets::Geometry::FivePiece.build_frame!(
            target: definition,
            params: params,
            finished_w_mm: width_mm,
            finished_h_mm: height_mm
          )

          open_w_mm = frame_result[:opening_w_mm]
          open_h_mm = frame_result[:opening_h_mm]
          open_w_mm ||= width_mm - (2.0 * params[:stile_width_mm].to_f)
          open_h_mm ||= height_mm - (2.0 * params[:rail_width_mm].to_f)

          panel_result = AICabinets::Geometry::FivePiecePanel.build_panel!(
            target: definition,
            params: params,
            style: params[:panel_style],
            cove_radius_mm: params[:panel_cove_radius_mm],
            open_w_mm: open_w_mm,
            open_h_mm: open_h_mm
          )

          AICabinets::Metadata.write_five_piece!(
            definition: definition,
            params: params,
            parts: {
              stiles: frame_result[:stiles],
              rails: frame_result[:rails],
              panel: panel_result[:panel]
            }
          )
          AICabinets::Params::FivePiece.write!(definition, params: params, scope: :definition)

          result
        end
        module_function :regenerate_front_impl
        private_class_method :regenerate_front_impl

        def self.regenerate_front(target, params)
          regenerate_front_impl(target, params)
        end
        private_class_method :regenerate_front

        def clamp_frame_member_widths!(params, finished_w_mm:, finished_h_mm:, min_panel_opening_mm: MIN_PANEL_OPENING_MM,
                                       min_rail_width_mm: nil)
          stile_width_mm = params[:stile_width_mm].to_f
          rail_width_mm = params[:rail_width_mm]
          rail_width_mm = stile_width_mm unless rail_width_mm.is_a?(Numeric)

          clearance_mm = params[:panel_clearance_per_side_mm].to_f

          stile_limit = frame_member_limit(
            finished_w_mm,
            label: 'Door width',
            clearance_mm: clearance_mm,
            min_panel_opening_mm: min_panel_opening_mm
          )
          rail_limit = frame_member_limit(
            finished_h_mm,
            label: 'Door height',
            clearance_mm: clearance_mm,
            min_panel_opening_mm: min_panel_opening_mm
          )

          min_stile = minimum_stile_requirement_mm(params)
          if stile_limit < min_stile
            raise AICabinets::ValidationError,
                  [format('Door width %.2f mm cannot accommodate stile width %.2f mm.', finished_w_mm, min_stile)]
          end

          clamped_stile = [stile_width_mm, stile_limit].min
          params[:stile_width_mm] = clamped_stile

          clamped_rail = [rail_width_mm.to_f, rail_limit].min
          min_rail_width = [clamped_stile / 2.0, min_rail_width_mm.to_f].compact.max
          if clamped_rail < min_rail_width
            if rail_limit < min_rail_width
              raise AICabinets::ValidationError,
                    [format('Door height %.2f mm cannot accommodate rail width %.2f mm.',
                            finished_h_mm, min_rail_width)]
            end
            clamped_rail = min_rail_width
          end
          params[:rail_width_mm] = clamped_rail
        end
        private_class_method :clamp_frame_member_widths!

        def frame_member_limit(total_mm, label:, clearance_mm:, min_panel_opening_mm: MIN_PANEL_OPENING_MM)
          numeric = Float(total_mm)
          required_opening = (clearance_mm * 2.0) + min_panel_opening_mm.to_f
          limit = (numeric - required_opening) / 2.0
          if limit <= 0.0
            raise AICabinets::ValidationError,
                  [format('%s %.2f mm is too small for a %.2f mm panel opening (including clearances).',
                          label, numeric, required_opening)]
          end

          limit
        rescue ArgumentError, TypeError
          raise AICabinets::ValidationError, [format('%s is invalid.', label)]
        end
        private_class_method :frame_member_limit

        def minimum_stile_requirement_mm(params)
          joint_type = params[:joint_type] || 'cope_stick'
          joint_min =
            AICabinets::Params::FivePiece::MIN_STILE_WIDTH_BY_JOINT_MM.fetch(
              joint_type
            ) do
              AICabinets::Params::FivePiece::MIN_STILE_WIDTH_BY_JOINT_MM.values.max
            end

          groove_depth = params[:groove_depth_mm].to_f
          groove_min = (groove_depth * 2.0) + AICabinets::Params::FivePiece::GROOVE_DEPTH_BUFFER_MM

          [joint_min, groove_min].max
        end
        private_class_method :minimum_stile_requirement_mm

        def rebuild_slab(target)
          definition = ensure_definition(target)
          bbox = definition.bounds
          width = bbox.width
          height = bbox.height
          thickness = bbox.depth

          definition.entities.clear!

          face = definition.entities.add_face(
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(width, 0, 0),
            Geom::Point3d.new(width, 0, height),
            Geom::Point3d.new(0, 0, height)
          )
          face.reverse! if face.normal.y.positive?
          face.pushpull(thickness)
        end
        private_class_method :rebuild_slab

        def clear_five_piece_attributes(definition)
          return unless definition.respond_to?(:attribute_dictionary)

          dictionary = definition.attribute_dictionary(AICabinets::Params::FivePiece::DICTIONARY_NAME, false)
          return unless dictionary

          keys = dictionary.keys.grep(/^#{AICabinets::Params::FivePiece::STORAGE_PREFIX}/)
          keys.each do |key|
            definition.delete_attribute(AICabinets::Params::FivePiece::DICTIONARY_NAME, key)
          end
        end
        private_class_method :clear_five_piece_attributes

        def five_piece_present?(definition)
          return false unless definition.respond_to?(:attribute_dictionary)

          dictionary = definition.attribute_dictionary(AICabinets::Params::FivePiece::DICTIONARY_NAME, false)
          return false unless dictionary

          dictionary.keys.any? do |key|
            key.to_s.start_with?(AICabinets::Params::FivePiece::STORAGE_PREFIX)
          end
        end
        private_class_method :five_piece_present?

        def drawer_front?(target)
          definition = ensure_definition(target)
          dictionary = definition.attribute_dictionary(AICabinets::Params::FivePiece::DICTIONARY_NAME, false)
          role = dictionary && dictionary['front_role']
          role ||= definition.get_attribute(AICabinets::Params::FivePiece::DICTIONARY_NAME, 'front_role') if
                    definition.respond_to?(:get_attribute)

          names = []
          names << target.name if target.respond_to?(:name)
          names << definition.name if definition.respond_to?(:name)

          name_hint = names.any? { |value| value.to_s.downcase.include?('drawer') }
          role_hint = role && role.to_s.downcase == 'drawer'

          role_hint || name_hint
        end
        private_class_method :drawer_front?

        def record_drawer_decision(definition, decision)
          return unless definition.respond_to?(:set_attribute)

          dictionary = AICabinets::Params::FivePiece::DICTIONARY_NAME
          definition.set_attribute(dictionary, 'five_piece:last_drawer_rules_action', decision&.action.to_s)
          definition.set_attribute(dictionary, 'five_piece:last_drawer_rules_reason', decision&.reason.to_s)
          definition.set_attribute(dictionary, 'five_piece:last_drawer_panel_h_mm', decision&.panel_h_mm.to_f)
        end
        private_class_method :record_drawer_decision

        def last_drawer_rules_action(definition)
          return unless definition.respond_to?(:get_attribute)

          action = definition.get_attribute(
            AICabinets::Params::FivePiece::DICTIONARY_NAME,
            'five_piece:last_drawer_rules_action'
          )

          action && !action.to_s.empty? ? action.to_s : nil
        end
        private_class_method :last_drawer_rules_action

        def ensure_definition(target)
          definition_class = sketchup_class(:ComponentDefinition)
          if target.is_a?(definition_class)
            target
          elsif target.respond_to?(:definition)
            target.definition
          else
            raise ArgumentError, 'Expected a ComponentDefinition or ComponentInstance'
          end
        end
        private_class_method :ensure_definition

        def html_dialog_available?
          defined?(::UI::HtmlDialog)
        end
        private_class_method :html_dialog_available?

        def set_dialog_file(dialog)
          html_path = File.join(__dir__, HTML_FILENAME)
          return warn_missing_asset(html_path) unless File.exist?(html_path)

          dialog.set_file(html_path)
        end
        private_class_method :set_dialog_file

        def warn_missing_asset(path)
          warn("AI Cabinets: Unable to locate dialog asset: #{path}")
        end
        private_class_method :warn_missing_asset

        def format_length(value_mm)
          return '' unless value_mm

          length = Units.to_length_mm(value_mm)
          Sketchup.format_length(length)
        end
        private_class_method :format_length

        def test_mode?
          false
        end
        private_class_method :test_mode?

        def sketchup_class(name)
          Sketchup.const_get(name) if defined?(Sketchup) && Sketchup.const_defined?(name)
        end
        private_class_method :sketchup_class
      end
    end
  end
end


