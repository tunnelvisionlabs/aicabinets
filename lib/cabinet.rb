# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  DEFAULT_PANEL_THICKNESS = 19.mm
  DEFAULT_BACK_THICKNESS = 6.mm
  DEFAULT_HOLE_DIAMETER = 5.mm
  DEFAULT_HOLE_DEPTH = 13.mm
  DEFAULT_HOLE_SPACING = 32.mm
  DEFAULT_DOOR_THICKNESS = 19.mm
  DEFAULT_DOOR_TYPE = :full_overlay
  DEFAULT_DOOR_STYLE = :slab
  DEFAULT_DOOR_REVEAL = 2.mm
  DEFAULT_RAIL_WIDTH = 70.mm
  DEFAULT_STILE_WIDTH = 70.mm
  DEFAULT_BEVEL_ANGLE = 15.degrees
  DEFAULT_PROFILE_DEPTH = 6.mm
  DEFAULT_GROOVE_WIDTH = 6.mm
  DEFAULT_GROOVE_DEPTH = 9.5.mm
  DOOR_BUMPER_GAP = 2.mm

  # Axis orientation helper:
  #   X increases left → right
  #   Y increases front → back (front has the lowest Y value)
  #   Z increases bottom → top

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
      hole_columns: [],
      door_thickness: DEFAULT_DOOR_THICKNESS,
      door_type: DEFAULT_DOOR_TYPE,
      door_style: DEFAULT_DOOR_STYLE,
      door_reveal: DEFAULT_DOOR_REVEAL,
      rail_width: DEFAULT_RAIL_WIDTH,
      stile_width: DEFAULT_STILE_WIDTH,
      bevel_angle: DEFAULT_BEVEL_ANGLE,
      profile_depth: DEFAULT_PROFILE_DEPTH,
      groove_width: DEFAULT_GROOVE_WIDTH,
      groove_depth: DEFAULT_GROOVE_DEPTH
    }.merge(config)

    height = defaults[:height]
    depth = defaults[:depth]

    cabinets = (config[:cabinets] || []).map { |cab| defaults.merge(cab) }

    cabinets.each do |cab|
      cab[:left_reveal] = cab[:door_reveal]
      cab[:right_reveal] = cab[:door_reveal]
    end

    cabinets.each_cons(2) do |left, right|
      next unless left[:doors] && right[:doors]

      left[:right_reveal] = left[:door_reveal] / 2
      right[:left_reveal] = right[:door_reveal] / 2
    end

    x_offset = 0
    cabinets.each do |cab_opts|
      create_single_cabinet(
        entities,
        x_offset: x_offset,
        width: cab_opts[:width],
        height: height,
        depth: depth,
        panel_thickness: cab_opts[:panel_thickness],
        back_thickness: cab_opts[:back_thickness],
        shelf_count: cab_opts[:shelf_count],
        hole_diameter: cab_opts[:hole_diameter],
        hole_depth: cab_opts[:hole_depth],
        hole_spacing: cab_opts[:hole_spacing],
        hole_columns: cab_opts[:hole_columns] || [],
        door_thickness: cab_opts[:door_thickness],
        door_type: cab_opts[:door_type],
        door_style: cab_opts[:door_style],
        door_reveal: cab_opts[:door_reveal],
        rail_width: cab_opts[:rail_width],
        stile_width: cab_opts[:stile_width],
        bevel_angle: cab_opts[:bevel_angle],
        profile_depth: cab_opts[:profile_depth],
        groove_width: cab_opts[:groove_width],
        groove_depth: cab_opts[:groove_depth],
        left_door_reveal: cab_opts[:left_reveal],
        right_door_reveal: cab_opts[:right_reveal],
        doors: cab_opts[:doors]
      )

      x_offset += cab_opts[:width]
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
    hole_columns: [],
    door_thickness:,
    door_type:,
    door_style:,
    door_reveal:,
    rail_width:,
    stile_width:,
    bevel_angle:,
    profile_depth:,
    groove_width:,
    groove_depth:,
    left_door_reveal: door_reveal,
    right_door_reveal: door_reveal,
    doors: nil
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
      shelf_depth = depth - back_thickness

      positions = if shelf_count > 0 && hole_columns.any?
                    col = hole_columns.first
                    spacing_holes = col[:spacing] || hole_spacing
                    first = col[:first_hole] || 0
                    skip = col[:skip].to_i
                    diameter = col[:diameter] || hole_diameter
                    base = panel_thickness + first + spacing_holes * skip + diameter / 2
                    spacing_even = interior_height / (shelf_count + 1)

                    Array.new(shelf_count) do |i|
                      desired_top = panel_thickness + spacing_even * (i + 1)
                      desired_bottom = desired_top - shelf_thickness
                      hole_top = align_to_hole_top(desired_bottom, base, spacing_holes)
                      hole_top + shelf_thickness
                    end
                  else
                    spacing_even = interior_height / (shelf_count + 1)
                    Array.new(shelf_count) { |i| panel_thickness + spacing_even * (i + 1) }
                  end

      positions.each do |z|
        shelf = g.add_group
        shelf.entities.add_face(
          [x_offset + panel_thickness, 0, z],
          [x_offset + width - panel_thickness, 0, z],
          [x_offset + width - panel_thickness, shelf_depth, z],
          [x_offset + panel_thickness, shelf_depth, z]
        ).pushpull(-shelf_thickness)
      end
    end

    add_doors(
      g,
      x_offset: x_offset,
      width: width,
      height: height,
      door_thickness: door_thickness,
      door_reveal: door_reveal,
      left_reveal: left_door_reveal,
      right_reveal: right_door_reveal,
      type: door_type,
      style: door_style,
      rail_width: rail_width,
      stile_width: stile_width,
      bevel_angle: bevel_angle,
      profile_depth: profile_depth,
      groove_width: groove_width,
      groove_depth: groove_depth,
      orientation: doors
    )
  end

  def self.add_doors(
    entities,
    x_offset:,
    width:,
    height:,
    door_thickness:,
    door_reveal:,
    left_reveal:,
    right_reveal:,
    type:,
    style:,
    rail_width:,
    stile_width:,
    bevel_angle:,
    profile_depth:,
    groove_width:,
    groove_depth:,
    orientation:
  )
    return unless orientation
    return unless type == :full_overlay

    door_height = height - 2 * door_reveal
    z = door_reveal
    gap = DOOR_BUMPER_GAP
    if orientation == :double
      door_width = (width - left_reveal - right_reveal - door_reveal) / 2
      x_start = x_offset + left_reveal
      2.times do |i|
        create_door_panel(
          entities,
          x_start + i * (door_width + door_reveal),
          door_width,
          door_height,
          z,
          door_thickness,
          gap,
          style: style,
          rail_width: rail_width,
          stile_width: stile_width,
          bevel_angle: bevel_angle,
          profile_depth: profile_depth,
          groove_width: groove_width,
          groove_depth: groove_depth
        )
      end
    else
      door_width = width - left_reveal - right_reveal
      x_start = x_offset + left_reveal
      create_door_panel(
        entities,
        x_start,
        door_width,
        door_height,
        z,
        door_thickness,
        gap,
        style: style,
        rail_width: rail_width,
        stile_width: stile_width,
        bevel_angle: bevel_angle,
        profile_depth: profile_depth,
        groove_width: groove_width,
        groove_depth: groove_depth
      )
    end
  end

  def self.create_door_panel(
    entities,
    x,
    width,
    height,
    z,
    thickness,
    gap,
    style: :slab,
    rail_width: DEFAULT_RAIL_WIDTH,
    stile_width: DEFAULT_STILE_WIDTH,
    bevel_angle: DEFAULT_BEVEL_ANGLE,
    profile_depth: DEFAULT_PROFILE_DEPTH,
    groove_width: DEFAULT_GROOVE_WIDTH,
    groove_depth: DEFAULT_GROOVE_DEPTH
  )
    group = entities.add_group
    y = -gap

    if style == :slab
      face = group.entities.add_face(
        [x, y, z],
        [x + width, y, z],
        [x + width, y, z + height],
        [x, y, z + height]
      )
      face.pushpull(thickness)
      return group
    end

    rail = rail_width
    stile = stile_width
    profile = profile_depth
    run = if bevel_angle.to_f.zero?
            0
          else
            [profile * Math.tan(bevel_angle), rail, stile].min
          end
    front_y = y - thickness
    groove_front_y = front_y + profile
    groove_back_y = groove_front_y + groove_width

    # Left stile
    left = group.entities.add_group
    l_face = left.entities.add_face(
      [x, y, z],
      [x + stile, y, z],
      [x + stile, y, z + height],
      [x, y, z + height]
    )
    l_face.pushpull(thickness)
    bevel_left = left.entities.add_face(
      [x + stile, front_y, z],
      [x + stile, groove_front_y, z],
      [x + stile - run, front_y, z]
    )
    bevel_left.pushpull(-height)
    groove_left = left.entities.add_face(
      [x + stile, groove_front_y, z],
      [x + stile, groove_back_y, z],
      [x + stile - groove_depth, groove_back_y, z],
      [x + stile - groove_depth, groove_front_y, z]
    )
    groove_left.pushpull(-height)

    # Bottom rail from the left stile
    bottom = left.copy
    rotate_bottom = Geom::Transformation.rotation([x, 0, z], Geom::Vector3d.new(0, 1, 0), -90.degrees)
    bottom.transform!(rotate_bottom)
    rail_length = width - 2 * stile + 2 * groove_depth
    length_scale = rail_length / height.to_f
    bottom.transform!(Geom::Transformation.scaling([x, 0, z], length_scale, 1, 1))
    if rail != stile
      delta = rail - stile
      bottom.entities.grep(Sketchup::Face).each do |f|
        next unless f.normal.parallel?(Geom::Vector3d.new(0, 0, -1))
        f.pushpull(delta)
      end
    end
    bb = bottom.bounds
    bottom.transform!(Geom::Transformation.translation([x + stile - groove_depth - bb.min.x, 0, z - bb.min.z]))

    # Right stile by mirroring the left stile across the door width
    right = left.copy
    mirror_right = Geom::Transformation.scaling([x + width / 2, 0, 0], -1, 1, 1)
    right.transform!(mirror_right)

    # Top rail by mirroring the bottom rail around the door's center
    top = bottom.copy
    mirror_top = Geom::Transformation.scaling([0, 0, z + height / 2], 1, 1, -1)
    top.transform!(mirror_top)

    # Panel set in grooves; bevel run only affects the front face width
    panel = group.entities.add_group
    panel_face = panel.entities.add_face(
      [x + stile, groove_front_y, z + rail],
      [x + width - stile, groove_front_y, z + rail],
      [x + width - stile, groove_front_y, z + height - rail],
      [x + stile, groove_front_y, z + height - rail]
    )
    panel_face.pushpull(-groove_width)

    group
  end

  def self.align_to_hole_top(z, base, spacing)
    return z if spacing.to_f.zero?
    base + ((z - base) / spacing).round * spacing
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
        face ||= edges.first.faces.min_by(&:area)
        next unless face
        face.pushpull(-depth_drill)
      end
    end
  end
end

