# frozen_string_literal: true

module Shapekitty
  module Global
    include Math

    # math constants
    TWO_PI     = PI * 2.0
    TAU        = PI * 2.0
    HALF_PI    = PI / 2.0
    QUARTER_PI = PI / 4.0
    VERSION    = 0 # i'll set this up later

    # rect and ellipse modes
    CORNER  = "CORNER"
    CORNERS = "CORNERS"
    CENTER  = "CENTER"
    RADIUS  = "RADIUS"

    # arc modes
    PIE        = "PIE"
    CHORD      = "CHORD"
    OPEN       = "OPEN"
    PIE_OPEN   = "PIE_OPEN"
    CHORD_OPEN = "CHORD_OPEN"

    # text modes (some are already initialized)
    LEFT        = "LEFT"
    RIGHT       = "RIGHT"
    TOP         = "TOP"
    MIDDLE      = "MIDDLE"
    BOTTOM      = "BOTTOM"
    BASELINE    = "BASELINE"
    NORMAL      = "NORMAL"
    ITALIC      = "ITALIC"
    BOLD        = "BOLD"
    BOLDITALIC  = "BOLDITALIC"

    PROTECTED_NAMES = (
      Object.instance_methods + Object.private_instance_methods +
        Kernel.instance_methods + Kernel.private_instance_methods +
        BasicObject.instance_methods
    ).freeze

    Sketch.public_instance_methods(false).each do |name|
      next if PROTECTED_NAMES.include?(name)

      define_method(name) do |*args, **kw, &blk|
        Shapekitty.default_sketch.public_send(name, *args, **kw, &blk)
      end
    end
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