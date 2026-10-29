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
      @rect_mode = CORNER
      @ellipse_mode = CENTER
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

    def point(x, y)
      @cr.save
      @cr.set_line_cap(Cairo::LINE_CAP_ROUND)
      @cr.move_to(x, y)
      @cr.line_to(x, y)
      stroke_shape
      @cr.restore
    end

    def circle(*args)
      case @ellipse_mode
      when CENTER
        x, y, d = args
        @cr.arc(x, y, d / 2.0, 0, 2 * Math::PI)
      when CORNER
        x, y, d = args
        @cr.arc(x + (d / 2.0), y + (d / 2.0), d / 2.0, 0, 2 * Math::PI)
      when RADIUS
        x, y, r = args
        @cr.arc(x, y, r, 0, 2 * Math::PI)
      when CORNERS
        x1, y1, x2, y2 = args
        cx = (x1 + x2) / 2.0
        cy = (y1 + y2) / 2.0
        r  = (x2 - x1).abs / 2.0
        @cr.arc(cx, cy, r, 0, 2 * Math::PI)
      end
      paint_shape
    end

    def ellipse(x, y, w, h = w)
      case @ellipse_mode
      when CENTER
        x, y, w, h = args
        h ||= w
        @cr.save
        @cr.translate(x, y)
        @cr.scale(w / 2.0, h / 2.0)
        @cr.arc(0, 0, 1.0, 0, 2 * Math::PI)
        @cr.restore
      when CORNER
        x, y, w, h = args
        h ||= w
        @cr.save
        @cr.translate(x + (w / 2.0), y + (h / 2.0))
        @cr.scale(w / 2.0, h / 2.0)
        @cr.arc(0, 0, 1.0, 0, 2 * Math::PI)
        @cr.restore
      when RADIUS
        x, y, rx, ry = args
        ry ||= rx
        @cr.save
        @cr.translate(x, y)
        @cr.scale(rx, ry)
        @cr.arc(0, 0, 1.0, 0, 2 * Math::PI)
        @cr.restore
      when CORNERS
        x1, y1, x2, y2 = args
        cx = (x1 + x2) / 2.0
        cy = (y1 + y2) / 2.0
        w  = (x2 - x1).abs
        h  = (y2 - y1).abs
        @cr.save
        @cr.translate(cx, cy)
        @cr.scale(w / 2.0, h / 2.0)
        @cr.arc(0, 0, 1.0, 0, 2 * Math::PI)
        @cr.restore
      end
      paint_shape
    end

    def arc(x, y, w, h, start, stop, mode = PIE_OPEN) # later
      cx, cy, w, h = case @ellipse_mode
      when CENTER
        h ||= w
        [x, y, w, h]
      when CORNER
        h ||= w
        [x + (w / 2.0), y + (h / 2.0), w, h]
      when RADIUS
        ry = h || w
        [x, y, w * 2.0, ry * 2.0]
      when CORNERS
        x1, y1, x2, y2 = x, y, w, h
        [(x1 + x2) / 2.0, (y1 + y2) / 2.0, (x2 - x1).abs, (y2 - y1).abs]
      end

      @cr.save
      @cr.translate(cx, cy)
      @cr.scale(w / 2.0, h / 2.0)

      @cr.new_path

      case mode
      when PIE
        @cr.move_to(0, 0)
        @cr.arc(0, 0, 1.0, start, stop)
        @cr.close_path
      when CHORD
        @cr.arc(0, 0, 1.0, start, stop)
        @cr.close_path
      when CHORD_OPEN, OPEN, PIE_OPEN
        @cr.arc(0, 0, 1.0, start, stop)
        @cr.close_path if mode == CHORD_OPEN
      else
        @cr.arc(0, 0, 1.0, start, stop)
      end

      @cr.restore

      paint_shape
    end

    def capsule(x1, y1, x2, y2, r)
      dx = x2 - x1
      dy = y2 - y1
      dist = Math.sqrt(dx * dx + dy * dy)

      @cr.new_path

      if dist.zero?
        # if points overlap, fallback and draw a circle
        @cr.arc(x1, y1, r, 0, 2 * Math::PI)
      else
        nx = (-dy / dist) * r
        ny = (dx / dist) * r

        angle = Math.atan2(dy, dx)

        @cr.arc(x1, y1, r, angle + Math::PI / 2, angle + 3 * Math::PI / 2)
        @cr.arc(x2, y2, r, angle - Math::PI / 2, angle + Math::PI / 2)
        @cr.close_path
      end

      paint_shape
    end

    def rect(x, y, w, h, tl = 0, tr = tl, br = tl, bl = tl)
      case @rect_mode
      when CORNER
        rx, ry, rw, rh = x, y, w, h
      when CORNERS
        rx, ry, rw, rh = x, y, w - x, h - y
      when CENTER
        rx, ry, rw, rh = x - (w / 2.0), y - (h / 2.0), w, h
      when RADIUS
        rx, ry, rw, rh = x - w, y - h, w * 2.0, h * 2.0
      end

      if tl > 0
        @cr.new_sub_path
        @cr.arc(rx + rw - tr, ry + tr, tr, 3 * Math::PI / 2, 2 * Math::PI)
        @cr.arc(rx + rw - br, ry + rh - br, br, 0, Math::PI / 2)
        @cr.arc(rx + bl, ry + rh - bl, bl, Math::PI / 2, Math::PI)
        @cr.arc(rx + tl, ry + tl, tl, Math::PI, 3 * Math::PI / 2)
        @cr.close_path
      else
        @cr.rectangle(rx, ry, rw, rh)
      end
      paint_shape
    end

    def square(x, y, s, tl = 0, tr = tl, br = tl, bl = tl)
      case @rect_mode
      when CORNER
        rx, ry, rw, rh = x, y, s, s
      when CORNERS
        rx, ry, rw, rh = x, y, s - x, s - y
      when CENTER
        rx, ry, rw, rh = x - (s / 2.0), y - (s / 2.0), s, s
      when RADIUS
        rx, ry, rw, rh = x - s, y - s, s * 2.0, s * 2.0
      end

      if tl > 0
        @cr.new_sub_path
        @cr.arc(rx + rw - tr, ry + tr, tr, 3 * Math::PI / 2, 2 * Math::PI)
        @cr.arc(rx + rw - br, ry + rh - br, br, 0, Math::PI / 2)
        @cr.arc(rx + bl, ry + rh - bl, bl, Math::PI / 2, Math::PI)
        @cr.arc(rx + tl, ry + tl, tl, Math::PI, 3 * Math::PI / 2)
        @cr.close_path
      else
        @cr.rectangle(rx, ry, rw, rh)
      end
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

    def rect_mode(mode)
      case mode
      when CORNER then @rect_mode = CORNER
      when CORNERS then @rect_mode = CORNERS
      when CENTER then @rect_mode = CENTER
      when RADIUS then @rect_mode = RADIUS
      end
    end

    def ellipse_mode(mode)
      case mode
      when CORNER then @ellipse_mode = CORNER
      when CORNERS then @ellipse_mode = CORNERS
      when CENTER then @ellipse_mode = CENTER
      when RADIUS then @ellipse_mode = RADIUS
      end
    end

    def beginShape
      @vertices = []
      @in_shape = true
      @cr.new_path
    end

    def vertex(x, y)
      @vertices << { type: :vertex, x: x, y: y, fill: @fill&.dup }
    end

    def bezierVertex(cp1x, cp1y, cp2x, cp2y, x, y)
      @vertices << { type: :bezier, cp1x: cp1x, cp1y: cp1y, cp2x: cp2x, cp2y: cp2y, x: x, y: y }
    end

    def quadraticVertex(cp1x, cp1y, x, y)
      @vertices << { type: :quadratic, cp1x: cp1x, cp1y: cp1y, x: x, y: y }
    end

    def beginContour
      @vertices << { type: :begin_contour }
    end

    def endContour
      @vertices << { type: :end_contour }
    end

    def endShape(close = false)
      return if @vertices.empty?

      @cr.new_path
      # uses the even-odd fill rule to support holes created by contours natively
      @cr.fill_rule = Cairo::FILL_RULE_EVEN_ODD

      @vertices.each_with_index do |v, i|
        case v[:type]
        when :vertex
          if i == 0 || @vertices[i - 1][:type] == :begin_contour
            @cr.move_to(v[:x], v[:y])
          else
            @cr.line_to(v[:x], v[:y])
          end
        when :bezier
          @cr.curve_to(v[:cp1x], v[:cp1y], v[:cp2x], v[:cp2y], v[:x], v[:y])
        when :quadratic
          # converts quadratic bezier control point to cubic bezier control points for Cairo
          curr_x, curr_y = @cr.current_point
          cp1x = curr_x + (2.0 / 3.0) * (v[:cp1x] - curr_x)
          cp1y = curr_y + (2.0 / 3.0) * (v[:cp1y] - curr_y)
          cp2x = v[:x] + (2.0 / 3.0) * (v[:cp1x] - v[:x])
          cp2y = v[:y] + (2.0 / 3.0) * (v[:cp1y] - v[:y])
          @cr.curve_to(cp1x, cp1y, cp2x, cp2y, v[:x], v[:y])
        when :begin_contour
          @cr.new_sub_path
        when :end_contour
          # just here
        end
      end

      @cr.close_path if close
      paint_shape
      @in_shape = false
    end

    def bezier(x1, y1, x2, y2, x3, y3, x4, y4)
      @cr.new_path
      @cr.move_to(x1, y1)
      @cr.curve_to(x2, y2, x3, y3, x4, y4)
      paint_shape
    end

    def curve(x1, y1, x2, y2, x3, y3, x4, y4)
      cp1x = x2 + (x3 - x1) / 6.0
      cp1y = y2 + (y3 - y1) / 6.0
      cp2x = x3 - (x4 - x2) / 6.0
      cp2y = y3 - (y4 - y2) / 6.0

      @cr.new_path
      @cr.move_to(x2, y2)
      @cr.curve_to(cp1x, cp1y, cp2x, cp2y, x3, y3)
      paint_shape
    end
    # shapes end

    def push
      @state_stack ||= []
      @state_stack.push({
        fill: @fill&.dup,
        stroke: @stroke&.dup,
        weight: @weight,
        do_fill: @do_fill,
        do_stroke: @do_stroke,
        rect_mode: @rect_mode,
        ellipse_mode: @ellipse_mode
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