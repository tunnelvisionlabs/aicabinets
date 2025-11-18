# frozen_string_literal: true

require 'json'

require 'aicabinets/geometry/five_piece'
require 'aicabinets/geometry/five_piece_panel'
require 'aicabinets/generator/fronts'
require 'aicabinets/ops/tags'
require 'aicabinets/ops/units'
require 'aicabinets/params/five_piece'
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
          instance = selected_front_instance
          unless instance
            notify(dialog, 'error', 'Select a single AI Cabinets front component to edit.')
            return
          end

          params = read_params(instance)
          payload = serialize_state(instance, params)
          send_state(dialog, payload)
        rescue StandardError => e
          notify(dialog, 'error', "Unable to load current state: #{e.message}")
        end
        private_class_method :deliver_state

        def deliver_defaults(dialog)
          instance = selected_front_instance
          params = AICabinets::Params::FivePiece.defaults
          payload = serialize_state(instance, params)
          send_state(dialog, payload)
        rescue StandardError => e
          notify(dialog, 'error', "Unable to load defaults: #{e.message}")
        end
        private_class_method :deliver_defaults

        def handle_apply(dialog, payload)
          instance = selected_front_instance
          unless instance
            notify(dialog, 'error', 'Select a single AI Cabinets front component to edit.')
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
            regenerate_front_impl(target, sanitized)
            notify(dialog, 'info', 'Five-piece settings applied.')
          end

          deliver_state(dialog)
        rescue AICabinets::ValidationError => e
          send_validation_error(dialog, Array(e.messages))
        rescue StandardError => e
          notify(dialog, 'error', "Apply failed: #{e.message}")
        end
        private_class_method :handle_apply

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

        def selected_front_instance
          return nil unless defined?(Sketchup)

          model = Sketchup.active_model
          selection = model&.selection
          return nil unless selection&.count == 1

          entity = selection.first
          return nil unless entity.is_a?(Sketchup::ComponentInstance)
          return nil unless front_tagged?(entity)

          entity
        end
        private_class_method :selected_front_instance

        def front_tagged?(entity)
          layer = entity.layer if entity.respond_to?(:layer)
          return false unless layer

          layer_name = layer.respond_to?(:name) ? layer.name : nil
          layer_name.to_s == AICabinets::Generator::Fronts::FRONTS_TAG_NAME
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

          door_style =
            if five_piece_present?(definition)
              params[:joint_type] == 'miter' ? 'five_piece_miter' : 'five_piece_cope_stick'
            else
              'slab'
            end

          {
            ok: true,
            door_style: door_style,
            params: {
              stile_width_mm: params[:stile_width_mm],
              rail_width_mm: rail_width,
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
              panel_thickness: format_length(params[:panel_thickness_mm]),
              groove_depth: format_length(params[:groove_depth_mm]),
              groove_width: format_length(params[:groove_width_mm]),
              panel_cove_radius: format_length(params[:panel_cove_radius_mm]),
              panel_clearance_per_side: format_length(params[:panel_clearance_per_side_mm])
            },
            bounds_mm: widths
          }
        end
        private_class_method :serialize_state

        def parse_payload(payload)
          data = payload.is_a?(Hash) ? payload : {}
          params = {}

          params[:door_type] = 'five_piece'
          params[:joint_type] = parse_joint_type(data['door_style'])
          params[:inside_profile_id] = data['inside_profile_id'] || 'square_inside'
          params[:stile_width_mm] = parse_length(data['stile_width'])
          params[:rail_width_mm] = parse_optional_length(data['rail_width'])
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

          clamp_frame_member_widths!(
            params,
            finished_w_mm: width_mm,
            finished_h_mm: height_mm
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

          AICabinets::Geometry::FivePiecePanel.build_panel!(
            target: definition,
            params: params,
            style: params[:panel_style],
            cove_radius_mm: params[:panel_cove_radius_mm],
            open_w_mm: open_w_mm,
            open_h_mm: open_h_mm
          )
        end
        module_function :regenerate_front_impl
        private_class_method :regenerate_front_impl

        def self.regenerate_front(target, params)
          regenerate_front_impl(target, params)
        end
        private_class_method :regenerate_front

        def clamp_frame_member_widths!(params, finished_w_mm:, finished_h_mm:)
          stile_width_mm = params[:stile_width_mm].to_f
          rail_width_mm = params[:rail_width_mm]
          rail_width_mm = stile_width_mm unless rail_width_mm.is_a?(Numeric)

          clearance_mm = params[:panel_clearance_per_side_mm].to_f

          stile_limit = frame_member_limit(finished_w_mm, label: 'Door width', clearance_mm: clearance_mm)
          rail_limit = frame_member_limit(finished_h_mm, label: 'Door height', clearance_mm: clearance_mm)

          min_stile = minimum_stile_requirement_mm(params)
          if stile_limit < min_stile
            raise AICabinets::ValidationError,
                  [format('Door width %.2f mm cannot accommodate stile width %.2f mm.', finished_w_mm, min_stile)]
          end

          clamped_stile = [stile_width_mm, stile_limit].min
          params[:stile_width_mm] = clamped_stile

          clamped_rail = [rail_width_mm.to_f, rail_limit].min
          min_rail_width = clamped_stile / 2.0
          if clamped_rail < min_rail_width
            if rail_limit < min_rail_width
              raise AICabinets::ValidationError,
                    [format('Door height %.2f mm cannot accommodate rail width %.2f mm (half of clamped stile %.2f mm).',
                            finished_h_mm, min_rail_width, clamped_stile)]
            end
            clamped_rail = min_rail_width
          end
          params[:rail_width_mm] = clamped_rail
        end
        private_class_method :clamp_frame_member_widths!

        def frame_member_limit(total_mm, label:, clearance_mm:)
          numeric = Float(total_mm)
          required_opening = (clearance_mm * 2.0) + MIN_PANEL_OPENING_MM
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


