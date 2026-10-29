# frozen_string_literal: true

# if you have used Processing or p5.js
# shapekitty's API should be very familiar to you

require "shapekitty"
include Shapekitty::Global

# you can also reference shapekitty with a variable
# just remove the global inclusion (include Shapekitty::Global).
# kitty = Shapekitty::Sketch.new # uncomment this

setup do
  create_canvas 400, 400
  # or kitty.create_canvas 400, 400
end

draw do
  background 24, 24, 31

  stroke 255
  stroke_weight 1
  fill 255, 100, 100, 180
  square(150, 150, 100, 10)
end





