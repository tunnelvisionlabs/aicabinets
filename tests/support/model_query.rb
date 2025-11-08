# frozen_string_literal: true

module ModelQuery
  module_function

  def count_tagged(tag_name_or_category)
    model = Sketchup.active_model
    return 0 unless model.is_a?(Sketchup::Model)

    enumerate_entities(model.entities).count do |entity|
      matches_tag_category?(entity, tag_name_or_category)
    end
  end

  def shelves_by_bay(instance:)
    components_by_bay(instance, 'Shelves')
  end

  def fronts_by_bay(instance:)
    components_by_bay(instance, 'Fronts')
  end

  def front_entities(instance:)
    validate_instance(instance)

    entities = enumerate_entities(instance.definition.entities)
    entities_in_category(entities, 'Fronts').map do |entity|
      component_info(entity)
    end
  end

  def tag_name_for(entity)
    return unless entity.respond_to?(:layer)

    tag = entity.layer
    return unless tag&.valid?

    name = tag.respond_to?(:name) ? tag.name : nil
    name.to_s
  end

  def tag_category_for(entity)
    normalize_tag_category(tag_name_for(entity))
  end

  def components_by_bay(instance, tag_category)
    validate_instance(instance)

    definition = instance.definition
    result = Hash.new { |hash, key| hash[key] = [] }

    entities_in_category(definition.entities, tag_category).each do |entity|
      info = component_info(entity)
      result[info[:bay_index]] << info
    end

    result
  end
  private_class_method :components_by_bay

  def component_info(entity)
    bounds = entity.bounds
    {
      entity: entity,
      bay_index: bay_index_for(entity),
      bounds: bounds,
      width_mm: width_mm(bounds)
    }
  end
  private_class_method :component_info

  def bay_index_for(entity)
    [entity, entity.definition].each do |source|
      next unless source.respond_to?(:name)

      name = source.name.to_s
      match = name.match(/Bay\s+(\d+)/i)
      return Integer(match[1]) if match
    end

    1
  end
  private_class_method :bay_index_for

  def width_mm(bounds)
    return 0.0 unless bounds.is_a?(Geom::BoundingBox)

    length_to_mm(bounds.max.x - bounds.min.x)
  end
  private_class_method :width_mm

  def length_to_mm(length)
    if defined?(AICabinetsTestHelper)
      AICabinetsTestHelper.mm_from_length(length)
    elsif length.respond_to?(:to_f)
      length.to_f * 25.4
    else
      0.0
    end
  end
  private_class_method :length_to_mm

  def entities_in_category(entities, tag_category)
    collection = if entities.respond_to?(:grep)
                   entities
                 else
                   Array(entities)
                 end

    collection.grep(Sketchup::Drawingelement).select do |entity|
      matches_tag_category?(entity, tag_category)
    end
  end
  private_class_method :entities_in_category

  def matches_tag_category?(entity, desired)
    actual = tag_category_for(entity)
    expected = normalize_tag_category(desired)
    return false unless actual && expected

    actual.casecmp(expected).zero?
  end
  private_class_method :matches_tag_category?

  def normalize_tag_category(name)
    text = name.to_s.strip
    return nil if text.empty?

    text = text.sub(%r{\AAICabinets/}i, '')
    text = text.sub(/\s*\(AI Cabinets(?:\s*\d+)?\)\z/i, '')
    text.empty? ? nil : text
  end
  private_class_method :normalize_tag_category

  def enumerate_entities(entities)
    return [] unless entities.respond_to?(:each)

    results = []
    queue = [entities]
    visited = {}

    until queue.empty?
      current = queue.shift
      next unless current.respond_to?(:each)

      current.each do |entity|
        next unless entity&.valid?

        results << entity
        case entity
        when Sketchup::Group
          queue << entity.entities
        when Sketchup::ComponentInstance
          definition = entity.definition
          next unless definition&.valid?

          key = definition.object_id
          next if visited[key]

          visited[key] = true
          queue << definition.entities
        end
      end
    end

    results
  end
  private_class_method :enumerate_entities

  def validate_instance(instance)
    unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
      raise ArgumentError, 'instance must be a valid SketchUp::ComponentInstance'
    end
  end
  private_class_method :validate_instance
end
