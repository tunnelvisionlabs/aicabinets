# frozen_string_literal: true

require 'sketchup.rb'
Sketchup.require('aicabinets/ops/units')
Sketchup.require('aicabinets/generator/carcass')

module AICabinets
  UNITS = Ops::Units

  # Builds a base carcass using the new generator namespace. Callers should
  # prefer this API for new work; the legacy helpers in this file remain for
  # backwards compatibility with the example scripts and will be removed once
  # migrated.
  def self.build_base_carcass!(parent:, params_mm:)
    Generator.build_base_carcass!(parent: parent, params_mm: params_mm)
  end

  DEFAULT_PANEL_THICKNESS = UNITS.to_length_mm(19)
  DEFAULT_BACK_THICKNESS = UNITS.to_length_mm(6)
  DEFAULT_HOLE_DIAMETER = UNITS.to_length_mm(5)
  DEFAULT_HOLE_DEPTH = UNITS.to_length_mm(13)
  DEFAULT_HOLE_SPACING = UNITS.to_length_mm(32)
  DEFAULT_DOOR_THICKNESS = UNITS.to_length_mm(19)
  DEFAULT_DOOR_TYPE = :overlay
  DEFAULT_DOOR_STYLE = :slab
  DEFAULT_DOOR_REVEAL = UNITS.to_length_mm(2)
  DEFAULT_DOOR_GAP = UNITS.to_length_mm(2)
  DEFAULT_RAIL_WIDTH = UNITS.to_length_mm(70)
  DEFAULT_STILE_WIDTH = UNITS.to_length_mm(70)
  DEFAULT_BEVEL_ANGLE = 15.degrees
  DEFAULT_PROFILE_DEPTH = UNITS.to_length_mm(6)
  DEFAULT_GROOVE_WIDTH = UNITS.to_length_mm(6)
  DEFAULT_GROOVE_DEPTH = UNITS.to_length_mm(9.5)
  DOOR_BUMPER_GAP = UNITS.to_length_mm(2)

  DEFAULT_CABINET_MATERIAL = 'Birch Plywood'
  DEFAULT_DOOR_MATERIAL = 'MDF'
  DEFAULT_DOOR_FRAME_MATERIAL = 'Maple'

  DEFAULT_TOP_INSET = UNITS.to_length_mm(0)
  DEFAULT_BOTTOM_INSET = UNITS.to_length_mm(0)
  DEFAULT_BACK_INSET = UNITS.to_length_mm(0)

  DEFAULT_TOP_TYPE = :panel
  DEFAULT_TOP_STRINGER_WIDTH = UNITS.to_length_mm(100)

  DEFAULT_DRAWER_SIDE_THICKNESS = UNITS.to_length_mm(16)
  DEFAULT_DRAWER_BOTTOM_THICKNESS = UNITS.to_length_mm(10)
  DEFAULT_DRAWER_JOINERY = :butt
  DEFAULT_DRAWER_SIDE_CLEARANCE = UNITS.to_length_mm(5)
  DEFAULT_DRAWER_ORIGIN = :top
  DEFAULT_DRAWER_BOTTOM_CLEARANCE = UNITS.to_length_mm(16)
  DEFAULT_DRAWER_TOP_CLEARANCE = UNITS.to_length_mm(7)

  def self.material(name)
    return nil unless name
    materials = Sketchup.active_model.materials
    existing = materials[name]
    return existing if existing

    mat = materials.add(name)
    case name
    when 'MDF'
      mat.color = Sketchup::Color.new(164, 143, 122)
    when 'Maple'
      mat.color = Sketchup::Color.new(224, 200, 160)
    when 'Birch Plywood'
      mat.color = Sketchup::Color.new(222, 206, 170)
    end
    mat
  end

  # Specifications for drawer slides including hole locations, required
  # cabinet depth, nominal slide length, and the offset of the first hole
  # of the 32 mm system from the bottom of the box. Each slide type maps to
  # a hash with a :first_hole_from_bottom entry and a :lengths subhash keyed
  # by nominal length in inches.
  SLIDE_HOLE_PATTERNS = {
    salice_progressa_plus_short_us: {
      first_hole_from_bottom: UNITS.to_length_mm(38),
      lengths: {
        # Distances are from the front of the cabinet side panel and reflect
        # Salice's specified hole locations for the short-member Progressa+
        # slides in the US market.
        15 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(261)], # rear hole positions TBD
          min_depth: UNITS.to_length_mm(399),
          slide_length: UNITS.to_length_mm(381)
        },
        18 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(261), UNITS.to_length_mm(325), UNITS.to_length_mm(357)],
          min_depth: UNITS.to_length_mm(474),
          slide_length: UNITS.to_length_mm(457)
        },
        21 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(261), UNITS.to_length_mm(389), UNITS.to_length_mm(430)],
          min_depth: UNITS.to_length_mm(550),
          slide_length: UNITS.to_length_mm(533)
        },
        24 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(261), UNITS.to_length_mm(389), UNITS.to_length_mm(453)],
          min_depth: UNITS.to_length_mm(627),
          slide_length: UNITS.to_length_mm(610)
        },
        27 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(261), UNITS.to_length_mm(389), UNITS.to_length_mm(517)],
          min_depth: UNITS.to_length_mm(703),
          slide_length: UNITS.to_length_mm(686)
        },
        30 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(261), UNITS.to_length_mm(389), UNITS.to_length_mm(517)],
          min_depth: UNITS.to_length_mm(779),
          slide_length: UNITS.to_length_mm(762)
        }
      }
    },
    salice_progressa_plus_standard_us: {
      first_hole_from_bottom: UNITS.to_length_mm(38),
      lengths: {
        # Distances for the face-frame cabinet member Progressa+ slides
        # available in the US market.
        9 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(133), UNITS.to_length_mm(197), UNITS.to_length_mm(229)],
          min_depth: UNITS.to_length_mm(270),
          slide_length: UNITS.to_length_mm(229)
        },
        12 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(165), UNITS.to_length_mm(261), UNITS.to_length_mm(293)],
          min_depth: UNITS.to_length_mm(323),
          slide_length: UNITS.to_length_mm(305)
        },
        15 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(165), UNITS.to_length_mm(261), UNITS.to_length_mm(357)],
          min_depth: UNITS.to_length_mm(399),
          slide_length: UNITS.to_length_mm(381)
        },
        18 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(261), UNITS.to_length_mm(357), UNITS.to_length_mm(389), UNITS.to_length_mm(453)],
          min_depth: UNITS.to_length_mm(475),
          slide_length: UNITS.to_length_mm(457)
        },
        21 => {
          holes: [UNITS.to_length_mm(37), UNITS.to_length_mm(261), UNITS.to_length_mm(357), UNITS.to_length_mm(389), UNITS.to_length_mm(517)],
          min_depth: UNITS.to_length_mm(551),
          slide_length: UNITS.to_length_mm(533)
        }
      }
    }
  }.freeze

  def self.select_slide_depth(kind, interior_depth, material_thickness)
    spec = SLIDE_HOLE_PATTERNS[kind]
    return unless spec
    offset = material_thickness >= UNITS.to_length_mm(17) ? UNITS.to_length_mm(3) : UNITS.to_length_mm(0)
    spec[:lengths].values
        .select { |data| data[:min_depth] + offset <= interior_depth }
        .max_by { |data| data[:slide_length].to_f }
        &.fetch(:slide_length)
  end

  def self.has_front?(section)
    section[:doors] || section[:drawers]&.any? ||
      section[:partitions]&.any? { |p| has_front?(p) }
  end

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
  #   height: 720 mm,
  #   depth: 350 mm,
  #   panel_thickness: 19 mm,
  #   back_thickness: 6 mm,
  #   shelf_count: 0,
  #   hole_diameter: 5 mm,
  #   hole_depth: 13 mm,
  #   hole_spacing: 32 mm,
  #   cabinets: [
  #     {
  #       width: 600 mm,
  #       shelf_count: 2,
  #       hole_columns: [
  #         { distance: 37 mm, first_hole: 10 mm, skip: 2, count: 5 }
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
      door_gap: DEFAULT_DOOR_GAP,
      top_reveal: nil,
      bottom_reveal: nil,
      rail_width: DEFAULT_RAIL_WIDTH,
      stile_width: DEFAULT_STILE_WIDTH,
      bevel_angle: DEFAULT_BEVEL_ANGLE,
      profile_depth: DEFAULT_PROFILE_DEPTH,
      groove_width: DEFAULT_GROOVE_WIDTH,
      groove_depth: DEFAULT_GROOVE_DEPTH,
      top_inset: DEFAULT_TOP_INSET,
      bottom_inset: DEFAULT_BOTTOM_INSET,
      back_inset: DEFAULT_BACK_INSET,
      top_type: DEFAULT_TOP_TYPE,
      top_stringer_width: DEFAULT_TOP_STRINGER_WIDTH,
      drawer_side_thickness: DEFAULT_DRAWER_SIDE_THICKNESS,
      drawer_bottom_thickness: DEFAULT_DRAWER_BOTTOM_THICKNESS,
      drawer_joinery: DEFAULT_DRAWER_JOINERY,
      drawer_depth: nil,
      drawer_slide: nil,
      drawer_side_clearance: DEFAULT_DRAWER_SIDE_CLEARANCE,
      drawer_bottom_clearance: DEFAULT_DRAWER_BOTTOM_CLEARANCE,
      drawer_top_clearance: DEFAULT_DRAWER_TOP_CLEARANCE,
      drawer_origin: DEFAULT_DRAWER_ORIGIN,
      drawers: [],
      partitions: [],
      cabinet_material: DEFAULT_CABINET_MATERIAL,
      door_material: DEFAULT_DOOR_MATERIAL,
      door_frame_material: DEFAULT_DOOR_FRAME_MATERIAL,
      door_panel_material: DEFAULT_DOOR_MATERIAL
    }.merge(config)

    height = defaults[:height]
    depth = defaults[:depth]

    cabinets = (config[:cabinets] || []).map do |cab|
      defaults.merge(cab).tap do |c|
        c[:drawers] ||= []
        c[:partitions] ||= []
      end
    end

    cabinets.each do |cab|
      cab[:left_reveal] ||= cab[:door_reveal]
      cab[:right_reveal] ||= cab[:door_reveal]
      cab[:top_reveal] ||= cab[:door_reveal]
      cab[:bottom_reveal] ||= cab[:door_reveal]
    end

    cabinets.each_cons(2) do |left, right|
      next unless has_front?(left) && has_front?(right)

      left[:right_reveal] = left[:door_gap] / 2
      right[:left_reveal] = right[:door_gap] / 2
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
        door_gap: cab_opts[:door_gap],
        rail_width: cab_opts[:rail_width],
        stile_width: cab_opts[:stile_width],
        bevel_angle: cab_opts[:bevel_angle],
        profile_depth: cab_opts[:profile_depth],
        groove_width: cab_opts[:groove_width],
        groove_depth: cab_opts[:groove_depth],
        top_inset: cab_opts[:top_inset],
        bottom_inset: cab_opts[:bottom_inset],
        back_inset: cab_opts[:back_inset],
        top_type: cab_opts[:top_type],
        top_stringer_width: cab_opts[:top_stringer_width],
        left_door_reveal: cab_opts[:left_reveal],
        right_door_reveal: cab_opts[:right_reveal],
        top_door_reveal: cab_opts[:top_reveal],
        bottom_door_reveal: cab_opts[:bottom_reveal],
        drawer_side_thickness: cab_opts[:drawer_side_thickness],
        drawer_bottom_thickness: cab_opts[:drawer_bottom_thickness],
        drawer_joinery: cab_opts[:drawer_joinery],
        drawer_depth: cab_opts[:drawer_depth],
        drawer_slide: cab_opts[:drawer_slide],
        drawer_side_clearance: cab_opts[:drawer_side_clearance],
        drawer_bottom_clearance: cab_opts[:drawer_bottom_clearance],
        drawer_top_clearance: cab_opts[:drawer_top_clearance],
        drawer_origin: cab_opts[:drawer_origin],
        drawers: cab_opts[:drawers] || [],
        partitions: cab_opts[:partitions] || [],
        doors: cab_opts[:doors],
        cabinet_material: cab_opts[:cabinet_material],
        door_material: cab_opts[:door_material],
        door_frame_material: cab_opts[:door_frame_material],
        door_panel_material: cab_opts[:door_panel_material]
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
  # @param partitions [Array<Hash>] optional interior sections
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
    door_gap: door_reveal,
    rail_width:,
    stile_width:,
    bevel_angle:,
    profile_depth:,
    groove_width:,
    groove_depth:,
    top_inset: DEFAULT_TOP_INSET,
    bottom_inset: DEFAULT_BOTTOM_INSET,
    back_inset: DEFAULT_BACK_INSET,
    left_door_reveal: door_reveal,
    right_door_reveal: door_reveal,
    top_door_reveal: door_reveal,
    bottom_door_reveal: door_reveal,
    top_type: DEFAULT_TOP_TYPE,
    top_stringer_width: DEFAULT_TOP_STRINGER_WIDTH,
    drawer_side_thickness: DEFAULT_DRAWER_SIDE_THICKNESS,
    drawer_bottom_thickness: DEFAULT_DRAWER_BOTTOM_THICKNESS,
    drawer_joinery: DEFAULT_DRAWER_JOINERY,
    drawer_depth: nil,
    drawer_slide: nil,
    drawer_side_clearance: DEFAULT_DRAWER_SIDE_CLEARANCE,
    drawer_bottom_clearance: DEFAULT_DRAWER_BOTTOM_CLEARANCE,
    drawer_top_clearance: DEFAULT_DRAWER_TOP_CLEARANCE,
    drawer_origin: DEFAULT_DRAWER_ORIGIN,
    drawers: [],
    partitions: [],
    doors: nil,
    cabinet_material: DEFAULT_CABINET_MATERIAL,
    door_material: DEFAULT_DOOR_MATERIAL,
    door_frame_material: DEFAULT_DOOR_FRAME_MATERIAL,
    door_panel_material: DEFAULT_DOOR_MATERIAL
  )
    cabinet = entities.add_group
    g = cabinet.entities

    cab_mat = material(cabinet_material)

    back_front_y = depth - back_inset - back_thickness
    back_front_y = 0 if back_front_y.to_f.negative?

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
      depth: depth - back_inset,
      panel_thickness: panel_thickness + bottom_inset,
      back_thickness: back_thickness,
      hole_diameter: hole_diameter,
      hole_depth: hole_depth,
      hole_spacing: hole_spacing,
      columns: hole_columns,
      from_right: false
    )
    left_comp = left.to_component
    left_comp.material = cab_mat

    drill_hole_columns(
      right.entities,
      x: x_offset + width - panel_thickness,
      depth: depth - back_inset,
      panel_thickness: panel_thickness + bottom_inset,
      back_thickness: back_thickness,
      hole_diameter: hole_diameter,
      hole_depth: hole_depth,
      hole_spacing: hole_spacing,
      columns: hole_columns,
      from_right: true
    )
    right_comp = right.to_component
    right_comp.material = cab_mat

    # Bottom
    bottom = g.add_group
    bottom.entities.add_face(
      [x_offset + panel_thickness, 0, bottom_inset + panel_thickness],
      [x_offset + width - panel_thickness, 0, bottom_inset + panel_thickness],
      [x_offset + width - panel_thickness, back_front_y, bottom_inset + panel_thickness],
      [x_offset + panel_thickness, back_front_y, bottom_inset + panel_thickness]
    ).pushpull(-panel_thickness)
    bottom_comp = bottom.to_component
    bottom_comp.material = cab_mat

    # Top
    if top_type == :stringers
      front = g.add_group
      front.entities.add_face(
        [x_offset + panel_thickness, 0, height - top_inset - panel_thickness],
        [x_offset + width - panel_thickness, 0, height - top_inset - panel_thickness],
        [x_offset + width - panel_thickness, top_stringer_width, height - top_inset - panel_thickness],
        [x_offset + panel_thickness, top_stringer_width, height - top_inset - panel_thickness]
      ).pushpull(panel_thickness)
      front_comp = front.to_component
      front_comp.material = cab_mat

      back_stringer_front = back_front_y - top_stringer_width
      back_stringer_front = 0 if back_stringer_front.to_f.negative?

      back_stringer = g.add_group
      back_stringer.entities.add_face(
        [x_offset + panel_thickness, back_stringer_front, height - top_inset - panel_thickness],
        [x_offset + width - panel_thickness, back_stringer_front, height - top_inset - panel_thickness],
        [x_offset + width - panel_thickness, back_front_y, height - top_inset - panel_thickness],
        [x_offset + panel_thickness, back_front_y, height - top_inset - panel_thickness]
      ).pushpull(panel_thickness)
      back_stringer_comp = back_stringer.to_component
      back_stringer_comp.material = cab_mat
    else
      top = g.add_group
      top.entities.add_face(
        [x_offset + panel_thickness, 0, height - top_inset - panel_thickness],
        [x_offset + width - panel_thickness, 0, height - top_inset - panel_thickness],
        [x_offset + width - panel_thickness, back_front_y, height - top_inset - panel_thickness],
        [x_offset + panel_thickness, back_front_y, height - top_inset - panel_thickness]
      ).pushpull(panel_thickness)
      top_comp = top.to_component
      top_comp.material = cab_mat
    end

    # Back inset between the sides and flush with the top of the bottom panel
    # and the underside of the top panel
    back = g.add_group
    back.entities.add_face(
      [x_offset + panel_thickness, depth - back_inset, bottom_inset + panel_thickness],
      [x_offset + width - panel_thickness, depth - back_inset, bottom_inset + panel_thickness],
      [x_offset + width - panel_thickness, depth - back_inset, height - top_inset - panel_thickness],
      [x_offset + panel_thickness, depth - back_inset, height - top_inset - panel_thickness]
    ).pushpull(back_thickness)
    back_comp = back.to_component
    back_comp.material = cab_mat

    # Shelves
    if shelf_count > 0
      shelf_thickness = panel_thickness
      interior_height = height - top_inset - bottom_inset - (panel_thickness * 2)
      shelf_depth = depth - back_inset - back_thickness

      positions = if shelf_count > 0 && hole_columns.any?
                    col = hole_columns.first
                    spacing_holes = col[:spacing] || hole_spacing
                    first = col[:first_hole] || 0
                    skip = col[:skip].to_i
                    diameter = col[:diameter] || hole_diameter
                    base = bottom_inset + panel_thickness + first + (spacing_holes * skip) + (diameter / 2)
                    spacing_even = interior_height / (shelf_count + 1)

                    Array.new(shelf_count) do |i|
                      desired_top = bottom_inset + panel_thickness + (spacing_even * (i + 1))
                      desired_bottom = desired_top - shelf_thickness
                      hole_top = align_to_hole_top(desired_bottom, base, spacing_holes)
                      hole_top + shelf_thickness
                    end
                  else
                    spacing_even = interior_height / (shelf_count + 1)
                    Array.new(shelf_count) { |i| bottom_inset + panel_thickness + (spacing_even * (i + 1)) }
                  end

      positions.each do |z|
        shelf = g.add_group
        shelf.entities.add_face(
          [x_offset + panel_thickness, 0, z],
          [x_offset + width - panel_thickness, 0, z],
          [x_offset + width - panel_thickness, shelf_depth, z],
          [x_offset + panel_thickness, shelf_depth, z]
        ).pushpull(-shelf_thickness)
        shelf_comp = shelf.to_component
        shelf_comp.material = cab_mat
      end
    end

    add_fronts(
      g,
      x_offset: x_offset,
      width: width,
      height: height,
      depth: depth,
      panel_thickness: panel_thickness,
      back_thickness: back_thickness,
      top_inset: top_inset,
      bottom_inset: bottom_inset,
      back_inset: back_inset,
      door_thickness: door_thickness,
      door_type: door_type,
      door_style: door_style,
      door_gap: door_gap,
      left_door_reveal: left_door_reveal,
      right_door_reveal: right_door_reveal,
      top_door_reveal: top_door_reveal,
      bottom_door_reveal: bottom_door_reveal,
      rail_width: rail_width,
      stile_width: stile_width,
      bevel_angle: bevel_angle,
      profile_depth: profile_depth,
      groove_width: groove_width,
      groove_depth: groove_depth,
      drawer_side_thickness: drawer_side_thickness,
      drawer_bottom_thickness: drawer_bottom_thickness,
      drawer_joinery: drawer_joinery,
      drawer_depth: drawer_depth,
      drawer_slide: drawer_slide,
      drawer_side_clearance: drawer_side_clearance,
      drawer_bottom_clearance: drawer_bottom_clearance,
      drawer_top_clearance: drawer_top_clearance,
      drawer_origin: drawer_origin,
      hole_spacing: hole_spacing,
      z_offset: 0,
      drawers: drawers,
      doors: doors,
      partitions: partitions,
      start: :left,
      cabinet_material: cabinet_material,
      door_material: door_material,
      door_frame_material: door_frame_material,
      door_panel_material: door_panel_material
    )
  end

  def self.add_doors(
    entities,
    x_offset:,
    width:,
    height:,
    z_offset: 0,
    door_thickness:,
    top_reveal:,
    bottom_reveal:,
    door_gap: top_reveal,
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
    orientation:,
    door_material: DEFAULT_DOOR_MATERIAL,
    door_frame_material: DEFAULT_DOOR_FRAME_MATERIAL,
    door_panel_material: DEFAULT_DOOR_MATERIAL
  )
    return unless orientation
    return unless type == :overlay

    door_height = height - top_reveal - bottom_reveal
    z = z_offset + bottom_reveal
    gap = DOOR_BUMPER_GAP
    if orientation == :double
      door_width = (width - left_reveal - right_reveal - door_gap) / 2
      x_start = x_offset + left_reveal
      2.times do |i|
        create_door_panel(
          entities,
          x_start + (i * (door_width + door_gap)),
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
          groove_depth: groove_depth,
          material: door_material,
          frame_material: door_frame_material,
          panel_material: door_panel_material
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
        groove_depth: groove_depth,
        material: door_material,
        frame_material: door_frame_material,
        panel_material: door_panel_material
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
    groove_depth: DEFAULT_GROOVE_DEPTH,
    material: DEFAULT_DOOR_MATERIAL,
    frame_material: DEFAULT_DOOR_FRAME_MATERIAL,
    panel_material: DEFAULT_DOOR_MATERIAL
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
       comp = group.to_component
       comp.material = self.material(material)
       return comp
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
    rail_length = width - (2 * stile) + (2 * groove_depth)
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
    mirror_right = Geom::Transformation.scaling([x + (width / 2), 0, 0], -1, 1, 1)
    right.transform!(mirror_right)

    # Top rail by mirroring the bottom rail around the door's center
    top = bottom.copy
    mirror_top = Geom::Transformation.scaling([0, 0, z + (height / 2)], 1, 1, -1)
    top.transform!(mirror_top)

    # Trim rails where they intersect stiles
    [left, right].each do |stile|
      bottom = stile.trim(bottom) || bottom
      top = stile.trim(top) || top
    end

    # Panel set in grooves; bevel run only affects the front face width
    panel = group.entities.add_group
    panel_face = panel.entities.add_face(
      [x + stile - groove_depth, groove_front_y, z + rail - groove_depth],
      [x + width - stile + groove_depth, groove_front_y, z + rail - groove_depth],
      [x + width - stile + groove_depth, groove_front_y, z + height - rail + groove_depth],
      [x + stile - groove_depth, groove_front_y, z + height - rail + groove_depth]
    )
    panel_face.pushpull(-groove_width)

    frame_comp_material = self.material(frame_material)
    [left, right, bottom, top].each do |frm|
      comp = frm.to_component
      comp.material = frame_comp_material
    end
    panel_comp = panel.to_component
    panel_comp.material = self.material(panel_material)
    group.to_component
  end

  def self.create_drawer_box(
    entities,
    x:,
    y:,
    z:,
    width:,
    depth:,
    height:,
    side_thickness: DEFAULT_DRAWER_SIDE_THICKNESS,
    bottom_thickness: DEFAULT_DRAWER_BOTTOM_THICKNESS,
    joinery: DEFAULT_DRAWER_JOINERY
  )
    group = entities.add_group

    unless joinery == :butt
      warn("AI Cabinets: Drawer joinery #{joinery.inspect} is not implemented; using default box geometry.")
    end

    # Left side
    left = group.entities.add_group
    left.entities.add_face(
      [x, y, z],
      [x, y + depth, z],
      [x, y + depth, z + height],
      [x, y, z + height]
    ).pushpull(side_thickness)
    left.to_component

    # Right side
    right = group.entities.add_group
    right.entities.add_face(
      [x + width - side_thickness, y, z],
      [x + width - side_thickness, y + depth, z],
      [x + width - side_thickness, y + depth, z + height],
      [x + width - side_thickness, y, z + height]
    ).pushpull(side_thickness)
    right.to_component

    # Back
    back = group.entities.add_group
    back.entities.add_face(
      [x + side_thickness, y + depth - side_thickness, z],
      [x + width - side_thickness, y + depth - side_thickness, z],
      [x + width - side_thickness, y + depth - side_thickness, z + height],
      [x + side_thickness, y + depth - side_thickness, z + height]
    ).pushpull(-side_thickness)
    back.to_component

    # Front
    front = group.entities.add_group
    front.entities.add_face(
      [x + side_thickness, y, z],
      [x + width - side_thickness, y, z],
      [x + width - side_thickness, y, z + height],
      [x + side_thickness, y, z + height]
    ).pushpull(-side_thickness)
    front.to_component

    # Bottom
    bottom = group.entities.add_group
    bottom.entities.add_face(
      [x + side_thickness, y, z],
      [x + width - side_thickness, y, z],
      [x + width - side_thickness, y + depth - side_thickness, z],
      [x + side_thickness, y + depth - side_thickness, z]
    ).pushpull(bottom_thickness)
    bottom.to_component

    group.to_component
  end

  def self.add_fronts(
    entities,
    x_offset:,
    width:,
    height:,
    depth:,
    panel_thickness:,
    back_thickness:,
    top_inset:,
    bottom_inset:,
    back_inset:,
    door_thickness:,
    door_type:,
    door_style:,
    door_gap:,
    left_door_reveal:,
    right_door_reveal:,
    top_door_reveal:,
    bottom_door_reveal:,
    rail_width:,
    stile_width:,
    bevel_angle:,
    profile_depth:,
    groove_width:,
    groove_depth:,
    drawer_side_thickness:,
    drawer_bottom_thickness:,
    drawer_joinery:,
    drawer_depth:,
    drawer_slide:,
    drawer_side_clearance:,
    drawer_bottom_clearance:,
    drawer_top_clearance:,
    drawer_origin:,
    hole_spacing:,
    z_offset: 0,
    start: :left,
    drawers: [],
    doors: nil,
    partitions: [],
    cabinet_material: DEFAULT_CABINET_MATERIAL,
    door_material: DEFAULT_DOOR_MATERIAL,
    door_frame_material: DEFAULT_DOOR_FRAME_MATERIAL,
    door_panel_material: DEFAULT_DOOR_MATERIAL
  )
    cab_mat = material(cabinet_material)

    if partitions.any?
      partition_depth = depth - back_inset - back_thickness
      if start == :left
        interior_width = width - (2 * panel_thickness)
        specified = partitions.sum { |p| p[:width] || 0 }
        unspecified = partitions.count { |p| p[:width].nil? }
        remaining = interior_width - specified - ((partitions.length - 1) * panel_thickness)
        default_width = unspecified.zero? ? 0 : remaining / unspecified.to_f
        x_current = x_offset + panel_thickness
        parts = partitions.map.with_index do |part, idx|
          opts = {
            door_thickness: door_thickness,
            door_type: door_type,
            door_style: door_style,
            door_reveal: door_gap,
            door_gap: door_gap,
            rail_width: rail_width,
            stile_width: stile_width,
            bevel_angle: bevel_angle,
            profile_depth: profile_depth,
            groove_width: groove_width,
            groove_depth: groove_depth,
            drawer_side_thickness: drawer_side_thickness,
            drawer_bottom_thickness: drawer_bottom_thickness,
            drawer_joinery: drawer_joinery,
            drawer_depth: drawer_depth,
            drawer_slide: drawer_slide,
            drawer_side_clearance: drawer_side_clearance,
            drawer_bottom_clearance: drawer_bottom_clearance,
            drawer_top_clearance: drawer_top_clearance,
            drawer_origin: drawer_origin,
            drawers: [],
            partitions: []
          }.merge(part)
          opts[:start] = part.key?(:start) ? part[:start] : :top
          w = opts[:width] || default_width
          outer_x = x_current - panel_thickness
          outer_width = w + (2 * panel_thickness)
          opts[:width] = outer_width
          opts[:x] = outer_x
          opts[:z] = z_offset
          opts[:left_reveal] = idx.zero? ? left_door_reveal : opts[:door_reveal]
          opts[:right_reveal] = idx == partitions.length - 1 ? right_door_reveal : opts[:door_reveal]
          opts[:top_reveal] ||= part.key?(:door_reveal) ? opts[:door_reveal] : top_door_reveal
          opts[:bottom_reveal] ||= part.key?(:door_reveal) ? opts[:door_reveal] : bottom_door_reveal
          x_current += w
          if idx < partitions.length - 1
            divider = entities.add_group
            divider.entities.add_face(
              [x_current, 0, z_offset + bottom_inset + panel_thickness],
              [x_current, partition_depth, z_offset + bottom_inset + panel_thickness],
              [x_current, partition_depth, z_offset + height - top_inset - panel_thickness],
              [x_current, 0, z_offset + height - top_inset - panel_thickness]
            ).pushpull(panel_thickness)
            divider_comp = divider.to_component
            divider_comp.material = cab_mat
            x_current += panel_thickness
          end
          opts
        end

        parts.each_cons(2) do |left_part, right_part|
          next unless has_front?(left_part) && has_front?(right_part)
          left_part[:right_reveal] = (panel_thickness / 2) + (left_part[:door_gap] / 2)
          right_part[:left_reveal] = (panel_thickness / 2) + (right_part[:door_gap] / 2)
        end
      else
        interior_height = height - top_inset - bottom_inset - (2 * panel_thickness)
        specified = partitions.sum { |p| p[:height] || 0 }
        unspecified = partitions.count { |p| p[:height].nil? }
        remaining = interior_height - specified - ((partitions.length - 1) * panel_thickness)
        default_height = unspecified.zero? ? 0 : remaining / unspecified.to_f
        z_current = start == :top ? height - top_inset - panel_thickness : bottom_inset + panel_thickness
        parts = partitions.map.with_index do |part, idx|
          opts = {
            door_thickness: door_thickness,
            door_type: door_type,
            door_style: door_style,
            door_reveal: door_gap,
            door_gap: door_gap,
            rail_width: rail_width,
            stile_width: stile_width,
            bevel_angle: bevel_angle,
            profile_depth: profile_depth,
            groove_width: groove_width,
            groove_depth: groove_depth,
            drawer_side_thickness: drawer_side_thickness,
            drawer_bottom_thickness: drawer_bottom_thickness,
            drawer_joinery: drawer_joinery,
            drawer_depth: drawer_depth,
            drawer_slide: drawer_slide,
            drawer_side_clearance: drawer_side_clearance,
            drawer_bottom_clearance: drawer_bottom_clearance,
            drawer_top_clearance: drawer_top_clearance,
            drawer_origin: drawer_origin,
            drawers: [],
            partitions: []
          }.merge(part)
          opts[:start] = part.key?(:start) ? part[:start] : :left
          h = opts[:height] || default_height
          if start == :top
            outer_bottom = z_current - h - panel_thickness
            opts[:z] = z_offset + outer_bottom
            z_current -= h
            if idx < partitions.length - 1
              divider = entities.add_group
              divider.entities.add_face(
                [x_offset + panel_thickness, 0, z_offset + z_current],
                [x_offset + width - panel_thickness, 0, z_offset + z_current],
                [x_offset + width - panel_thickness, partition_depth, z_offset + z_current],
                [x_offset + panel_thickness, partition_depth, z_offset + z_current]
              ).pushpull(-panel_thickness)
              divider_comp = divider.to_component
              divider_comp.material = cab_mat
              z_current -= panel_thickness
            end
          else
            outer_bottom = z_current - panel_thickness
            opts[:z] = z_offset + outer_bottom
            z_current += h
            if idx < partitions.length - 1
              divider = entities.add_group
              divider.entities.add_face(
                [x_offset + panel_thickness, 0, z_offset + z_current],
                [x_offset + width - panel_thickness, 0, z_offset + z_current],
                [x_offset + width - panel_thickness, partition_depth, z_offset + z_current],
                [x_offset + panel_thickness, partition_depth, z_offset + z_current]
              ).pushpull(panel_thickness)
              divider_comp = divider.to_component
              divider_comp.material = cab_mat
              z_current += panel_thickness
            end
          end
          opts[:height] = h + (2 * panel_thickness)
          opts[:left_reveal] ||= part.key?(:door_reveal) ? opts[:door_reveal] : left_door_reveal
          opts[:right_reveal] ||= part.key?(:door_reveal) ? opts[:door_reveal] : right_door_reveal
          if start == :top
            opts[:top_reveal] = idx.zero? ? top_door_reveal : opts[:door_reveal]
            opts[:bottom_reveal] = idx == partitions.length - 1 ? bottom_door_reveal : opts[:door_reveal]
          else
            opts[:bottom_reveal] = idx.zero? ? bottom_door_reveal : opts[:door_reveal]
            opts[:top_reveal] = idx == partitions.length - 1 ? top_door_reveal : opts[:door_reveal]
          end
          opts
        end

        parts.each_cons(2) do |upper, lower|
          next unless has_front?(upper) && has_front?(lower)
          upper[:bottom_reveal] = (panel_thickness / 2) + (upper[:door_gap] / 2)
          lower[:top_reveal] = (panel_thickness / 2) + (lower[:door_gap] / 2)
        end
      end

      parts.each do |part|
        add_fronts(
          entities,
          x_offset: start == :left ? part[:x] : x_offset,
          width: start == :left ? part[:width] : width,
          height: start == :left ? height : part[:height],
          depth: depth,
          panel_thickness: panel_thickness,
          back_thickness: back_thickness,
          top_inset: top_inset,
          bottom_inset: bottom_inset,
          back_inset: back_inset,
          door_thickness: part[:door_thickness],
          door_type: part[:door_type],
          door_style: part[:door_style],
          door_gap: part[:door_gap],
          left_door_reveal: part[:left_reveal],
          right_door_reveal: part[:right_reveal],
          top_door_reveal: part[:top_reveal],
          bottom_door_reveal: part[:bottom_reveal],
          rail_width: part[:rail_width],
          stile_width: part[:stile_width],
          bevel_angle: part[:bevel_angle],
          profile_depth: part[:profile_depth],
          groove_width: part[:groove_width],
          groove_depth: part[:groove_depth],
          drawer_side_thickness: part[:drawer_side_thickness],
          drawer_bottom_thickness: part[:drawer_bottom_thickness],
          drawer_joinery: part[:drawer_joinery],
          drawer_depth: part[:drawer_depth],
          drawer_slide: part[:drawer_slide],
          drawer_side_clearance: part[:drawer_side_clearance],
          drawer_bottom_clearance: part[:drawer_bottom_clearance],
          drawer_top_clearance: part[:drawer_top_clearance],
          drawer_origin: part[:drawer_origin],
          hole_spacing: hole_spacing,
          z_offset: part[:z],
          start: part[:start],
          drawers: part[:drawers] || [],
          doors: part[:doors],
          partitions: part[:partitions] || [],
          cabinet_material: cabinet_material,
          door_material: door_material,
          door_frame_material: door_frame_material,
          door_panel_material: door_panel_material
        )
      end
      return
    end

    total_drawer_height = 0
    door_height_param = height
    door_z_offset = 0
    door_orientation = doors
    interior_height = height - top_inset - bottom_inset - (panel_thickness * 2)
    if drawers.any?
      drawer_count = drawers.length
      drawers.each do |d|
        d[:height] ||= d[:pitch] && (d[:pitch] * hole_spacing)
      end
      reveal_between_drawers = [drawer_count - 1, 0].max * door_gap
      gap_between_doors = doors ? door_gap : 0
      has_doors = false
      heights = []
      loop do
        available_for_drawers = interior_height - reveal_between_drawers - gap_between_doors
        specified = drawers.sum { |d| d[:height] || 0 }
        unspecified = drawers.count { |d| d[:height].nil? }
        remaining = [available_for_drawers - specified, 0].max
        default_height = unspecified.zero? ? 0 : remaining / unspecified.to_f
        heights = drawers.map { |d| d[:height] || default_height }
        total_drawer_height = heights.sum
        remaining_for_doors = interior_height - total_drawer_height - reveal_between_drawers - gap_between_doors
        has_doors = doors && remaining_for_doors > 0
        break if has_doors || gap_between_doors.zero?
        gap_between_doors = 0
      end
      gap_after_last = has_doors ? door_gap : 0
      interior_depth = depth - back_inset - back_thickness
      drawer_depth_default =
        if drawer_depth
          drawer_depth
        elsif drawer_slide
          select_slide_depth(drawer_slide, interior_depth, drawer_side_thickness) || interior_depth
        else
          interior_depth
        end
      slide_spec = drawer_slide && SLIDE_HOLE_PATTERNS[drawer_slide]
      extra_bottom_from_slide = if slide_spec && slide_spec[:first_hole_from_bottom]
                                  slide_spec[:first_hole_from_bottom] - hole_spacing
                                else
                                  UNITS.to_length_mm(0)
                                end
      interior_width = width - (2 * panel_thickness) - (2 * drawer_side_clearance)
      x_start = x_offset + panel_thickness + drawer_side_clearance
      y_start = 0
      if drawer_origin == :top
        current_top = height - top_inset - panel_thickness
        drawers.each_with_index do |drawer, i|
          h = heights[i]
          bottom = current_top - h
          ddepth = drawer[:depth] || drawer_depth_default
          extra_top = door_type == :overlay && i.zero? ? panel_thickness : 0
          extra_bottom = door_type == :overlay && !has_doors && i == drawers.length - 1 ? panel_thickness : 0
          offset = (i == drawers.length - 1 ? extra_bottom_from_slide : 0)
          box_bottom = bottom + drawer_bottom_clearance + offset
          box_height = h - drawer_bottom_clearance - drawer_top_clearance - offset
          create_drawer_box(
            entities,
            x: x_start,
            y: y_start,
            z: box_bottom + z_offset,
            width: interior_width,
            depth: ddepth,
            height: box_height,
            side_thickness: drawer_side_thickness,
            bottom_thickness: drawer_bottom_thickness,
            joinery: drawer_joinery
          )
          front_height = h + extra_top + extra_bottom
          front_bottom = bottom - top_door_reveal - extra_bottom
          create_door_panel(
            entities,
            x_offset + left_door_reveal,
            width - left_door_reveal - right_door_reveal,
            front_height,
            front_bottom + z_offset,
            door_thickness,
            DOOR_BUMPER_GAP,
            style: door_style,
            rail_width: rail_width,
            stile_width: stile_width,
            bevel_angle: bevel_angle,
            profile_depth: profile_depth,
            groove_width: groove_width,
            groove_depth: groove_depth,
            material: door_material,
            frame_material: door_frame_material,
            panel_material: door_panel_material
          )
          current_top = bottom - (i == drawers.length - 1 ? gap_after_last : door_gap)
        end
        door_start_z = current_top
      else
        current_bottom = bottom_inset + panel_thickness
        drawers.each_with_index do |drawer, i|
          h = heights[i]
          bottom = current_bottom
          ddepth = drawer[:depth] || drawer_depth_default
          extra_bottom = door_type == :overlay && i.zero? ? panel_thickness : 0
          extra_top = door_type == :overlay && !has_doors && i == drawers.length - 1 ? panel_thickness : 0
          offset = (i.zero? ? extra_bottom_from_slide : 0)
          box_bottom = bottom + drawer_bottom_clearance + offset
          box_height = h - drawer_bottom_clearance - drawer_top_clearance - offset
          create_drawer_box(
            entities,
            x: x_start,
            y: y_start,
            z: box_bottom + z_offset,
            width: interior_width,
            depth: ddepth,
            height: box_height,
            side_thickness: drawer_side_thickness,
            bottom_thickness: drawer_bottom_thickness,
            joinery: drawer_joinery
          )
          front_height = h + extra_top + extra_bottom
          front_bottom = bottom + bottom_door_reveal - extra_bottom
          create_door_panel(
            entities,
            x_offset + left_door_reveal,
            width - left_door_reveal - right_door_reveal,
            front_height,
            front_bottom + z_offset,
            door_thickness,
            DOOR_BUMPER_GAP,
            style: door_style,
            rail_width: rail_width,
            stile_width: stile_width,
            bevel_angle: bevel_angle,
            profile_depth: profile_depth,
            groove_width: groove_width,
            groove_depth: groove_depth,
            material: door_material,
            frame_material: door_frame_material,
            panel_material: door_panel_material
          )
          current_bottom += h + (i == drawers.length - 1 ? gap_after_last : door_gap)
        end
        door_start_z = current_bottom
      end
      if has_doors
        door_height_param = drawer_origin == :top ? door_start_z : height - door_start_z
        door_z_offset = drawer_origin == :top ? 0 : door_start_z
      else
        door_orientation = nil
      end
    end

    add_doors(
      entities,
      x_offset: x_offset,
      width: width,
      height: door_height_param,
      z_offset: z_offset + door_z_offset,
      door_thickness: door_thickness,
      top_reveal: top_door_reveal,
      bottom_reveal: bottom_door_reveal,
      door_gap: door_gap,
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
      orientation: door_orientation,
      door_material: door_material,
      door_frame_material: door_frame_material,
      door_panel_material: door_panel_material
    )
  end

  def self.align_to_hole_top(z, base, spacing)
    return z if spacing.to_f.zero?
    base + (((z - base) / spacing).round * spacing)
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
      z_start = panel_thickness + first + (spacing * skip)
      count = col[:count].to_i

      count.times do |i|
        z = z_start + (spacing * i)
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

