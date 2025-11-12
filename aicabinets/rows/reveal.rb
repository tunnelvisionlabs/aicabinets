# frozen_string_literal: true

require 'json'

Sketchup.require('aicabinets/generator/carcass')
Sketchup.require('aicabinets/generator/fronts')
Sketchup.require('aicabinets/ops/insert_base_cabinet')
Sketchup.require('aicabinets/ops/materials')
Sketchup.require('aicabinets/ops/tags')

module AICabinets
  module Rows
    module Reveal
      module_function

      OPERATION_NAME = 'AI Cabinets — Apply Row Reveal'.freeze
      REVEAL_DICTIONARY = 'AICabinets.Reveal'.freeze
      USE_ROW_REVEAL_KEY = 'use_row_reveal'.freeze
      def apply!(row_id:, model:, operation: true)
        model = Rows.__send__(:validate_model, model)
        row_id = Rows.__send__(:validate_row_id, row_id)

        state, = Rows.__send__(:prepare_state, model)
        row = state['rows'][row_id]
        raise RowError.new(:unknown_row, 'Row not found.') unless row

        members = Rows.__send__(:resolve_member_instances, model, row['member_pids'])
        return ok_result if members.empty?

        ordered = order_members(members)
        return ok_result if ordered.empty?

        reveal_mm = extract_row_reveal(row)
        plan = build_plan(ordered, reveal_mm)
        return ok_result if plan.empty?

        operation_open = false
        if operation
          model.start_operation(OPERATION_NAME, true)
          operation_open = true
        end

        front_material = AICabinets::Ops::Materials.default_door(model)
        apply_plan!(plan, front_material)

        if operation_open
          model.commit_operation
          operation_open = false
        end
        ok_result
      rescue RowError
        raise
      rescue StandardError => error
        warn("AI Cabinets: Row reveal application failed: #{error.message}")
        raise RowError.new(:reveal_failed, 'Unable to apply row reveal across the row.')
      ensure
        if operation && operation_open && model.respond_to?(:abort_operation)
          model.abort_operation
        end
      end

      def order_members(instances)
        instances.filter_map do |instance|
          next unless instance&.valid?

          membership = Rows.for_instance(instance)
          params_mm = definition_params(instance.definition)
          next unless params_mm

          {
            instance: instance,
            params_mm: params_mm,
            row_pos: membership ? membership[:row_pos].to_i : nil,
            origin_x_mm: length_to_mm(instance.transformation.origin.x),
            use_row_reveal: use_row_reveal?(instance),
            legacy_left_mm: legacy_edge_reveal_mm(params_mm, :left),
            legacy_right_mm: legacy_edge_reveal_mm(params_mm, :right)
          }
        end.sort_by do |entry|
          [
            entry[:row_pos] || Float::INFINITY,
            entry[:origin_x_mm] || 0.0,
            entry[:instance].persistent_id.to_i
          ]
        end
      end
      private_class_method :order_members

      def build_plan(entries, reveal_mm)
        entries.each_with_index.map do |entry, index|
          left_neighbor = entries[index - 1] if index.positive?
          right_neighbor = entries[index + 1]

          left_kind = boundary_kind(entry, left_neighbor)
          right_kind = boundary_kind(entry, right_neighbor, side: :right)

          trim_left = trim_amount(entry, left_kind, reveal_mm, entry[:legacy_left_mm])
          trim_right = trim_amount(entry, right_kind, reveal_mm, entry[:legacy_right_mm])

          entry.merge(trim_left_mm: trim_left, trim_right_mm: trim_right)
        end
      end
      private_class_method :build_plan

      def apply_plan!(plan, front_material)
        plan.each do |entry|
          instance = entry[:instance]
          next unless instance&.valid?

          params_mm = deep_copy(entry[:params_mm])
          params_mm[:door_edge_reveal_left_mm] = entry[:trim_left_mm]
          params_mm[:door_edge_reveal_right_mm] = entry[:trim_right_mm]

          ensure_unique_definition(instance)

          parameter_set = AICabinets::Generator::Carcass::ParameterSet.new(params_mm)
          entities = instance.definition.entities
          created = AICabinets::Generator::Fronts.build(parent_entities: entities, params: parameter_set)
          apply_category(created, 'AICabinets/Fronts', front_material)
        end
      end
      private_class_method :apply_plan!

      def ensure_unique_definition(instance)
        return unless instance.respond_to?(:make_unique)

        instance.make_unique
      end
      private_class_method :ensure_unique_definition

      def apply_category(container, tag_name, material)
        Array(container).each do |entity|
          next unless entity&.valid?

          AICabinets::Ops::Tags.assign!(entity, tag_name)
          next unless material && entity.respond_to?(:material=)

          entity.material = material
        end
      end
      private_class_method :apply_category

      def boundary_kind(entry, neighbor, _side: :left)
        return :legacy unless entry[:use_row_reveal]
        return :exposed_end unless neighbor&.dig(:use_row_reveal)

        :interior_split
      end
      private_class_method :boundary_kind

      def trim_amount(_entry, kind, reveal_mm, legacy_mm)
        case kind
        when :interior_split
          [reveal_mm.to_f / 2.0, 0.0].max
        when :exposed_end
          [reveal_mm.to_f, 0.0].max
        else
          [legacy_mm.to_f, 0.0].max
        end
      end
      private_class_method :trim_amount

      def extract_row_reveal(row)
        value = row['row_reveal_mm'] || row[:row_reveal_mm]
        return Rows::DEFAULT_ROW_REVEAL_MM unless value

        numeric =
          if value.is_a?(Numeric) || value.respond_to?(:to_f)
            value.to_f
          else
            Float(value)
          end

        numeric.finite? ? numeric : Rows::DEFAULT_ROW_REVEAL_MM
      rescue ArgumentError, TypeError
        Rows::DEFAULT_ROW_REVEAL_MM
      end
      private_class_method :extract_row_reveal

      def definition_params(definition)
        return unless definition&.valid?

        dictionary =
          definition.attribute_dictionary(AICabinets::Ops::InsertBaseCabinet::DICTIONARY_NAME)
        return unless dictionary

        json = dictionary[AICabinets::Ops::InsertBaseCabinet::PARAMS_JSON_KEY]
        return unless json.is_a?(String) && !json.empty?

        JSON.parse(json, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end
      private_class_method :definition_params

      def use_row_reveal?(instance)
        dictionary = instance.attribute_dictionary(REVEAL_DICTIONARY)
        return true unless dictionary

        value = dictionary[USE_ROW_REVEAL_KEY]
        return true if value.nil?

        value == true || value.to_s.downcase == 'true'
      end
      private_class_method :use_row_reveal?

      def legacy_edge_reveal_mm(params_mm, side)
        return 0.0 unless params_mm.is_a?(Hash)

        keys =
          case side
          when :left
            %i[door_edge_reveal_left_mm door_reveal_left_mm]
          when :right
            %i[door_edge_reveal_right_mm door_reveal_right_mm]
          else
            []
          end

        override = fetch_numeric(params_mm, keys)
        base = fetch_numeric(params_mm, %i[door_edge_reveal_mm door_reveal_mm])
        (override || base || AICabinets::Generator::Fronts::REVEAL_EDGE_MM).to_f
      end
      private_class_method :legacy_edge_reveal_mm

      def fetch_numeric(container, keys)
        Array(keys).each do |key|
          value = container[key]
          value = container[key.to_s] if value.nil?
          next if value.nil?

          numeric =
            if value.is_a?(Numeric) || value.respond_to?(:to_f)
              value.to_f
            else
              Float(value)
            end
          return numeric if numeric.finite? && numeric >= 0.0
        rescue ArgumentError, TypeError
          next
        end

        nil
      end
      private_class_method :fetch_numeric

      def deep_copy(object)
        Marshal.load(Marshal.dump(object))
      rescue StandardError
        object.dup
      end
      private_class_method :deep_copy

      def length_to_mm(length)
        if length.respond_to?(:to_mm)
          length.to_mm.to_f
        elsif length.respond_to?(:to_f)
          length.to_f * 25.4
        else
          0.0
        end
      end
      private_class_method :length_to_mm

      def ok_result
        Rows::Result.new(ok: true, code: :ok)
      end
      private_class_method :ok_result
    end
  end
end
