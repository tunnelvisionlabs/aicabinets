# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'time'
require 'sketchup.rb'

Sketchup.require('aicabinets/rows/reflow')
Sketchup.require('aicabinets/rows/reveal')
Sketchup.require('aicabinets/rows/regeneration')

module AICabinets
  module Rows
    Result = Struct.new(:ok, :code, :message, keyword_init: true) do
      def ok?
        ok
      end
    end

    class RowError < StandardError
      attr_reader :code

      def initialize(code, message)
        super(message)
        @code = code
      end
    end

    module_function

    MODEL_DICTIONARY = 'AICabinets.Rows'.freeze
    MODEL_JSON_KEY = 'json'.freeze
    INSTANCE_DICTIONARY = 'AICabinets.Row'.freeze
    ROW_ID_KEY = 'row_id'.freeze
    ROW_POS_KEY = 'row_pos'.freeze
    SCHEMA_VERSION = 1
    DEFAULT_ROW_REVEAL_MM = 2.0
    COLLINEAR_TOLERANCE_MM = 0.5
    OPERATION_NAME = 'AI Cabinets — Create Row'.freeze
    MANAGE_OPERATION_NAME = 'AI Cabinets — Manage Row'.freeze
    ROW_HIGHLIGHT_OVERLAY_ID = 'AICabinets.Rows.Highlight'.freeze

    def create_from_selection(model:, reveal_mm: nil, lock_total_length: false)
      model = validate_model(model)

      reveal_value = coerce_row_reveal_mm(reveal_mm)
      unless reveal_value
        return Result.new(
          ok: false,
          code: :invalid_reveal,
          message: 'Row reveal must be expressed in millimeters.'
        )
      end

      selection_result = validate_selection(model)
      return selection_result unless selection_result.is_a?(Array)

      instances = selection_result
      row_id = SecureRandom.uuid
      timestamp = Time.now.utc.iso8601

      member_pids = instances.map { |instance| instance.persistent_id.to_i }
      row_payload = {
        'row_id' => row_id,
        'member_pids' => member_pids,
        'row_reveal_mm' => reveal_value,
        'lock_total_length' => !!lock_total_length,
        'total_length_mm' => nil,
        'created_at' => timestamp,
        'updated_at' => timestamp
      }

      operation_open = false
      model.start_operation(OPERATION_NAME, true)
      operation_open = true

      state, state_changed = load_state(model)
      state_changed ||= repair_state!(model, state)
      state['rows'][row_id] = row_payload
      row_added = true

      instances.each_with_index do |instance, index|
        ensure_instance_membership(instance, row_id, index + 1)
      end

      state_changed ||= cleanup_orphaned_instance_memberships(model, state['rows'])
      state_changed ||= sanitize_rows!(state)

      write_state(model, state) if state_changed || row_added

      model.commit_operation
      operation_open = false

      row_id
    rescue StandardError
      model.abort_operation if operation_open
      raise
    end

    def list_summary(model)
      model = validate_model(model)

      state, changed = prepare_state(model)
      write_state(model, state) if changed

      state['rows'].values.map { |row| build_row_summary(row) }
    end

    def get_row(model:, row_id:)
      model = validate_model(model)
      row_id = validate_row_id(row_id)

      state, changed = prepare_state(model)
      row = state['rows'][row_id]
      raise RowError.new(:unknown_row, 'Row not found.') unless row

      detail = build_row_detail(model, row)
      write_state(model, state) if changed

      detail
    end

    def add_members(model:, row_id:, member_pids:)
      model = validate_model(model)
      row_id = validate_row_id(row_id)
      pids = normalize_pids(member_pids)
      raise RowError.new(:invalid_members, 'Specify at least one cabinet to add.') if pids.empty?

      state, = prepare_state(model)
      row = state['rows'][row_id]
      raise RowError.new(:unknown_row, 'Row not found.') unless row

      instances = resolve_member_instances(model, pids)
      if instances.length != pids.length
        raise RowError.new(:invalid_members, 'Some cabinets are missing or invalid.')
      end

      validate_instances_for_row!(instances, current_row_id: row_id)

      operation_open = false
      model.start_operation(MANAGE_OPERATION_NAME, true)
      operation_open = true

      existing_instances = resolve_member_instances(model, row['member_pids'])
      updated_instances = merge_instances(existing_instances, instances)

      if updated_instances.empty?
        model.abort_operation
        operation_open = false
        raise RowError.new(:invalid_members, 'Unable to determine row membership after update.')
      end

      apply_row_membership!(model, row, updated_instances, state['rows'])

      write_state(model, state)
      update_highlight_if_active(model, row)
      trigger_regeneration(model, row)

      model.commit_operation
      operation_open = false

      build_row_detail(model, row)
    rescue StandardError
      model.abort_operation if operation_open
      raise
    end

    def remove_members(model:, row_id:, member_pids:)
      model = validate_model(model)
      row_id = validate_row_id(row_id)
      pids = normalize_pids(member_pids)
      raise RowError.new(:invalid_members, 'Specify at least one cabinet to remove.') if pids.empty?

      state, = prepare_state(model)
      row = state['rows'][row_id]
      raise RowError.new(:unknown_row, 'Row not found.') unless row

      original_instances = resolve_member_instances(model, row['member_pids'])
      updated_instances = original_instances.reject { |instance| pids.include?(instance.persistent_id.to_i) }

      operation_open = false
      model.start_operation(MANAGE_OPERATION_NAME, true)
      operation_open = true

      removed = original_instances.length - updated_instances.length
      if removed.zero?
        model.abort_operation
        operation_open = false
        raise RowError.new(:invalid_members, 'Selected cabinets are not part of the row.')
      end

      apply_row_membership!(model, row, updated_instances, state['rows'])

      write_state(model, state)
      update_highlight_if_active(model, row)
      trigger_regeneration(model, row)

      model.commit_operation
      operation_open = false

      build_row_detail(model, row)
    rescue StandardError
      model.abort_operation if operation_open
      raise
    end

    def reorder(model:, row_id:, order:)
      model = validate_model(model)
      row_id = validate_row_id(row_id)
      order_pids = normalize_pids(order)
      raise RowError.new(:invalid_order, 'Specify the desired cabinet order.') if order_pids.empty?

      state, = prepare_state(model)
      row = state['rows'][row_id]
      raise RowError.new(:unknown_row, 'Row not found.') unless row

      current_instances = resolve_member_instances(model, row['member_pids'])
      if current_instances.length != order_pids.length
        raise RowError.new(:invalid_order, 'Order must reference all cabinets in the row.')
      end

      order_lookup = order_pids.each_with_index.to_h
      unless current_instances.all? { |instance| order_lookup.key?(instance.persistent_id.to_i) }
        raise RowError.new(:invalid_order, 'Order contains an unknown cabinet.')
      end

      reordered = current_instances.sort_by { |instance| order_lookup.fetch(instance.persistent_id.to_i) }

      operation_open = false
      model.start_operation(MANAGE_OPERATION_NAME, true)
      operation_open = true

      apply_row_membership!(model, row, reordered, state['rows'])

      write_state(model, state)
      update_highlight_if_active(model, row)
      trigger_regeneration(model, row)

      model.commit_operation
      operation_open = false

      build_row_detail(model, row)
    rescue StandardError
      model.abort_operation if operation_open
      raise
    end

    def update(model:, row_id:, row_reveal_mm: nil, lock_total_length: nil)
      model = validate_model(model)
      row_id = validate_row_id(row_id)

      state, = prepare_state(model)
      row = state['rows'][row_id]
      raise RowError.new(:unknown_row, 'Row not found.') unless row

      attributes_changed = false

      if !row_reveal_mm.nil?
        reveal_value = coerce_row_reveal_mm(row_reveal_mm)
        unless reveal_value
          raise RowError.new(:invalid_reveal, 'Reveal must be expressed in millimeters.')
        end

        current_reveal = (row['row_reveal_mm'] || 0.0).to_f
        if (current_reveal - reveal_value).abs > Float::EPSILON
          row['row_reveal_mm'] = reveal_value
          attributes_changed = true
        end
      end

      unless lock_total_length.nil?
        lock_value = !!lock_total_length
        if row['lock_total_length'] != lock_value
          row['lock_total_length'] = lock_value
          attributes_changed = true
        end
      end

      return build_row_detail(model, row) unless attributes_changed

      operation_open = false
      model.start_operation(MANAGE_OPERATION_NAME, true)
      operation_open = true

      row['updated_at'] = Time.now.utc.iso8601
      write_state(model, state)
      trigger_regeneration(model, row)

      model.commit_operation
      operation_open = false

      build_row_detail(model, row)
    rescue StandardError
      model.abort_operation if operation_open
      raise
    end

    def highlight(model:, row_id:, enabled:)
      model = validate_model(model)
      row_id = validate_row_id(row_id)

      state, changed = prepare_state(model)
      row = state['rows'][row_id]
      raise RowError.new(:unknown_row, 'Row not found.') unless row

      instances = resolve_member_instances(model, row['member_pids'])
      if enabled
        ensure_overlay(model).update(instances)
        highlight_state(model)[:row_id] = row_id
      else
        clear_overlay(model)
        highlight_state(model).delete(:row_id)
      end

      write_state(model, state) if changed

      { ok: true }
    end

    def list(model)
      model = validate_model(model)

      state, changed = prepare_state(model)
      write_state(model, state) if changed

      state['rows'].values.map { |row| symbolize_row(row) }
    end

    def for_instance(instance)
      return unless instance.respond_to?(:attribute_dictionary)

      dictionary = instance.attribute_dictionary(INSTANCE_DICTIONARY)
      return unless dictionary

      row_id = dictionary[ROW_ID_KEY]
      row_pos = dictionary[ROW_POS_KEY]
      return unless row_id.is_a?(String) && !row_id.empty?

      { row_id:, row_pos: row_pos.to_i }
    end

    def migrate!(state)
      return false unless state.is_a?(Hash)

      version = state['schema_version']
      changed = false

      unless version.is_a?(Integer)
        state['schema_version'] = SCHEMA_VERSION
        version = SCHEMA_VERSION
        changed = true
      end

      if version > SCHEMA_VERSION
        warn(
          "AI Cabinets: Rows schema version #{version} is newer than supported #{SCHEMA_VERSION}."
        )
        return changed
      end

      if version < SCHEMA_VERSION
        state['schema_version'] = SCHEMA_VERSION
        changed = true
      end

      changed
    end

    def validate_model(model)
      return model if model.is_a?(Sketchup::Model)

      default_model = defined?(Sketchup) ? Sketchup.active_model : nil
      return default_model if default_model.is_a?(Sketchup::Model)

      raise ArgumentError, 'model must be a SketchUp::Model'
    end
    private_class_method :validate_model

    def coerce_row_reveal_mm(value)
      return DEFAULT_ROW_REVEAL_MM if value.nil?

      mm_value = length_to_mm(value)
      return unless mm_value

      mm_value
    end
    private_class_method :coerce_row_reveal_mm

    def prepare_state(model)
      state, changed = load_state(model)
      changed |= repair_state!(model, state)
      changed |= sanitize_rows!(state)
      [state, changed]
    end
    private_class_method :prepare_state

    def build_row_summary(row)
      {
        row_id: row['row_id'],
        name: row['name'],
        member_count: Array(row['member_pids']).length,
        lock_total_length: !!row['lock_total_length'],
        row_reveal_mm: row['row_reveal_mm'],
        row_reveal_formatted: format_length(row['row_reveal_mm'])
      }
    end
    private_class_method :build_row_summary

    def build_row_detail(model, row)
      instances = resolve_member_instances(model, row['member_pids'])
      members = instances.each_with_index.map do |instance, index|
        {
          pid: instance.persistent_id.to_i,
          label: member_label(instance, index + 1),
          row_pos: index + 1
        }
      end

      {
        row: {
          row_id: row['row_id'],
          name: row['name'],
          member_pids: members.map { |member| member[:pid] },
          members: members,
          row_reveal_mm: row['row_reveal_mm'],
          row_reveal_formatted: format_length(row['row_reveal_mm']),
          lock_total_length: !!row['lock_total_length']
        }
      }
    end
    private_class_method :build_row_detail

    def member_label(instance, fallback_index)
      return "Cabinet ##{fallback_index}" unless instance&.valid?

      if instance.respond_to?(:name) && !instance.name.to_s.empty?
        return instance.name
      end

      definition = instance.definition if instance.respond_to?(:definition)
      if definition && definition.respond_to?(:name) && !definition.name.to_s.empty?
        return definition.name
      end

      "Cabinet ##{fallback_index}"
    end
    private_class_method :member_label

    def validate_row_id(row_id)
      value = row_id.to_s.strip
      return value unless value.empty?

      raise RowError.new(:invalid_row_id, 'Row id must be provided.')
    end
    private_class_method :validate_row_id

    def normalize_pids(pids)
      Array(pids).map { |pid| pid.to_i }.select { |pid| pid.positive? }.uniq
    end
    private_class_method :normalize_pids

    def resolve_member_instances(model, member_pids)
      Array(member_pids).filter_map do |pid|
        entity = model.find_entity_by_persistent_id(pid.to_i)
        next unless entity.is_a?(Sketchup::ComponentInstance)
        next unless cabinet_instance?(entity)

        entity
      end
    end
    private_class_method :resolve_member_instances

    def merge_instances(existing_instances, new_instances)
      combined = existing_instances + new_instances
      combined.uniq(&:object_id).sort_by do |instance|
        [length_to_mm(instance.bounds.min.x) || 0.0, instance.persistent_id.to_i]
      end
    end
    private_class_method :merge_instances

    def apply_row_membership!(model, row, instances, rows_state)
      row['member_pids'] = instances.map { |instance| instance.persistent_id.to_i }
      now_iso = Time.now.utc.iso8601
      row['updated_at'] = now_iso

      instances.each_with_index do |instance, index|
        ensure_instance_membership(instance, row['row_id'], index + 1)
      end

      cleanup_orphaned_instance_memberships(model, rows_state)
    end
    private_class_method :apply_row_membership!

    def validate_instances_for_row!(instances, current_row_id:)
      invalid = instances.reject do |instance|
        membership = for_instance(instance)
        membership.nil? || membership[:row_id] == current_row_id
      end
      return if invalid.empty?

      raise RowError.new(:in_other_row, 'One or more cabinets already belong to another row.')
    end
    private_class_method :validate_instances_for_row!

    def highlight_states
      @highlight_states ||= {}.compare_by_identity
    end
    private_class_method :highlight_states

    def highlight_state(model)
      highlight_states[model] ||= {}
    end
    private_class_method :highlight_state

    def ensure_overlay(model)
      return NullOverlay.new unless overlay_supported?(model)

      state = highlight_state(model)
      overlay = state[:overlay]
      return overlay if overlay&.valid_for_model?(model)

      overlay = RowHighlightOverlay.new(model)
      model.overlays.add(overlay)
      state[:overlay] = overlay
      overlay
    rescue StandardError => error
      warn("AI Cabinets: Unable to enable row highlight overlay: #{error.message}")
      state[:overlay] = NullOverlay.new
    end
    private_class_method :ensure_overlay

    def clear_overlay(model)
      state = highlight_state(model)
      overlay = state[:overlay]
      overlay&.clear
    end
    private_class_method :clear_overlay

    def overlay_supported?(model)
      return false unless defined?(Sketchup::Overlays)
      manager = model.respond_to?(:overlays) ? model.overlays : nil
      manager.respond_to?(:add)
    end
    private_class_method :overlay_supported?

    def update_highlight_if_active(model, row)
      return unless highlight_state(model)[:row_id] == row['row_id']

      overlay = ensure_overlay(model)
      instances = resolve_member_instances(model, row['member_pids'])
      overlay.update(instances)
    end
    private_class_method :update_highlight_if_active

    def trigger_regeneration(model, row)
      return unless defined?(AICabinets::Rows::Regeneration)
      Regeneration.handle_row_change(model: model, row: row)
    rescue StandardError => error
      warn("AI Cabinets: Row regeneration failed: #{error.message}")
    end
    private_class_method :trigger_regeneration

    def validate_selection(model)
      selection = model.selection
      unless selection&.count&.positive?
        return Result.new(
          ok: false,
          code: :no_selection,
          message: 'Select at least two AI Cabinets base cabinets to create a row.'
        )
      end

      instances = selection.grep(Sketchup::ComponentInstance)
      if instances.length != selection.length
        return Result.new(
          ok: false,
          code: :invalid_entities,
          message: 'Selection must contain only AI Cabinets cabinet instances.'
        )
      end

      if instances.length < 2
        return Result.new(
          ok: false,
          code: :insufficient_cabinets,
          message: 'Select at least two AI Cabinets base cabinets to create a row.'
        )
      end

      instances.each do |instance|
        if instance.respond_to?(:locked?) && instance.locked?
          return Result.new(
            ok: false,
            code: :locked_cabinet,
            message: 'Unlock cabinets before adding them to a row.'
          )
        end

        unless cabinet_instance?(instance)
          return Result.new(
            ok: false,
            code: :not_cabinet,
            message: 'Selection must contain only AI Cabinets base cabinets.'
          )
        end

        pid = instance.persistent_id.to_i
        unless pid.positive?
          return Result.new(
            ok: false,
            code: :missing_persistent_id,
            message: 'One or more cabinets are missing a persistent_id; save and retry.'
          )
        end
      end

      unless roughly_collinear?(instances)
        return Result.new(
          ok: false,
          code: :not_collinear,
          message: 'Selected cabinets must be roughly collinear along world X to form a row.'
        )
      end

      instances.sort_by { |instance| length_to_mm(instance.bounds.min.x) || 0.0 }
    end
    private_class_method :validate_selection

    def cabinet_instance?(instance)
      return false unless instance.is_a?(Sketchup::ComponentInstance)
      return false unless defined?(AICabinets::Ops::InsertBaseCabinet)

      dictionary_name = AICabinets::Ops::InsertBaseCabinet::DICTIONARY_NAME
      dictionary = instance.definition.attribute_dictionary(dictionary_name)
      return false unless dictionary

      type_key = AICabinets::Ops::InsertBaseCabinet::TYPE_KEY
      type_value = dictionary[type_key]
      legacy_types = AICabinets::Ops::InsertBaseCabinet::LEGACY_TYPE_VALUES
      return false if type_value && !legacy_types.include?(type_value)

      params_key = AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY
      params_json = dictionary[params_key]
      params_json.is_a?(String) && !params_json.empty?
    end
    private_class_method :cabinet_instance?

    def roughly_collinear?(instances)
      return true if instances.length <= 1

      y_values = []
      z_values = []

      instances.each do |instance|
        origin = instance.transformation.origin
        y_values << length_to_mm(origin.y)
        z_values << length_to_mm(origin.z)
      end

      y_values.compact!
      z_values.compact!

      return false if y_values.length != instances.length
      return false if z_values.length != instances.length

      y_range = y_values.max - y_values.min
      z_range = z_values.max - z_values.min

      y_range <= COLLINEAR_TOLERANCE_MM && z_range <= COLLINEAR_TOLERANCE_MM
    end
    private_class_method :roughly_collinear?

    def load_state(model)
      dictionary = model.attribute_dictionary(MODEL_DICTIONARY)
      state = default_state
      changed = false

      if dictionary
        raw = dictionary[MODEL_JSON_KEY]
        if raw.is_a?(String) && !raw.empty?
          begin
            parsed = JSON.parse(raw)
            if parsed.is_a?(Hash)
              state = parsed
            else
              changed = true
            end
          rescue JSON::ParserError
            changed = true
          end
        else
          changed = true if raw
        end
      end

      changed |= migrate!(state)
      state['rows'] = {} unless state['rows'].is_a?(Hash)

      [state, changed]
    end
    private_class_method :load_state

    def write_state(model, state)
      dictionary = model.attribute_dictionary(MODEL_DICTIONARY, true)
      dictionary[MODEL_JSON_KEY] = JSON.generate(state)
    end
    private_class_method :write_state

    def repair_state!(model, state)
      rows = state['rows']
      return false unless rows.is_a?(Hash)

      changed = false
      now_iso = Time.now.utc.iso8601

      rows.keys.each do |row_id|
        row = rows[row_id]
        member_pids = Array(row['member_pids'])
        next unless member_pids

        resolved_instances = []
        sanitized_pids = []
        row_changed = false

        member_pids.each do |pid|
          pid_int = pid.to_i
          next unless pid_int.positive?

          entity = model.find_entity_by_persistent_id(pid_int)
          next unless entity.is_a?(Sketchup::ComponentInstance)
          next unless cabinet_instance?(entity)

          resolved_instances << entity
          sanitized_pids << pid_int
        end

        if resolved_instances.empty?
          rows.delete(row_id)
          changed = true
          next
        end

        if sanitized_pids != member_pids
          row['member_pids'] = sanitized_pids
          row_changed = true
        end

        resolved_instances.each_with_index do |instance, index|
          row_changed |= ensure_instance_membership(instance, row_id, index + 1)
        end

        if row_changed
          row['updated_at'] = now_iso
          changed = true
        end
      end

      changed |= cleanup_orphaned_instance_memberships(model, rows)
      changed
    end
    private_class_method :repair_state!

    def ensure_instance_membership(instance, row_id, row_pos)
      dictionary = instance.attribute_dictionary(INSTANCE_DICTIONARY, true)
      changed = false

      if dictionary[ROW_ID_KEY] != row_id
        dictionary[ROW_ID_KEY] = row_id
        changed = true
      end

      if dictionary[ROW_POS_KEY].to_i != row_pos.to_i
        dictionary[ROW_POS_KEY] = row_pos.to_i
        changed = true
      end

      changed
    end
    private_class_method :ensure_instance_membership

    def cleanup_orphaned_instance_memberships(model, rows)
      expected = {}
      rows.each do |row_id, row|
        Array(row['member_pids']).each do |pid|
          expected[pid.to_i] = row_id
        end
      end

      changed = false
      instances_with_row_attributes(model) do |instance, dictionary|
        pid = instance.persistent_id.to_i
        row_id = dictionary[ROW_ID_KEY]
        next if pid.positive? && expected[pid] == row_id

        instance.delete_attribute(INSTANCE_DICTIONARY, ROW_ID_KEY)
        instance.delete_attribute(INSTANCE_DICTIONARY, ROW_POS_KEY)
        changed = true
      end

      changed
    end
    private_class_method :cleanup_orphaned_instance_memberships

    def instances_with_row_attributes(model)
      return unless model.respond_to?(:entities)

      model.entities.grep(Sketchup::ComponentInstance).each do |instance|
        dictionary = instance.attribute_dictionary(INSTANCE_DICTIONARY)
        next unless dictionary

        yield(instance, dictionary)
      end
    end
    private_class_method :instances_with_row_attributes

    def sanitize_rows!(state)
      rows = state['rows']
      return false unless rows.is_a?(Hash)

      changed = false
      now_iso = Time.now.utc.iso8601
      rows.each do |row_id, row|
        next unless row.is_a?(Hash)

        if sanitize_row!(row_id, row)
          row['updated_at'] = now_iso
          changed = true
        end
      end

      changed
    end
    private_class_method :sanitize_rows!

    def sanitize_row!(row_id, row)
      changed = false

      unless row['row_id'].is_a?(String) && !row['row_id'].empty?
        row['row_id'] = row_id
        changed = true
      end

      member_pids = Array(row['member_pids']).map { |pid| pid.to_i }
                                     .select { |pid| pid.positive? }
                                     .uniq
      if member_pids != row['member_pids']
        row['member_pids'] = member_pids
        changed = true
      end

      reveal = length_to_mm(row['row_reveal_mm'])
      if reveal
        if row['row_reveal_mm'] != reveal
          row['row_reveal_mm'] = reveal
          changed = true
        end
      else
        row['row_reveal_mm'] = DEFAULT_ROW_REVEAL_MM
        changed = true
      end

      lock_flag = row['lock_total_length'] ? true : false
      if row['lock_total_length'] != lock_flag
        row['lock_total_length'] = lock_flag
        changed = true
      end

      if row.key?('total_length_mm')
        total_length = length_to_mm(row['total_length_mm'])
        if total_length
          if row['total_length_mm'] != total_length
            row['total_length_mm'] = total_length
            changed = true
          end
        elsif !row['total_length_mm'].nil?
          row['total_length_mm'] = nil
          changed = true
        end
      end

      row['created_at'] = sanitize_iso8601(row['created_at'])
      row['updated_at'] = sanitize_iso8601(row['updated_at'])

      changed
    end
    private_class_method :sanitize_row!

    def sanitize_iso8601(value)
      return unless value.is_a?(String) && !value.empty?

      Time.iso8601(value)
      value
    rescue ArgumentError
      nil
    end
    private_class_method :sanitize_iso8601

    def symbolize_row(row)
      {
        row_id: row['row_id'],
        member_pids: Array(row['member_pids']).map(&:to_i),
        row_reveal_mm: row['row_reveal_mm'],
        lock_total_length: !!row['lock_total_length'],
        total_length_mm: row['total_length_mm'],
        created_at: row['created_at'],
        updated_at: row['updated_at']
      }
    end
    private_class_method :symbolize_row

    def length_to_mm(value)
      return unless value

      converted = if defined?(Sketchup::Length) && value.is_a?(Sketchup::Length)
                    value.to_mm.to_f
                  elsif value.is_a?(Numeric)
                    value.to_f
                  end

      if !converted && value.respond_to?(:to_mm)
        converted = value.to_mm.to_f
      end

      return unless converted&.finite?

      converted
    end
    private_class_method :length_to_mm

    def default_state
      {
        'schema_version' => SCHEMA_VERSION,
        'rows' => {}
      }
    end
    private_class_method :default_state

    def format_length(value_mm)
      return '' if value_mm.nil?

      if defined?(Sketchup) && value_mm.respond_to?(:to_f)
        length = value_mm.to_f.mm
        return Sketchup.format_length(length)
      end

      format('%.2f mm', value_mm.to_f)
    rescue StandardError
      format('%.2f mm', value_mm.to_f)
    end
    private_class_method :format_length

    class NullOverlay
      def update(_instances); end

      def clear; end

      def valid_for_model?(_model)
        true
      end
    end
    private_constant :NullOverlay

    class RowHighlightOverlay < Sketchup::Overlay
      COLOR = Sketchup::Color.new(0xff, 0x66, 0x00).freeze
      LINE_WIDTH = 3

      def initialize(model)
        super(ROW_HIGHLIGHT_OVERLAY_ID)
        @model = model
        @polylines = []
      end

      def update(instances)
        @polylines = build_polylines(instances)
        invalidate
      end

      def clear
        @polylines = []
        invalidate
      end

      def valid_for_model?(model)
        @model == model
      end

      def draw(view)
        return if @polylines.empty?

        view.drawing_color = COLOR
        view.line_width = LINE_WIDTH
        view.line_stipple = ''
        @polylines.each do |polyline|
          view.draw(GL_LINE_LOOP, polyline)
        end
      end

      private

      def build_polylines(instances)
        instances.filter_map do |instance|
          next unless instance&.valid?

          bounds = instance.bounds
          [
            Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.min.z),
            Geom::Point3d.new(bounds.max.x, bounds.min.y, bounds.min.z),
            Geom::Point3d.new(bounds.max.x, bounds.min.y, bounds.max.z),
            Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.max.z)
          ]
        end
      end
    end
    private_constant :RowHighlightOverlay
  end
end
