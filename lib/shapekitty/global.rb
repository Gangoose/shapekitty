# frozen_string_literal: true
include Math
module Shapekitty
  module Global

    TWO_PI = PI*2.0
    TAU = PI*2.0
    HALF_PI = PI/2.0
    QUARTER_PI = PI/4.0
    VERSION = 0 # i'll set this up later

    CORNER = "CORNER"
    CORNERS = "CORNERS"
    CENTER = "CENTER"
    RADIUS = "RADIUS"

    PIE = "PIE"
    CHORD = "CHORD"
    OPEN = "OPEN"
    PIE_OPEN = "PIE_OPEN"
    CHORD_OPEN = "CHORD_OPEN"

    Sketch.public_instance_methods(false).each do |name|
      next if Object.method_defined?(name) || Object.private_method_defined?(name)

      define_method(name) { |*args, **kw, &blk| Shapekitty.default_sketch.public_send(name, *args, **kw, &blk) }
    end

    name
  end
end


# testing
# module Shapekitty
#   module Global
#
#     Sketch.public_instance_methods(false).each do |name|
#       next if Object.method_defined?(name) || Object.private_method_defined?(name) # skip clashes
#       define_method(name) { |*args, **kw, &blk| Shapekit.default_sketch.public_send(name, *args, **kw, &blk) }
#       private name
#     end
#   end
# end
# 