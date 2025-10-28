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
    OWNED_TAG_PREFIX = 'AICabinets/'.freeze
    TAG_DICTIONARY = 'AICabinets::Tags'.freeze
    TAG_CATEGORY_KEY = 'category'.freeze
    OWNED_TAG_BASE_NAMES = %w[
      Cabinet
      Sides
      Bottom
      Top
      Stretchers
      Back
      ToeKick
      Partitions
      Shelves
      Fronts
    ].freeze

    def ensure_structure!(model)
      return unless model.is_a?(Sketchup::Model)

      layers = model.layers
      return ensure_legacy_cabinet_tag(layers) unless supports_tag_folders?(layers)

      folder = infer_folder(layers)
      base_names = owned_base_names_present(layers)
      base_names << CABINET_TAG_NAME unless base_names.include?(CABINET_TAG_NAME)

      changes_required =
        folder.nil? ||
        base_names.any? { |base_name| normalization_required?(layers, folder, base_name) }

      tag = nil
      operation_open = false
      begin
        if changes_required
          operation_open = model.start_operation(OPERATION_NAME, true)
          folder ||= layers.add_folder(CABINET_FOLDER_NAME)

          base_names.each do |base_name|
            create = base_name == CABINET_TAG_NAME
            normalize_owned_tag(layers, folder, base_name, create_if_missing: create)
          end

          tag = normalize_owned_tag(layers, folder, CABINET_TAG_NAME, create_if_missing: true)

          model.commit_operation if operation_open
          operation_open = false
        else
          folder ||= infer_folder(layers)
          tag = normalize_owned_tag(layers, folder, CABINET_TAG_NAME, create_if_missing: true)
        end
      ensure
        model.abort_operation if operation_open
      end

      tag
    rescue StandardError => error
      warn("AI Cabinets: Failed to ensure cabinet tag structure: #{error.message}")
      layers[CABINET_TAG_NAME] ||
        layers[CABINET_TAG_COLLISION_NAME] ||
        layers[LEGACY_CABINET_TAG_NAME]
    end

    def ensure_owned_tag(model, name)
      raise ArgumentError, 'model must be a SketchUp::Model' unless model.is_a?(Sketchup::Model)

      base_name = owned_base_name_from(name)
      raise ArgumentError, 'name must reference an AI Cabinets tag' unless base_name

      layers = model.layers
      if supports_tag_folders?(layers)
        ensure_structure!(model)
        folder = infer_folder(layers)
        return ensure_legacy_tag(layers, base_name) unless folder

        normalize_owned_tag(layers, folder, base_name, create_if_missing: true)
      else
        ensure_legacy_tag(layers, base_name)
      end
    end

    def supports_tag_folders?(layers)
      defined?(Sketchup::LayerFolder) &&
        layers.respond_to?(:add_folder) &&
        layers.respond_to?(:folders) &&
        Sketchup::Layer.instance_methods.include?(:folder=)
    end
    private_class_method :supports_tag_folders?

    def ensure_legacy_cabinet_tag(layers)
      legacy = layers[LEGACY_CABINET_TAG_NAME]
      legacy || layers.add(LEGACY_CABINET_TAG_NAME)
    end
    private_class_method :ensure_legacy_cabinet_tag

    def ensure_legacy_tag(layers, base_name)
      legacy_name = legacy_name_for(base_name)
      layers[legacy_name] || layers.add(legacy_name)
    end
    private_class_method :ensure_legacy_tag

    def owned_base_name_from(name)
      return name.sub(OWNED_TAG_PREFIX, '') if name.is_a?(String) && name.start_with?(OWNED_TAG_PREFIX)
      return name if name.is_a?(String) && OWNED_TAG_BASE_NAMES.include?(name)

      nil
    end
    private_class_method :owned_base_name_from

    def owned_base_names_present(layers)
      names = []
      return names unless layers.respond_to?(:each)

      layers.each do |tag|
        base_name = base_name_from_tag(tag)
        next unless base_name
        names << base_name unless names.include?(base_name)
      end

      names
    end
    private_class_method :owned_base_names_present

    def base_name_from_tag(tag)
      return unless tag.respond_to?(:name)

      base_name = tag.get_attribute(TAG_DICTIONARY, TAG_CATEGORY_KEY) if tag.respond_to?(:get_attribute)
      return base_name if base_name.is_a?(String) && !base_name.empty?

      name = tag.name.to_s
      return name.sub(OWNED_TAG_PREFIX, '') if name.start_with?(OWNED_TAG_PREFIX)

      fallback = fallback_base_name(name)
      return fallback if fallback

      folder = tag.respond_to?(:folder) ? tag.folder : nil
      return name if folder && folder_display_name(folder) == CABINET_FOLDER_NAME

      nil
    end
    private_class_method :base_name_from_tag

    def fallback_base_name(name)
      match = name.match(/\A(.+?) \(AI Cabinets(?: \d+)?\)\z/)
      return unless match

      match[1]
    end
    private_class_method :fallback_base_name

    def normalization_required?(layers, folder, base_name)
      folder ||= infer_folder(layers)
      return true unless folder

      legacy_tag = layers[legacy_name_for(base_name)]
      return true if legacy_tag

      owned_tag = find_marked_tag(layers, base_name)
      if owned_tag
        return false if tag_in_folder?(owned_tag, folder)
        return true
      end

      preferred_tag = layers[base_name]
      if base_name == CABINET_TAG_NAME && likely_owned_cabinet_tag?(layers, preferred_tag) &&
         !tag_in_folder?(preferred_tag, folder)
        return true
      end

      return true if collision_tag?(layers, preferred_tag, folder, base_name)

      fallback_tag = find_fallback_candidate(layers, base_name)
      return true if collision_tag?(layers, fallback_tag, folder, base_name)

      return true if base_name == CABINET_TAG_NAME && preferred_tag.nil? && fallback_tag.nil? && owned_tag.nil?

      false
    end
    private_class_method :normalization_required?

    def find_marked_tag(layers, base_name)
      return unless layers.respond_to?(:each)

      layers.each do |tag|
        return tag if owned_tag?(tag, base_name)
      end

      nil
    end
    private_class_method :find_marked_tag

    def find_fallback_candidate(layers, base_name)
      fallback_name = fallback_name_for(base_name)
      candidate = layers[fallback_name]
      return candidate if candidate

      find_marked_tag(layers, base_name)
    end
    private_class_method :find_fallback_candidate

    def collision_tag?(layers, tag, folder, base_name)
      return false unless tag
      return false if usable_as_owned_tag?(layers, tag, folder, base_name)

      true
    end
    private_class_method :collision_tag?

    def usable_as_owned_tag?(layers, tag, folder, base_name)
      return false unless tag.respond_to?(:valid?) && tag.valid?
      return true if owned_tag?(tag, base_name)

      tag_folder = tag.respond_to?(:folder) ? tag.folder : nil
      if tag_folder && folder && folder_display_name(tag_folder) == CABINET_FOLDER_NAME
        return true if owned_tag?(tag) || tag.name.to_s == base_name
      end

      base_name == CABINET_TAG_NAME && likely_owned_cabinet_tag?(layers, tag)
    end
    private_class_method :usable_as_owned_tag?

    def owned_tag?(tag, base_name = nil)
      return false unless tag.respond_to?(:get_attribute)

      value = tag.get_attribute(TAG_DICTIONARY, TAG_CATEGORY_KEY)
      return false unless value.is_a?(String) && !value.empty?

      return value == base_name if base_name

      true
    end
    private_class_method :owned_tag?

    def normalize_owned_tag(layers, folder, base_name, create_if_missing:)
      return unless folder

      owned_tag = find_marked_tag(layers, base_name)
      if owned_tag
        assign_folder(owned_tag, folder)
        return owned_tag
      end

      legacy_tag = layers[legacy_name_for(base_name)]
      preferred_tag = layers[base_name]
      collision = collision_tag?(layers, preferred_tag, folder, base_name)

      if legacy_tag
        target_name = next_available_owned_name(layers, base_name, prefer_base: !collision, except: [legacy_tag])
        migrate_tag_to_owned(legacy_tag, folder, target_name, base_name)
        return legacy_tag
      end

      if preferred_tag && !collision
        assign_folder(preferred_tag, folder)
        mark_owned_tag(preferred_tag, base_name)
        return preferred_tag
      end

      fallback_tag = find_fallback_candidate(layers, base_name)
      if fallback_tag && usable_as_owned_tag?(layers, fallback_tag, folder, base_name)
        assign_folder(fallback_tag, folder)
        mark_owned_tag(fallback_tag, base_name)
        return fallback_tag
      end

      return nil unless create_if_missing

      target_name = next_available_owned_name(layers, base_name, prefer_base: !collision, except: [])
      tag = layers[target_name] || layers.add(target_name)
      assign_folder(tag, folder)
      mark_owned_tag(tag, base_name)
      tag
    end
    private_class_method :normalize_owned_tag

    def migrate_tag_to_owned(tag, folder, target_name, base_name)
      visibility = tag.visible? if tag.respond_to?(:visible?)
      rename_tag(tag, target_name)
      assign_folder(tag, folder)
      mark_owned_tag(tag, base_name)
      if !visibility.nil? && tag.respond_to?(:visible=) && tag.visible? != visibility
        tag.visible = visibility
      end
      tag
    end
    private_class_method :migrate_tag_to_owned

    def next_available_owned_name(layers, base_name, prefer_base:, except: [])
      candidates = []
      candidates << base_name if prefer_base

      fallback_base = fallback_name_for(base_name)
      suffix = 1
      loop do
        candidate = suffix == 1 ? fallback_base : "#{fallback_base} #{suffix}"
        candidates << candidate
        suffix += 1
        break if candidates.length > 16 # prevent runaway loops
      end

      candidates.each do |candidate|
        return candidate if available_tag_name?(layers, candidate, except: except)
      end

      attempt = suffix
      loop do
        candidate = "#{fallback_base} #{attempt}"
        return candidate if available_tag_name?(layers, candidate, except: except)
        attempt += 1
      end
    end
    private_class_method :next_available_owned_name

    def available_tag_name?(layers, name, except: [])
      tag = layers[name]
      return true unless tag

      except.any? { |candidate| candidate.equal?(tag) }
    end
    private_class_method :available_tag_name?

    def legacy_name_for(base_name)
      "#{OWNED_TAG_PREFIX}#{base_name}"
    end
    private_class_method :legacy_name_for

    def fallback_name_for(base_name)
      return CABINET_TAG_COLLISION_NAME if base_name == CABINET_TAG_NAME

      "#{base_name} (AI Cabinets)"
    end
    private_class_method :fallback_name_for

    def infer_folder(layers)
      find_folder(layers, CABINET_FOLDER_NAME) ||
        folder_from_tag(layers[CABINET_TAG_NAME]) ||
        folder_from_tag(layers[CABINET_TAG_COLLISION_NAME])
    end
    private_class_method :infer_folder

    def find_folder(layers, display_name)
      return unless layers.respond_to?(:folders)

      layers.folders.find do |folder|
        folder_display_name(folder) == display_name
      end
    end
    private_class_method :find_folder

    def folder_from_tag(tag)
      return unless tag.respond_to?(:folder)

      folder = tag.folder
      return unless folder
      return folder if folder_display_name(folder) == CABINET_FOLDER_NAME
    end
    private_class_method :folder_from_tag

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

    def tag_in_folder?(tag, folder)
      return false unless tag && folder
      return false unless tag.respond_to?(:folder)

      current_folder = tag.folder
      return false unless current_folder

      current_folder == folder || folder_display_name(current_folder) == folder_display_name(folder)
    end
    private_class_method :tag_in_folder?

    def assign_folder(tag, folder)
      return tag unless tag.respond_to?(:folder=)
      return tag unless folder
      return tag if tag_in_folder?(tag, folder)

      tag.folder = folder
      tag
    end
    private_class_method :assign_folder

    def mark_owned_tag(tag, base_name)
      return unless tag.respond_to?(:set_attribute)

      tag.set_attribute(TAG_DICTIONARY, TAG_CATEGORY_KEY, base_name)
    end
    private_class_method :mark_owned_tag

    def rename_tag(tag, target_name)
      return unless tag.respond_to?(:name)
      return unless tag.respond_to?(:name=)

      current_name = tag.name.to_s
      return if current_name == target_name

      tag.name = target_name
    end
    private_class_method :rename_tag

    def likely_owned_cabinet_tag?(layers, tag)
      return false unless tag
      return false unless tag.respond_to?(:name)

      name = tag.name.to_s
      return false unless name == CABINET_TAG_NAME

      return true if owned_tag?(tag, CABINET_TAG_NAME)

      folder = tag.respond_to?(:folder) ? tag.folder : nil
      return true if folder && folder_display_name(folder) == CABINET_FOLDER_NAME

      other_owned_tags_present?(layers, exclude: tag)
    end
    private_class_method :likely_owned_cabinet_tag?

    def other_owned_tags_present?(layers, exclude: nil)
      return false unless layers.respond_to?(:each)

      layers.each do |candidate|
        next if exclude && candidate.equal?(exclude)

        base_name = base_name_from_tag(candidate)
        next unless base_name

        return true
      end

      false
    end
    private_class_method :other_owned_tags_present?
  end
end
