# frozen_string_literal: true

require "libui"
require_relative "shapes"
require_relative "text"

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
      # state from sketch.rb
      @fill      = [1.0, 1.0, 1.0, 1.0]
      @stroke    = [0.0, 0.0, 0.0, 1.0]
      @do_fill   = true
      @do_stroke = true
      @weight    = 1.0
      @frame_count = 0
      @target_fps = 60

      # state for shapes.rb
      @rect_mode = CORNER
      @ellipse_mode = CENTER

      # state for text.rb
      @text_size = 12
      @text_font = "Helvetica"
      @text_horizontal = LEFT
      @text_vertical = BASELINE
      @text_leading = nil
      @text_style = NORMAL
      @text_weight = Cairo::FONT_WEIGHT_NORMAL
      @text_slant  = Cairo::FONT_SLANT_NORMAL
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

      # accept an argument (`_time`) so LibUI's callback argument doesn't crash the program. *bleurgh*
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

    def create_canvas(w, h, title = "shapekitty")
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

    def translate(x, y)
      @cr.translate(x, y)
    end

    def rotate(angle)
      @cr.rotate(angle)
    end

    def scale(sx, sy = nil)
      sy ||= sx
      @cr.scale(sx, sy)
    end

    def push
      @state_stack ||= []
      @state_stack.push({
        fill: @fill&.dup,
        stroke: @stroke&.dup,
        weight: @weight,
        do_fill: @do_fill,
        do_stroke: @do_stroke,
        rect_mode: @rect_mode,
        ellipse_mode: @ellipse_mode,
        text_size: @text_size,
        text_font: @text_font,
        text_horizontal: @text_horizontal,
        text_vertical: @text_vertical,
        text_leading: @text_leading,
        text_style: @text_style
      })
      @cr.save
    end

    def pop
      return if @state_stack.nil? || @state_stack.empty?
      state = @state_stack.pop

      @fill = state[:fill]
      @stroke = state[:stroke]
      @weight = state[:weight]
      @do_fill = state[:do_fill]
      @do_stroke = state[:do_stroke]
      @rect_mode = state[:rect_mode]
      @ellipse_mode = state[:ellipse_mode]
      @text_size = state[:text_size]
      @text_font = state[:text_font]
      @text_horizontal = state[:text_horizontal]
      @text_vertical = state[:text_vertical]
      @text_leading = state[:text_leading]
      @text_style = state[:text_style]

      # Restore Cairo's native graphics state (transforms, clips, etc.)
      @cr.restore
    end

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
      # hex code stuff
      if args.size == 1 && args[0].is_a?(String) && args[0].start_with?("#")
        hex = args[0].delete("#")
        r = hex[0..1].to_i(16)
        g = hex[2..3].to_i(16)
        b = hex[4..5].to_i(16)
        a = hex.length == 8 ? hex[6..7].to_i(16) : 255
        args = [r, g, b, a]
      end

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