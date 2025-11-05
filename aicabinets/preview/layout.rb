# frozen_string_literal: true

module AICabinets
  module Preview
    # Pure layout planner for preview geometry. Transforms sanitized cabinet
    # configuration into rectangular regions and partition lines that the
    # renderer can consume without mutating state or touching the SketchUp API.
    module Layout
      Rect = Struct.new(:left, :right, :bottom, :top, keyword_init: true) do
        def width
          right - left
        end

        def height
          top - bottom
        end
      end

      ContainerPlan = Struct.new(:orientation, :bays, keyword_init: true)
      BayPlan = Struct.new(:rect, :sub_plan, keyword_init: true)
      Line = Struct.new(:orientation, :position, :range_start, :range_end, keyword_init: true)
      Plan = Struct.new(:outline, :container_plan, :highlight_rect, keyword_init: true)

      module_function

      def plan(config, selected_path: nil)
        params = config.is_a?(Hash) ? config : {}
        width = fetch_numeric(params, :width_mm) || 0.0
        height = fetch_numeric(params, :height_mm) || 0.0

        outline = Rect.new(left: 0.0, right: [width, 0.0].max, bottom: 0.0, top: [height, 0.0].max)

        container = fetch_hash(params, :partitions)
        partition_mode = normalize_partition_mode(params[:partition_mode] || params['partition_mode'])
        orientation = normalize_orientation(container[:orientation] || container['orientation'])

        container_plan =
          if partition_mode == :none
            build_single_bay_plan(outline, orientation)
          else
            build_container_plan(outline, container, allow_nested: true)
          end

        highlight = resolve_highlight_rect(container_plan, Array(selected_path)) || outline

        Plan.new(outline: outline, container_plan: container_plan, highlight_rect: highlight)
      rescue StandardError => e
        warn("AI Cabinets: Unable to build preview layout: #{e.message}")
        build_fallback_plan(outline)
      end

      def collect_lines(container_plan)
        lines = []
        traverse_partitions(container_plan, lines)
        lines
      end

      def build_single_bay_plan(rect, orientation)
        orientation = normalize_orientation(orientation)
        ContainerPlan.new(
          orientation: orientation,
          bays: [BayPlan.new(rect: Rect.new(left: rect.left, right: rect.right, bottom: rect.bottom, top: rect.top), sub_plan: nil)]
        )
      end

      def build_container_plan(rect, container, allow_nested:)
        orientation = normalize_orientation(container[:orientation] || container['orientation'])
        bays_config = fetch_array(container, :bays)
        count_value = integer_value(container[:count] || container['count'])
        desired_count = bays_config.length.positive? ? bays_config.length : (count_value || 0) + 1
        desired_count = 1 if desired_count < 1

        segments =
          if orientation == :horizontal
            compute_segments(rect.height, desired_count, fetch_positions(container))
          else
            compute_segments(rect.width, desired_count, fetch_positions(container))
          end

        bays = segments.each_with_index.map do |(start_mm, finish_mm), index|
          child_rect =
            if orientation == :horizontal
              Rect.new(
                left: rect.left,
                right: rect.right,
                bottom: rect.bottom + start_mm,
                top: rect.bottom + finish_mm
              )
            else
              Rect.new(
                left: rect.left + start_mm,
                right: rect.left + finish_mm,
                bottom: rect.bottom,
                top: rect.top
              )
            end

          bay_config = bays_config[index] || {}
          sub_plan =
            if allow_nested
              sub_container = fetch_hash(bay_config, :subpartitions)
              if valid_subpartition_count?(sub_container)
                build_container_plan(child_rect, sub_container, allow_nested: false)
              end
            end

          BayPlan.new(rect: child_rect, sub_plan: sub_plan)
        end

        ContainerPlan.new(orientation: orientation, bays: bays)
      end

      def traverse_partitions(container_plan, lines)
        return unless container_plan.is_a?(ContainerPlan)

        bays = container_plan.bays || []
        orientation = container_plan.orientation || :vertical

        if bays.length > 1
          bays.each_with_index do |bay, index|
            next if index.zero?

            line =
              if orientation == :horizontal
                Line.new(
                  orientation: :horizontal,
                  position: bay.rect.bottom,
                  range_start: bays.first.rect.left,
                  range_end: bays.first.rect.right
                )
              else
                Line.new(
                  orientation: :vertical,
                  position: bay.rect.left,
                  range_start: bays.first.rect.bottom,
                  range_end: bays.first.rect.top
                )
              end
            lines << line
          end
        end

        bays.each do |bay|
          traverse_partitions(bay.sub_plan, lines) if bay.sub_plan
        end
      end
      private_class_method :traverse_partitions

      def resolve_highlight_rect(container_plan, selected_path)
        return nil unless container_plan.is_a?(ContainerPlan)

        bays = container_plan.bays || []
        return nil if bays.empty?

        index = index_from_path(selected_path.shift, bays.length)
        bay = bays[index] || bays.first

        if selected_path.empty? || !bay.sub_plan
          bay.rect
        else
          resolve_highlight_rect(bay.sub_plan, selected_path)
        end
      end
      private_class_method :resolve_highlight_rect

      def index_from_path(value, length)
        numeric = Integer(value, exception: false)
        numeric = 0 if numeric.nil?
        numeric = 0 if numeric.negative?
        numeric = length - 1 if numeric >= length
        numeric
      end
      private_class_method :index_from_path

      def build_fallback_plan(outline)
        container_plan = ContainerPlan.new(
          orientation: :vertical,
          bays: [BayPlan.new(rect: Rect.new(left: outline.left, right: outline.right, bottom: outline.bottom, top: outline.top), sub_plan: nil)]
        )
        Plan.new(outline: outline, container_plan: container_plan, highlight_rect: outline)
      end
      private_class_method :build_fallback_plan

      def valid_subpartition_count?(sub_container)
        return false unless sub_container.is_a?(Hash)

        count = integer_value(sub_container[:count] || sub_container['count'])
        bays = fetch_array(sub_container, :bays)
        count = bays.length - 1 if count.nil? && bays.length > 1
        count && count >= 1
      end
      private_class_method :valid_subpartition_count?

      def fetch_numeric(hash, key)
        return unless hash.is_a?(Hash)

        value = hash[key] || hash[key.to_s]
        return value if value.is_a?(Numeric)

        numeric = Float(value, exception: false)
        numeric if numeric.is_a?(Numeric)
      end
      private_class_method :fetch_numeric

      def fetch_hash(hash, key)
        candidate = hash[key] || hash[key.to_s]
        candidate.is_a?(Hash) ? candidate : {}
      end
      private_class_method :fetch_hash

      def fetch_array(hash, key)
        candidate = hash[key] || hash[key.to_s]
        candidate.is_a?(Array) ? candidate : []
      end
      private_class_method :fetch_array

      def fetch_positions(container)
        positions = container[:positions_mm] || container['positions_mm']
        return [] unless positions.is_a?(Array)

        positions.map do |value|
          converted = Float(value, exception: false)
          converted if converted.is_a?(Numeric)
        end.compact
      end
      private_class_method :fetch_positions

      def integer_value(value)
        return nil if value.nil?

        Integer(value, exception: false)
      end
      private_class_method :integer_value

      def normalize_orientation(value)
        text = value.to_s.downcase
        text == 'horizontal' ? :horizontal : :vertical
      end
      private_class_method :normalize_orientation

      def normalize_partition_mode(value)
        case value.to_s.downcase
        when 'vertical'
          :vertical
        when 'horizontal'
          :horizontal
        when 'none'
          :none
        else
          :unknown
        end
      end
      private_class_method :normalize_partition_mode

      def compute_segments(total_length, segment_count, positions)
        return Array.new(segment_count) { [0.0, 0.0] } if segment_count <= 0
        return [[0.0, total_length.to_f]] if segment_count == 1

        total = total_length.to_f
        sanitized_positions = sanitize_positions(positions, total, segment_count)

        if sanitized_positions.length == segment_count - 1
          points = [0.0] + sanitized_positions + [total]
          points.each_cons(2).map { |left, right| [left, right] }
        else
          step = segment_count.positive? ? total / segment_count : 0.0
          Array.new(segment_count) do |index|
            left = step * index
            right = index == segment_count - 1 ? total : left + step
            [left, right]
          end
        end
      end
      private_class_method :compute_segments

      def sanitize_positions(positions, total_length, segment_count)
        return [] unless positions.is_a?(Array)

        filtered = positions.map do |value|
          converted = Float(value, exception: false)
          converted if converted.is_a?(Numeric)
        end.compact
        filtered = filtered.select { |value| value.positive? && value < total_length }
        filtered = filtered.uniq.sort
        filtered.first(segment_count - 1)
      end
      private_class_method :sanitize_positions
    end
  end
end
