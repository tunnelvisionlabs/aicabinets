# frozen_string_literal: true

require 'sketchup.rb'

module AICabinets
  # Creates a simple frameless cabinet.
  #
  # @param width [Length] cabinet width
  # @param height [Length] cabinet height
  # @param depth [Length] cabinet depth
  # @param shelf_count [Integer] number of shelves inside the cabinet
  def self.create_frameless_cabinet(width:, height:, depth:, shelf_count: 0)
    model = Sketchup.active_model
    entities = model.entities

    # Base box
    base = entities.add_face(
      [0, 0, 0],
      [width, 0, 0],
      [width, depth, 0],
      [0, depth, 0]
    )
    base.pushpull(height)

    # Shelves
    return if shelf_count <= 0

    shelf_thickness = 19.mm
    spacing = (height - shelf_thickness) / (shelf_count + 1)

    shelf_count.times do |i|
      z = spacing * (i + 1)
      shelf = entities.add_face(
        [0, 0, z],
        [width, 0, z],
        [width, depth, z],
        [0, depth, z]
      )
      shelf.pushpull(-shelf_thickness)
    end
  end
end

