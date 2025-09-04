# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  # Creates a simple frameless cabinet formed from discrete panels.
  #
  # The carcass consists of two sides, a top, a bottom, and a back. Shelves
  # are optional and span the interior of the carcass.
  #
  # @param width [Length] cabinet width
  # @param height [Length] cabinet height
  # @param depth [Length] cabinet depth
  # @param shelf_count [Integer] number of shelves inside the cabinet
  def self.create_frameless_cabinet(width:, height:, depth:, shelf_count: 0)
    model = Sketchup.active_model
    entities = model.entities

    panel_thickness = 19.mm
    back_thickness = 6.mm

    # Sides
    left = entities.add_group
    left.entities.add_face(
      [0, 0, 0],
      [0, depth, 0],
      [0, depth, height],
      [0, 0, height]
    ).pushpull(panel_thickness)

    right = entities.add_group
    right.entities.add_face(
      [width, 0, 0],
      [width, depth, 0],
      [width, depth, height],
      [width, 0, height]
    ).pushpull(-panel_thickness)

    # Bottom
    bottom = entities.add_group
    bottom.entities.add_face(
      [panel_thickness, 0, 0],
      [width - panel_thickness, 0, 0],
      [width - panel_thickness, depth, 0],
      [panel_thickness, depth, 0]
    ).pushpull(-panel_thickness)

    # Top
    top = entities.add_group
    top.entities.add_face(
      [panel_thickness, 0, height - panel_thickness],
      [width - panel_thickness, 0, height - panel_thickness],
      [width - panel_thickness, depth, height - panel_thickness],
      [panel_thickness, depth, height - panel_thickness]
    ).pushpull(panel_thickness)

    # Back
    back = entities.add_group
    back.entities.add_face(
      [0, depth - back_thickness, 0],
      [width, depth - back_thickness, 0],
      [width, depth - back_thickness, height],
      [0, depth - back_thickness, height]
    ).pushpull(back_thickness)

    # Shelves
    return if shelf_count <= 0

    shelf_thickness = panel_thickness
    interior_height = height - panel_thickness * 2
    spacing = interior_height / (shelf_count + 1)
    shelf_depth = depth - back_thickness

    shelf_count.times do |i|
      z = panel_thickness + spacing * (i + 1)
      shelf = entities.add_group
      shelf.entities.add_face(
        [panel_thickness, 0, z],
        [width - panel_thickness, 0, z],
        [width - panel_thickness, shelf_depth, z],
        [panel_thickness, shelf_depth, z]
      ).pushpull(-shelf_thickness)
    end
  end
end

