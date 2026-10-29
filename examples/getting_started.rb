# frozen_string_literal: true

# if you have used Processing

require "shapekitty"
include Shapekitty::Global

# you can also reference shapekitty with a variable
# just remove the global inclusion (include Shapekitty::Global).
# kitty = Shapekitty::Sketch.new # uncomment this

setup do
  create_canvas 520, 300
  # or kitty.create_canvas 520, 300
end

draw do
  background 24, 24, 31

  stroke 255
  stroke_weight 4
  fill 255, 100, 100, 180
  square(width / 2, height / 2, 120)
end





