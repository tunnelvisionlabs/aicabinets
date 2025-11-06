# frozen_string_literal: true

module AICabinets
  module Preview
    module Layout
      module_function

      def regions(config)
        data = symbolize_keys(config || {})
        partitions = symbolize_keys(data[:partitions] || {})

        orientation = resolve_orientation(data[:partition_mode], partitions[:orientation])
        bays = Array(partitions[:bays]).map.with_index do |bay, index|
          build_bay_region(bay, orientation, index)
        end

        {
          orientation: orientation,
          count: partitions[:count],
          bays: bays
        }
      end

      def build_bay_region(bay, parent_orientation, index)
        normalized = symbolize_keys(bay || {})
        mode = normalized[:mode] || 'fronts_shelves'
        region = {
          index: index,
          mode: mode,
          subpartitions: nil
        }

        if mode == 'subpartitions'
          sub = symbolize_keys(normalized[:subpartitions] || {})
          orientation = perpendicular_orientation(parent_orientation)
          nested = Array(sub[:bays]).map.with_index do |entry, nested_index|
            build_bay_region(entry, orientation, nested_index)
          end
          region[:subpartitions] = {
            count: sub[:count],
            orientation: orientation,
            bays: nested
          }
        end

        region
      end

      def resolve_orientation(mode, fallback)
        case mode
        when 'vertical'
          'vertical'
        when 'horizontal'
          'horizontal'
        else
          fallback || 'vertical'
        end
      end

      def perpendicular_orientation(orientation)
        orientation == 'horizontal' ? 'vertical' : 'horizontal'
      end

      def symbolize_keys(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, item), memo|
          memo[key.is_a?(String) ? key.to_sym : key] = item
        end
      end
    end
  end
end
