# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  DEFAULT_PANEL_THICKNESS = 19.mm
  DEFAULT_BACK_THICKNESS = 6.mm
  DEFAULT_HOLE_DIAMETER = 5.mm
  DEFAULT_HOLE_DEPTH = 13.mm
  DEFAULT_HOLE_SPACING = 32.mm

  # Creates a row of simple frameless cabinets formed from discrete panels.
  #
  # The data structure is a hash with global defaults and an array of
  # individual cabinet descriptions. Example:
  #
  # {
  #   height: 720.mm,
  #   depth: 350.mm,
  #   panel_thickness: 19.mm,
  #   back_thickness: 6.mm,
  #   shelf_count: 0,
  #   hole_diameter: 5.mm,
  #   hole_depth: 13.mm,
  #   hole_spacing: 32.mm,
  #   cabinets: [
  #     {
  #       width: 600.mm,
  #       shelf_count: 2,
  #       hole_columns: [
  #         { distance: 37.mm, first_hole: 10.mm, skip: 2, count: 5 }
  #       ]
  #     }
  #   ]
  # }
  #
  # Each cabinet uses the global defaults unless overridden in its own hash.
  # Cabinets are created left to right.
  #
  # @param config [Hash] cabinet row description
  def self.create_frameless_cabinet(config)
    model = Sketchup.active_model
    entities = model.entities

    defaults = {
      panel_thickness: DEFAULT_PANEL_THICKNESS,
      back_thickness: DEFAULT_BACK_THICKNESS,
      shelf_count: 0,
      hole_diameter: DEFAULT_HOLE_DIAMETER,
      hole_depth: DEFAULT_HOLE_DEPTH,
      hole_spacing: DEFAULT_HOLE_SPACING,
      hole_columns: []
    }.merge(config)

    height = defaults[:height]
    depth = defaults[:depth]
    x_offset = 0

    (config[:cabinets] || []).each do |cabinet|
      cab_opts = defaults.merge(cabinet)

      width = cab_opts[:width]
      panel_thickness = cab_opts[:panel_thickness]
      back_thickness = cab_opts[:back_thickness]
      shelf_count = cab_opts[:shelf_count]
      hole_diameter = cab_opts[:hole_diameter]
      hole_depth = cab_opts[:hole_depth]
      hole_spacing = cab_opts[:hole_spacing]
      hole_columns = cab_opts[:hole_columns] || []

      create_single_cabinet(
        entities,
        x_offset: x_offset,
        width: width,
        height: height,
        depth: depth,
        panel_thickness: panel_thickness,
        back_thickness: back_thickness,
        shelf_count: shelf_count,
        hole_diameter: hole_diameter,
        hole_depth: hole_depth,
        hole_spacing: hole_spacing,
        hole_columns: hole_columns
      )

      x_offset += width
    end
  end

  # Internal helper that constructs a cabinet at the given X offset.
  # @param entities [Sketchup::Entities]
  # @param x_offset [Length] start position along the X axis
  # @param width [Length]
  # @param height [Length]
  # @param depth [Length]
  # @param panel_thickness [Length]
  # @param back_thickness [Length]
  # @param shelf_count [Integer]
  # @param hole_diameter [Length]
  # @param hole_depth [Length]
  # @param hole_spacing [Length]
  # @param hole_columns [Array<Hash>]
  def self.create_single_cabinet(
    entities,
    x_offset:,
    width:,
    height:,
    depth:,
    panel_thickness:,
    back_thickness:,
    shelf_count:,
    hole_diameter:,
    hole_depth:,
    hole_spacing:,
    hole_columns: []
  )
    cabinet = entities.add_group
    g = cabinet.entities

    # Sides
    left = g.add_group
    left.entities.add_face(
      [x_offset, 0, 0],
      [x_offset, depth, 0],
      [x_offset, depth, height],
      [x_offset, 0, height]
    ).pushpull(panel_thickness)

    right = g.add_group
    right.entities.add_face(
      [x_offset + width, 0, 0],
      [x_offset + width, depth, 0],
      [x_offset + width, depth, height],
      [x_offset + width, 0, height]
    ).pushpull(-panel_thickness)

    drill_hole_columns(
      left.entities,
      x: x_offset + panel_thickness,
      depth: depth,
      panel_thickness: panel_thickness,
      back_thickness: back_thickness,
      hole_diameter: hole_diameter,
      hole_depth: hole_depth,
      hole_spacing: hole_spacing,
      columns: hole_columns,
      from_right: false
    )

    drill_hole_columns(
      right.entities,
      x: x_offset + width - panel_thickness,
      depth: depth,
      panel_thickness: panel_thickness,
      back_thickness: back_thickness,
      hole_diameter: hole_diameter,
      hole_depth: hole_depth,
      hole_spacing: hole_spacing,
      columns: hole_columns,
      from_right: true
    )

    # Bottom
    bottom = g.add_group
    bottom.entities.add_face(
      [x_offset + panel_thickness, 0, 0],
      [x_offset + width - panel_thickness, 0, 0],
      [x_offset + width - panel_thickness, depth, 0],
      [x_offset + panel_thickness, depth, 0]
    ).pushpull(-panel_thickness)

    # Top
    top = g.add_group
    top.entities.add_face(
      [x_offset + panel_thickness, 0, height - panel_thickness],
      [x_offset + width - panel_thickness, 0, height - panel_thickness],
      [x_offset + width - panel_thickness, depth, height - panel_thickness],
      [x_offset + panel_thickness, depth, height - panel_thickness]
    ).pushpull(panel_thickness)

    # Back inset between the sides and flush with the top of the bottom panel
    # and the underside of the top panel
    back = g.add_group
    back.entities.add_face(
      [x_offset + panel_thickness, depth, panel_thickness],
      [x_offset + width - panel_thickness, depth, panel_thickness],
      [x_offset + width - panel_thickness, depth, height - panel_thickness],
      [x_offset + panel_thickness, depth, height - panel_thickness]
    ).pushpull(back_thickness)

    # Shelves
    if shelf_count > 0
      shelf_thickness = panel_thickness
      interior_height = height - panel_thickness * 2
      spacing = interior_height / (shelf_count + 1)
      shelf_depth = depth - back_thickness

      shelf_count.times do |i|
        z = panel_thickness + spacing * (i + 1)
        shelf = g.add_group
        shelf.entities.add_face(
          [x_offset + panel_thickness, 0, z],
          [x_offset + width - panel_thickness, 0, z],
          [x_offset + width - panel_thickness, shelf_depth, z],
          [x_offset + panel_thickness, shelf_depth, z]
        ).pushpull(-shelf_thickness)
      end
    end
  end

  def self.drill_hole_columns(
    entities,
    x:,
    depth:,
    panel_thickness:,
    back_thickness:,
    hole_diameter:,
    hole_depth:,
    hole_spacing:,
    columns:,
    from_right: false
  )
    normal = Geom::Vector3d.new(from_right ? -1 : 1, 0, 0)

    columns.each do |col|
      dist = col[:distance] || 0
      y = if col[:from] == :rear
            depth - back_thickness - dist
          else
            dist
          end

      spacing = col[:spacing] || hole_spacing
      diameter = col[:diameter] || hole_diameter
      depth_drill = col[:depth] || hole_depth
      radius_col = diameter / 2
      skip = col[:skip].to_i
      first = col[:first_hole] || 0
      z_start = panel_thickness + first + spacing * skip
      count = col[:count].to_i

      count.times do |i|
        z = z_start + spacing * i
        center = Geom::Point3d.new(x, y, z)
        edges = entities.add_circle(center, normal, radius_col)
        face = entities.add_face(edges)
        face.pushpull(-depth_drill)
      end
    end
  end
end

