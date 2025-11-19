# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Metadata
    module Naming
      module_function

      DICTIONARY_NAME = 'AICabinets.Metadata'.freeze
      ROLE_KEY = 'role'.freeze
      INDEX_KEY = 'index'.freeze
      FACE_FRAME_ROLE = 'face_frame'.freeze
      FACE_FRAME_LABEL = 'Face Frame'.freeze

      ROLE_LABELS = {
        stile_left: 'Stile Left',
        stile_right: 'Stile Right',
        rail_top: 'Rail Top',
        rail_bottom: 'Rail Bottom',
        mid_stile: 'Mid Stile'
      }.freeze

      # Names the face-frame container and records its semantic role.
      #
      # @param entity [Sketchup::Group, Sketchup::ComponentInstance]
      # @return [Sketchup::Entity, nil]
      def name_face_frame!(entity)
        return entity unless container?(entity)

        assign_name(entity, FACE_FRAME_LABEL)
        write_role_attributes(entity, FACE_FRAME_ROLE, nil)
        entity
      end

      # Names an individual face-frame member based on its role and ordering.
      #
      # @param entity [Sketchup::Group, Sketchup::ComponentInstance]
      # @param role [Symbol, String]
      # @param index [Integer, nil] numbering for mid rails
      def name_member!(entity, role:, index: nil)
        return entity unless container?(entity)

        normalized_role = normalize_role(role)
        label = label_for_role(normalized_role, index)
        normalized_index =
          if normalized_role == :mid_rail
            normalize_index(index)
          else
            normalize_index_optional(index)
          end

        assign_name(entity, label)
        write_role_attributes(entity, normalized_role, normalized_index)
        entity
      end

      def assign_name(entity, label)
        entity.name = label if entity.respond_to?(:name=)
      end
      private_class_method :assign_name

      def write_role_attributes(entity, role, index)
        entity.set_attribute(DICTIONARY_NAME, ROLE_KEY, role.to_s)
        if index
          entity.set_attribute(DICTIONARY_NAME, INDEX_KEY, index)
        else
          entity.delete_attribute(DICTIONARY_NAME, INDEX_KEY)
        end
      end
      private_class_method :write_role_attributes

      def label_for_role(role, index)
        case role
        when :mid_rail
          idx = normalize_index(index)
          "Mid Rail #{idx}"
        else
          ROLE_LABELS.fetch(role) { raise ArgumentError, "Unsupported member role: #{role}" }
        end
      end
      private_class_method :label_for_role

      def normalize_role(role)
        case role
        when Symbol
          role
        when String
          trimmed = role.strip
          raise ArgumentError, 'role must be provided' if trimmed.empty?

          trimmed.downcase.to_sym
        else
          raise ArgumentError, 'role must be a Symbol or String'
        end
      end
      private_class_method :normalize_role

      def normalize_index(value)
        integer = value.to_i
        raise ArgumentError, 'index must be positive' unless integer.positive?

        integer
      end
      private_class_method :normalize_index

      def normalize_index_optional(value)
        return nil if value.nil?

        normalize_index(value)
      rescue ArgumentError
        nil
      end
      private_class_method :normalize_index_optional

      def container?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end
      private_class_method :container?
    end
  end
end
