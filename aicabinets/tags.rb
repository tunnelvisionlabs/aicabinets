# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  module Tags
    module_function

    OPERATION_NAME = 'AI Cabinets: Ensure Tags'.freeze
    CABINET_FOLDER_NAME = 'AICabinets'.freeze
    CABINET_TAG_NAME = 'Cabinet'.freeze
    CABINET_TAG_COLLISION_NAME = 'Cabinet (AI Cabinets)'.freeze
    LEGACY_CABINET_TAG_NAME = 'AICabinets/Cabinet'.freeze

    def ensure_structure!(model)
      return unless model.is_a?(Sketchup::Model)

      layers = model.layers
      return unless supports_tag_folders?(layers)

      folder = find_folder(layers, CABINET_FOLDER_NAME)
      preferred_tag = layers[CABINET_TAG_NAME]
      fallback_tag = layers[CABINET_TAG_COLLISION_NAME]
      legacy_tag = layers[LEGACY_CABINET_TAG_NAME]

      folder ||= folder_from_tag(preferred_tag)
      folder ||= folder_from_tag(fallback_tag)

      tag = current_tag_for(folder, preferred_tag, fallback_tag)
      return tag if tag && legacy_tag.nil?

      operation_open = false
      begin
        model.start_operation(OPERATION_NAME, true)
        operation_open = true

        folder ||= layers.add_folder(CABINET_FOLDER_NAME)

        tag =
          if legacy_tag
            migrate_legacy_tag(layers, folder, legacy_tag)
          else
            ensure_cabinet_tag(layers, folder, preferred_tag, fallback_tag)
          end

        model.commit_operation
        operation_open = false
      ensure
        model.abort_operation if operation_open
      end

      tag
    rescue StandardError => error
      warn("AI Cabinets: Failed to ensure cabinet tag structure: #{error.message}")
      tag || legacy_tag || preferred_tag || fallback_tag
    end

    def supports_tag_folders?(layers)
      defined?(Sketchup::LayerFolder) &&
        layers.respond_to?(:add_folder) &&
        layers.respond_to?(:folders) &&
        Sketchup::Layer.instance_methods.include?(:folder=)
    end
    private_class_method :supports_tag_folders?

    def current_tag_for(folder, preferred_tag, fallback_tag)
      return unless folder

      return preferred_tag if tag_in_folder?(preferred_tag, folder)
      return fallback_tag if tag_in_folder?(fallback_tag, folder)

      nil
    end
    private_class_method :current_tag_for

    def tag_in_folder?(tag, folder)
      return false unless tag && folder
      return false unless tag.respond_to?(:folder)

      current_folder = tag.folder
      return false unless current_folder

      current_folder == folder ||
        folder_display_name(current_folder) == folder_display_name(folder)
    end
    private_class_method :tag_in_folder?

    def folder_from_tag(tag)
      return unless tag&.respond_to?(:folder)

      folder = tag.folder
      return unless folder
      return folder if folder_display_name(folder) == CABINET_FOLDER_NAME
    end
    private_class_method :folder_from_tag

    def find_folder(layers, display_name)
      return unless layers.respond_to?(:folders)

      layers.folders.find do |folder|
        folder_display_name(folder) == display_name
      end
    end
    private_class_method :find_folder

    def folder_display_name(folder)
      return '' unless folder

      if folder.respond_to?(:display_name)
        folder.display_name.to_s
      elsif folder.respond_to?(:name)
        folder.name.to_s
      else
        folder.to_s
      end
    end
    private_class_method :folder_display_name

    def migrate_legacy_tag(layers, folder, legacy_tag)
      visibility = legacy_tag.visible? if legacy_tag.respond_to?(:visible?)

      target_name = migration_target_name(layers, legacy_tag, folder)
      rename_tag(legacy_tag, target_name)
      assign_folder(legacy_tag, folder)
      legacy_tag.visible = visibility unless visibility.nil? || legacy_tag.visible? == visibility
      legacy_tag
    end
    private_class_method :migrate_legacy_tag

    def migration_target_name(layers, legacy_tag, folder)
      existing = layers[CABINET_TAG_NAME]
      return CABINET_TAG_NAME if existing.nil? || existing == legacy_tag
      return CABINET_TAG_NAME if tag_in_folder?(existing, folder)

      CABINET_TAG_COLLISION_NAME
    end
    private_class_method :migration_target_name

    def ensure_cabinet_tag(layers, folder, preferred_tag, fallback_tag)
      if preferred_tag && tag_belongs_to_extension?(preferred_tag, folder)
        assign_folder(preferred_tag, folder)
        preferred_tag
      elsif preferred_tag
        ensure_fallback_tag(layers, folder, fallback_tag)
      else
        created = layers[CABINET_TAG_NAME] || layers.add(CABINET_TAG_NAME)
        if tag_belongs_to_extension?(created, folder)
          assign_folder(created, folder)
          created
        else
          ensure_fallback_tag(layers, folder, fallback_tag)
        end
      end
    end
    private_class_method :ensure_cabinet_tag

    def ensure_fallback_tag(layers, folder, fallback_tag)
      fallback = fallback_tag || layers.add(CABINET_TAG_COLLISION_NAME)
      assign_folder(fallback, folder)
      fallback
    end
    private_class_method :ensure_fallback_tag

    def tag_belongs_to_extension?(tag, folder)
      return false unless tag&.respond_to?(:folder)

      current_folder = tag.folder
      return false unless current_folder

      folder_display_name(current_folder) == CABINET_FOLDER_NAME &&
        (folder.nil? || tag_in_folder?(tag, folder))
    end
    private_class_method :tag_belongs_to_extension?

    def assign_folder(tag, folder)
      return tag unless tag.respond_to?(:folder=)
      return tag unless folder
      return tag if tag_in_folder?(tag, folder)

      tag.folder = folder
      tag
    end
    private_class_method :assign_folder

    def rename_tag(tag, target_name)
      current_name = tag.respond_to?(:name) ? tag.name.to_s : nil
      return if current_name == target_name
      tag.name = target_name if tag.respond_to?(:name=)
    end
    private_class_method :rename_tag
  end
end
