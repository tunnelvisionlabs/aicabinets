# frozen_string_literal: true

module AICabinets
  module Rows
    module Selection
      extend self

      def auto_select_row?
        !!@auto_select_row
      end

      def set_auto_select_row(on:, model: Sketchup.active_model)
        enabled = !!on
        @auto_select_row = enabled

        model = resolve_model(model)
        if enabled
          attach_observer(model)
        else
          detach_observer(model)
        end

        { ok: true, enabled: enabled }
      end

      def reset!
        observer_attached_models.keys.each do |model|
          detach_observer(model)
        end
        @auto_select_row = false
        @updating_selection = false
        @expansion_states = nil
      end

      def handle_selection_change(selection)
        return unless auto_select_row?
        return if @updating_selection
        return unless selection.is_a?(Sketchup::Selection)
        model = resolve_model(selection.model) || resolve_model(nil)
        return unless model.is_a?(Sketchup::Model)

        instances = selection.grep(Sketchup::ComponentInstance).select(&:valid?)
        selected_row_ids = instances.filter_map { |entity| row_id_for(entity) }.uniq

        if selection.empty? || instances.empty?
          clear_expansion_state(model)
          return
        end

        if selected_row_ids.length > 1
          prune_auto_added_members(selection, model)
          return
        end

        return unless selection.count == 1

        instance = instances.first
        membership = AICabinets::Rows.for_instance(instance)
        return unless membership

        row_id = membership[:row_id]
        return if row_id.to_s.empty?

        detail = fetch_row_detail(model, row_id)
        return unless detail

        pids = Array(detail[:row][:member_pids] || detail[:row]['member_pids']).map { |pid| pid.to_i }
        return if pids.empty?

        target_entities = pids.filter_map do |pid|
          entity = model.find_entity_by_persistent_id(pid)
          entity if entity.is_a?(Sketchup::ComponentInstance)
        end
        return if target_entities.empty?

        current_ids = instances.map { |entity| entity.persistent_id.to_i }.sort
        target_ids = target_entities.map { |entity| entity.persistent_id.to_i }.sort
        return if current_ids == target_ids

        begin
          @updating_selection = true
          selection.clear
          target_entities.each { |entity| selection.add(entity) }
          store_expansion_state(model, row_id:, base_ids: current_ids, target_ids: target_ids)
        ensure
          @updating_selection = false
        end
      end

      def observer
        @observer ||= AutoSelectObserver.new
      end

      private

      def resolve_model(model)
        return model if model.is_a?(Sketchup::Model)
        defined?(Sketchup) ? Sketchup.active_model : nil
      end

      def attach_observer(model)
        selection = model.respond_to?(:selection) ? model.selection : nil
        return unless selection

        return if observer_attached_models.key?(model)

        selection.add_observer(observer)
        observer_attached_models[model] = true
      rescue StandardError
        nil
      end

      def detach_observer(model)
        return unless model.is_a?(Sketchup::Model)

        selection = model.selection
        return unless selection

        selection.remove_observer(observer)
        observer_attached_models.delete(model)
      rescue StandardError
        observer_attached_models.delete(model)
        nil
      end

      def observer_attached_models
        @observer_attached_models ||= {}.compare_by_identity
      end

      def expansion_states
        @expansion_states ||= {}.compare_by_identity
      end

      def store_expansion_state(model, row_id:, base_ids:, target_ids:)
        added_ids = target_ids - base_ids
        expansion_states[model] = {
          row_id: row_id,
          added_ids: added_ids
        }
      end

      def clear_expansion_state(model)
        expansion_states.delete(model)
      end

      def prune_auto_added_members(selection, model)
        state = expansion_states[model]
        return unless state

        added_ids = Array(state[:added_ids])
        if added_ids.empty?
          clear_expansion_state(model)
          return
        end

        entities_to_remove = added_ids.filter_map do |pid|
          entity = model.find_entity_by_persistent_id(pid.to_i)
          entity if entity && selection.include?(entity)
        end
        if entities_to_remove.empty?
          clear_expansion_state(model)
          return
        end

        begin
          @updating_selection = true
          entities_to_remove.each { |entity| selection.remove(entity) }
        ensure
          @updating_selection = false
          clear_expansion_state(model)
        end
      end

      def row_id_for(entity)
        membership = AICabinets::Rows.for_instance(entity)
        return unless membership

        membership[:row_id]
      rescue AICabinets::Rows::RowError
        nil
      end

      def fetch_row_detail(model, row_id)
        AICabinets::Rows.get_row(model: model, row_id: row_id)
      rescue AICabinets::Rows::RowError
        nil
      end

      class AutoSelectObserver < Sketchup::SelectionObserver
        def onSelectionAdded(selection, _entity)
          Selection.handle_selection_change(selection)
        end

        def onSelectionRemoved(selection, _entity)
          Selection.handle_selection_change(selection)
        end

        def onSelectionBulkChange(selection)
          Selection.handle_selection_change(selection)
        end

        def onSelectionCleared(selection)
          Selection.handle_selection_change(selection)
        end
      end
      private_constant :AutoSelectObserver
    end
  end
end
