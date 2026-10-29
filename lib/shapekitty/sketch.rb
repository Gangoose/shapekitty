# frozen_string_literal: true

require "libui"

module Shapekitty

  class Sketch
    UI = LibUI

    attr_reader(
      :width,
      :height,
      :frame_count,
      )

    # main loop
    def initialize
      @fill      = [1.0, 1.0, 1.0, 1.0]
      @stroke    = [0.0, 0.0, 0.0, 1.0]
      @do_fill   = true
      @do_stroke = true
      @weight    = 1.0
      @frame_count = 0
      @target_fps = 60
    end

    def setup(&block)
      @setup_block = block
    end

    def draw(&block)
      @draw_block = block
      run
    end

    # this runs stuff. basically, this is shapekitty's loop under the hood.
    def run
      @setup_block&.call
      create_canvas(300, 300) unless @window

      old_int  = Signal.trap("INT")  { @interrupted = true }
      old_term = Signal.trap("TERM") { @interrupted = true }

      current_fps = @target_fps

      # accept an argument (e.g. `_time`) so LibUI's callback argument doesn't crash the program
      timer_block = lambda do |_time|
        if @interrupted
          UI.quit
          next false
        end

        begin
          @draw_block&.call
          @frame_count += 1
          UI.area_queue_redraw_all(@area)

          if @target_fps != current_fps
            current_fps = @target_fps
            new_interval = (1000.0 / current_fps).to_i
            UI.timer(new_interval, &timer_block)
            next false
          end

          true
        rescue StandardError => e
          @error = e
          UI.quit
          false
        end
      end

      UI.timer((1000.0 / current_fps).to_i, &timer_block)

      UI.main
      raise @error if @error
      raise Interrupt if @interrupted
    ensure
      Signal.trap("INT", old_int || "DEFAULT")
      Signal.trap("TERM", old_term || "DEFAULT")
      shutdown
    end

    def create_canvas(w, h, title = "Shapekit")
      @width  = w
      @height = h
      UI.init
      @initialized = true

      # Cairo draws into @surface (memory owned by Cairo).
      @surface = Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32, w, h)
      @cr      = Cairo::Context.new(@surface)
      raise Error, "unexpected Cairo stride #{@surface.stride}" unless @surface.stride == w * 4

      # the area is a blank rectangle that LibUI lets Cairo paint on.
      @handler = UI::AreaHandler.new(
        draw: ->(event) { blit_to_area(event) },
        key_event: ->(event) { escape_to_quit(event) },
        )
      @area = UI.new_area(@handler)

      box = UI.new_horizontal_box
      UI.box_append(box, @area, 1)

      @window = UI.new_window(title, w, h, 0)
      UI.window_set_resizeable(@window, 0)
      UI.window_set_child(@window, box)
      UI.window_on_closing(@window) do
        @window_closed = true # LibUI destroys the window itself when we return 1
        UI.quit
        1
      end
      UI.control_show(@window)
    end

    # state
    def background(*args)
      @cr.set_source_rgba(*to_rgba(*args))
      @cr.paint
    end

    def fill(*args)
      @fill = to_rgba(*args)
      @do_fill = true
    end

    def stroke(*args)
      @stroke = to_rgba(*args)
      @do_stroke = true
    end

    def no_fill   = @do_fill = false
    def no_stroke = @do_stroke = false

    def stroke_weight(n)
      @weight = n.to_f
    end
    # state end

    # shapes
    def line(x1, y1, x2, y2)
      @cr.move_to(x1, y1)
      @cr.line_to(x2, y2)
      stroke_shape
    end

    def circle(x, y, d)
      @cr.arc(x, y, d / 2.0, 0, 2 * Math::PI)
      paint_shape
    end

    def ellipse(x, y, w, h)
      @cr.save
      @cr.translate(x, y)
      @cr.scale(w / 2.0, h / 2.0)
      @cr.arc(0, 0, 1.0, 0, 2 * Math::PI)
      @cr.restore
      paint_shape
    end

    def rect(x, y, w, h)
      @cr.rectangle(x, y, w, h)
      paint_shape
    end

    def square(x, y, s)
      @cr.rectangle(x, y, s, s)
      paint_shape
    end

    def quad(x1, y1, x2, y2, x3, y3, x4, y4)
      @cr.move_to(x1, y1)
      @cr.line_to(x2, y2)
      @cr.line_to(x3, y3)
      @cr.line_to(x4, y4)
      @cr.close_path
      paint_shape
    end

    def triangle(x1, y1, x2, y2, x3, y3)
      @cr.move_to(x1, y1)
      @cr.line_to(x2, y2)
      @cr.line_to(x3, y3)
      @cr.close_path
      paint_shape
    end
    # shapes end

    def frame_rate(target_fps)
      raise ArgumentError, "frame_rate must be above 0" unless target_fps.to_f.positive?

      @target_fps = target_fps
    end

    private

    # Processing typically uses colors are 0-255. Cairo uses 0.0-1.0. bleh.
    # nerd stuff below, but it's much needed!
    # the red/blue swap at the end is on purpose. Cairo stores each pixel in memory as the
    # bytes [B, G, R, A], but LibUI wants [R, G, B, A]. if we hand Cairo "red" where it expects
    # blue (and vice versa), the bytes land in the order LibUI wants, and we never have to
    # reshuffle 4 bytes x every pixel x every frame in Ruby.
    def to_rgba(*args)
      vals = case args.size
             when 1 then [args[0], args[0], args[0], 255]
             when 2 then [args[0], args[0], args[0], args[1]]
             when 3 then [*args, 255]
             when 4 then args
             else raise ArgumentError, "color takes 1 to 4 numbers, got #{args.size}"
             end
      r, g, b, a = vals.map { |v| v / 255.0 }
      [b, g, r, a]
    end

    def paint_shape
      if @do_fill
        @cr.set_source_rgba(*@fill)
        @do_stroke ? @cr.fill_preserve : @cr.fill
      end
      if @do_stroke
        @cr.set_source_rgba(*@stroke)
        @cr.set_line_width(@weight)
        @cr.stroke
      end
      @cr.new_path # clear the path in case neither fill nor stroke ran
    end

    def stroke_shape
      if @do_stroke
        @cr.set_source_rgba(*@stroke)
        @cr.set_line_width(@weight)
        @cr.stroke
      end
    end

    # LibUI calls this whenever the area needs repainting. it handles Cairo's pixels as an image.
    def blit_to_area(event)
      @surface.flush
      image = UI.new_image(@width, @height)
      UI.image_append(image, @surface.data, @width, @height, @surface.stride)
      event.context.draw_image(image, 0, 0, @width, @height)
    ensure
      UI.free_image(image) if image
    end

    def escape_to_quit(event)
      return false unless event.ext_key == UI::ExtKeyEscape && !event.up

      UI.quit
      true
    end

    def shutdown
      UI.control_destroy(@window) if @window && !@window_closed
      UI.uninit if @initialized
    end
  end
end