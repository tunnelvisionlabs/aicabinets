# frozen_string_literal: true

require 'json'
require 'time'

Sketchup.require('aicabinets/ops/edit_base_cabinet')

module AICabinets
  module Rows
    module Reflow
      module_function

      OPERATION_NAME = 'AI Cabinets — Reflow Row'.freeze
      EPSILON_MM = 1e-6
      MM_PER_INCH = 25.4
      VALID_SCOPES = {
        instance_only: 'instance',
        instance: 'instance',
        all_instances: 'all',
        all: 'all'
      }.freeze
      MIN_MEMBER_WIDTH_MM = 25.0
      def apply_width_change!(instance:, new_width_mm:, scope: :instance_only)
        validate_edit_dependencies!
        instance = validate_instance(instance)
        new_width = coerce_positive_mm(new_width_mm)
        scope_key, scope_value = normalize_scope(scope)

        membership = AICabinets::Rows.for_instance(instance)
        raise RowError.new(:not_in_row, 'The cabinet is not part of a row.') unless membership

        model = instance.model
        state, state_changed = AICabinets::Rows.__send__(:prepare_state, model)
        row = state['rows'][membership[:row_id]]
        raise RowError.new(:unknown_row, 'Row not found.') unless row

        members = resolve_row_members(model, row)
        raise RowError.new(:row_empty, 'Row has no members to reflow.') if members.empty?

        unless members.include?(instance)
          raise RowError.new(:not_in_row, 'Specified cabinet is no longer part of the row.')
        end

        original_width_mm = measure_instance_width_mm(instance)
        delta_mm = new_width - original_width_mm
        return Result.new(ok: true, code: :no_change) if delta_mm.abs <= EPSILON_MM

        operation_open = false
        model.start_operation(OPERATION_NAME, true)
        operation_open = true

        apply_member_width!(instance, new_width, scope_value)
        total_delta_mm = apply_reflow_transforms!(
          members,
          instance,
          delta_mm,
          scope_key
        )

        if row['lock_total_length'] && total_delta_mm.abs > EPSILON_MM
          adjust_filler_width!(members, total_delta_mm)
        end

        state_changed ||= update_row_metadata!(row, members)
        AICabinets::Rows.__send__(:write_state, model, state) if state_changed

        AICabinets::Rows.__send__(:trigger_regeneration, model, row)

        model.commit_operation
        operation_open = false

        Result.new(ok: true, code: :ok)
      rescue RowError
        raise
      rescue StandardError => error
        warn("AI Cabinets: Row reflow failed: #{error.message}")
        raise RowError.new(:reflow_failed, 'Unable to reflow the row after editing width.')
      ensure
        model.abort_operation if defined?(model) && model && operation_open
      end

      def debug_reflow!(row_id:, i:, new_width_mm:, scope: :instance_only)
        model = Sketchup.active_model
        raise RowError.new(:no_model, 'No active SketchUp model.') unless model

        state, = AICabinets::Rows.__send__(:prepare_state, model)
        row = state['rows'][row_id]
        raise RowError.new(:unknown_row, 'Row not found.') unless row

        members = resolve_row_members(model, row)
        raise RowError.new(:row_empty, 'Row has no members to reflow.') if members.empty?

        index = i.to_i - 1
        raise RowError.new(:invalid_member_index, 'Member index must be at least 1.') if index.negative?

        target = members[index]
        raise RowError.new(:invalid_member_index, 'Member index exceeds row length.') unless target

        apply_width_change!(instance: target, new_width_mm: new_width_mm, scope: scope)
      end

      def validate_edit_dependencies!
        return if defined?(AICabinets::Ops::EditBaseCabinet)

        raise RowError.new(:missing_edit_ops, 'EditBaseCabinet operations are unavailable.')
      end
      private_class_method :validate_edit_dependencies!

      def validate_instance(instance)
        unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
          raise RowError.new(:not_cabinet, 'Width changes can only be applied to cabinet instances.')
        end

        instance
      end
      private_class_method :validate_instance

      def coerce_positive_mm(value)
        mm =
          case value
          when nil
            raise ArgumentError
          when String
            Float(value)
          else
            if length_object?(value)
              value.to_mm.to_f
            elsif value.respond_to?(:to_f)
              value.to_f
            else
              Float(value)
            end
          end

        raise RowError.new(:invalid_width, 'Width must be positive.') unless mm.positive?

        mm
      rescue ArgumentError, TypeError
        raise RowError.new(:invalid_width, 'Width must be expressed in millimeters.')
      end
      private_class_method :coerce_positive_mm

      def length_object?(value)
        length_class =
          if defined?(Sketchup::Length)
            Sketchup::Length
          elsif defined?(Length)
            Length
          end

        if length_class
          value.is_a?(length_class)
        else
          value.respond_to?(:to_mm) && !value.is_a?(Numeric)
        end
      end
      private_class_method :length_object?

      def normalize_scope(scope)
        key =
          case scope
          when String
            scope.strip.downcase.to_sym
          when Symbol
            scope
          else
            raise RowError.new(:invalid_scope, 'Scope must be :instance_only or :all_instances.')
          end

        value = VALID_SCOPES[key]
        unless value
          raise RowError.new(:invalid_scope, 'Scope must be :instance_only or :all_instances.')
        end

        [key, value]
      end
      private_class_method :normalize_scope

      def resolve_row_members(model, row)
        instances = AICabinets::Rows.__send__(:resolve_member_instances, model, row['member_pids'])
        pid_lookup = instances.each_with_object({}) do |instance, memo|
          memo[instance.persistent_id.to_i] = instance
        end

        Array(row['member_pids']).filter_map do |pid|
          pid_lookup[pid.to_i]
        end
      end
      private_class_method :resolve_row_members

      def apply_member_width!(instance, new_width_mm, scope_string)
        edit_ops = AICabinets::Ops::EditBaseCabinet
        original_definition = instance.definition
        params = definition_params(original_definition)
        params[:width_mm] = new_width_mm
        sanitized = edit_ops.__send__(:validate_params!, params)

        definition = edit_ops.__send__(:ensure_definition_for_scope, instance, scope_string)
        edit_ops.__send__(:rebuild_definition!, definition, sanitized)

        def_key, params_json = edit_ops.__send__(:build_definition_key, sanitized)
        edit_ops.__send__(:assign_definition_attributes, definition, def_key, params_json)
      end
      private_class_method :apply_member_width!

      def definition_params(definition)
        dictionary = definition.attribute_dictionary(AICabinets::Ops::InsertBaseCabinet::DICTIONARY_NAME)
        raise RowError.new(:missing_params, 'Cabinet parameters are unavailable.') unless dictionary

        json = dictionary[AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY]
        raise RowError.new(:missing_params, 'Cabinet parameters are unavailable.') unless json.is_a?(String)

        parsed = JSON.parse(json)
        parsed.each_with_object({}) do |(key, value), memo|
          memo[key.to_sym] = value
        end
      rescue JSON::ParserError
        raise RowError.new(:invalid_params, 'Cabinet parameters are invalid.')
      end
      private_class_method :definition_params

      def apply_reflow_transforms!(members, target_instance, delta_mm, scope_key)
        target_definition = target_instance.definition
        cumulative_shift_mm = 0.0
        occurrences = 0

        members.each do |member|
          translate_x_mm!(member, cumulative_shift_mm)

          next unless member_triggers_delta?(member, target_instance, target_definition, scope_key)

          occurrences += 1
          cumulative_shift_mm += delta_mm
        end

        occurrences * delta_mm
      end
      private_class_method :apply_reflow_transforms!

      def member_triggers_delta?(member, target_instance, target_definition, scope_key)
        case scope_key
        when :instance_only, :instance
          member == target_instance
        when :all_instances, :all
          member.definition == target_definition
        else
          false
        end
      end
      private_class_method :member_triggers_delta?

      def translate_x_mm!(member, delta_mm)
        shift_mm =
          if length_object?(delta_mm)
            delta_mm.to_mm.to_f
          else
            delta_mm.to_f
          end

        return if shift_mm.abs <= EPSILON_MM

        delta_length = shift_mm.mm
        member.transform!(
          Geom::Transformation.translation([delta_length.to_f, 0.0, 0.0])
        )
      end
      private_class_method :translate_x_mm!

      def adjust_filler_width!(members, total_delta_mm)
        filler = members.last
        return unless filler

        filler_width_mm = measure_instance_width_mm(filler)
        new_width_mm = filler_width_mm - total_delta_mm

        if new_width_mm < MIN_MEMBER_WIDTH_MM - EPSILON_MM
          raise RowError.new(:lock_length_failed, 'Row lock prevents applying this width change.')
        end

        apply_member_width!(filler, new_width_mm, VALID_SCOPES[:instance_only])
      end
      private_class_method :adjust_filler_width!

      def measure_instance_width_mm(instance)
        bounds = instance.bounds
        width_mm = length_to_mm(bounds.max.x) - length_to_mm(bounds.min.x)
        return width_mm if width_mm.positive?

        raise RowError.new(:invalid_width, 'Unable to determine cabinet width.')
      end
      private_class_method :measure_instance_width_mm

      def update_row_metadata!(row, members)
        changed = false
        now_iso = Time.now.utc.iso8601

        if row['updated_at'] != now_iso
          row['updated_at'] = now_iso
          changed = true
        end

        total_length = compute_total_length_mm(members)
        if total_length && row['total_length_mm'] != total_length
          row['total_length_mm'] = total_length
          changed = true
        end

        changed
      end
      private_class_method :update_row_metadata!

      def compute_total_length_mm(members)
        bounds = members.map(&:bounds)
        return nil if bounds.empty?

        min_x = bounds.map { |bbox| length_to_mm(bbox.min.x) }.min
        max_x = bounds.map { |bbox| length_to_mm(bbox.max.x) }.max
        max_x - min_x
      end
      private_class_method :compute_total_length_mm

      def length_to_mm(value)
        if value.respond_to?(:to_mm)
          value.to_mm.to_f
        else
          value.to_f * MM_PER_INCH
        end
      end
      private_class_method :length_to_mm
    end
  end
end

