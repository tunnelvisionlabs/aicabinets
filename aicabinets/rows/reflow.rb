# frozen_string_literal: true

require 'json'

Sketchup.require('aicabinets/ops/edit_base_cabinet')

module AICabinets
  module Rows
    module Reflow
      module_function

      OPERATION_NAME = 'AI Cabinets — Reflow Row'.freeze
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
        state, _changed = AICabinets::Rows.__send__(:prepare_state, model)
        row = state['rows'][membership[:row_id]]
        raise RowError.new(:unknown_row, 'Row not found.') unless row

        members = resolve_row_members(model, row)
        raise RowError.new(:row_empty, 'Row has no members to reflow.') if members.empty?

        unless members.include?(instance)
          raise RowError.new(:not_in_row, 'Specified cabinet is no longer part of the row.')
        end

        original_transforms = members.each_with_object({}) do |member, memo|
          memo[member] = member.transformation
        end

        operation_open = false
        model.start_operation(OPERATION_NAME, true)
        operation_open = true

        delta_mm = apply_member_width!(instance, new_width, scope_value)
        offsets_mm, total_delta_mm = compute_offsets(members, instance, delta_mm, scope_key)

        apply_transforms!(members, offsets_mm, original_transforms)

        if row['lock_total_length'] && total_delta_mm.abs > Float::EPSILON
          adjust_filler_width!(members, total_delta_mm)
        end

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
        mm = if value.respond_to?(:to_mm)
               value.to_mm.to_f
             else
               Float(value)
             end

        raise RowError.new(:invalid_width, 'Width must be positive.') unless mm.positive?

        mm
      rescue ArgumentError, TypeError
        raise RowError.new(:invalid_width, 'Width must be expressed in millimeters.')
      end
      private_class_method :coerce_positive_mm

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
        old_width_mm = params[:width_mm].to_f

        return 0.0 if (old_width_mm - new_width_mm).abs <= Float::EPSILON

        params[:width_mm] = new_width_mm
        sanitized = edit_ops.__send__(:validate_params!, params)

        definition = edit_ops.__send__(:ensure_definition_for_scope, instance, scope_string)
        edit_ops.__send__(:rebuild_definition!, definition, sanitized)

        def_key, params_json = edit_ops.__send__(:build_definition_key, sanitized)
        edit_ops.__send__(:assign_definition_attributes, definition, def_key, params_json)

        new_width_mm - old_width_mm
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

      def compute_offsets(members, target_instance, delta_mm, scope_key)
        target_definition = target_instance.definition

        per_member_delta = members.each_with_object({}) do |member, memo|
          applies =
            if scope_key == :all_instances
              member.definition == target_definition
            else
              member == target_instance
            end

          memo[member] = applies ? delta_mm : 0.0
        end

        cumulative = 0.0
        offsets = members.each_with_object({}) do |member, memo|
          memo[member] = cumulative
          cumulative += per_member_delta[member]
        end

        [offsets, cumulative]
      end
      private_class_method :compute_offsets

      def apply_transforms!(members, offsets_mm, original_transforms)
        members.each do |member|
          offset_mm = offsets_mm[member] || 0.0
          next if offset_mm.abs <= Float::EPSILON

          base = original_transforms[member] || member.transformation
          translation = Geom::Transformation.translation(Geom::Vector3d.new(offset_mm.mm, 0, 0))
          member.transformation = translation * base
        end
      end
      private_class_method :apply_transforms!

      def adjust_filler_width!(members, total_delta_mm)
        filler = members.last
        return unless filler

        filler_params = definition_params(filler.definition)
        filler_width = filler_params[:width_mm].to_f
        new_width = filler_width - total_delta_mm

        if new_width < MIN_MEMBER_WIDTH_MM
          raise RowError.new(:lock_length_failed, 'Row lock prevents applying this width change.')
        end

        apply_member_width!(filler, new_width, VALID_SCOPES[:instance_only])
      end
      private_class_method :adjust_filler_width!
    end
  end
end

