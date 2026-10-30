module Shapekitty

  class Sketch

    def initialize
      @rect_mode = CORNER
      @ellipse_mode = CENTER
    end

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

    def ellipse(*args)
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

      if [tl, tr, br, bl].max > 0
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

      if [tl, tr, br, bl].max > 0
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
      when CORNER, CORNERS, CENTER, RADIUS
        @rect_mode = mode
      else
        raise ArgumentError, "unknown rect_mode: #{mode.inspect}"
      end
    end

    def ellipse_mode(mode)
      case mode
      when CORNER, CORNERS, CENTER, RADIUS
        @ellipse_mode = mode
      else
        raise ArgumentError, "unknown ellipse_mode: #{mode.inspect}"
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

  end

end