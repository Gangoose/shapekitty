require_relative "font_loader"

module Shapekitty

  class Sketch

    def initialize
      @text_size = 12
      @text_font = "Helvetica"
      @text_horizontal = LEFT
      @text_vertical = BASELINE
      @text_leading = nil
      @text_style = NORMAL
    end

    def text(str, x, y, wrapWidth = nil, lineLimit = nil)
      @cr.save

      if @fill
        @cr.set_source_rgba(*@fill)
      else
        @cr.set_source_rgb(0, 0, 1) # default color is black
      end

      @cr.set_font_size(@text_size)
      @cr.select_font_face(@text_font, @text_slant, @text_weight)

      font_extents = @cr.font_extents
      text_ascent = font_extents.ascent
      text_descent = font_extents.descent
      lh = text_leading

      lines = if wrapWidth && wrapWidth > 0
                wrap_text(str.to_s, wrapWidth)
              else
                str.to_s.split("\n", -1)
              end

      if lineLimit && lineLimit > 0
        lines = lines[0...lineLimit]
      end

      return if lines.empty?

      total_block_height = text_ascent + text_descent + (lines.size - 1) * lh

      base_y = case @text_vertical
               when BASELINE then y
               when TOP then y + text_ascent
               when MIDDLE, CENTER then y - (total_block_height / 2.0) + text_ascent
               when BOTTOM then y - total_block_height + text_ascent
               else y
               end

      lines.each_with_index do |line, i|
        line_extents = @cr.text_extents(line)
        line_width = line_extents.width

        line_x = case @text_horizontal
                 when LEFT then x
                 when CENTER then x - (line_width / 2.0)
                 when RIGHT then x - line_width
                 else x
                 end

        line_y = base_y + (i * lh)

        @cr.move_to(line_x, line_y)
        @cr.show_text(line)
      end

      @cr.restore
      paint_shape
    end
    def text_size(size = @text_size)
      @text_size = size
    end

    def text_align(horiz, vert)
      @text_horizontal = horiz
      @text_vertical = vert
    end

    def text_style(style)
      case style
      when NORMAL
        @text_weight = Cairo::FONT_WEIGHT_NORMAL
        @text_slant = Cairo::FONT_SLANT_NORMAL
      when BOLD
        @text_weight = Cairo::FONT_WEIGHT_BOLD
        @text_slant = Cairo::FONT_SLANT_NORMAL
      when ITALIC
        @text_weight = Cairo::FONT_WEIGHT_NORMAL
        @text_slant = Cairo::FONT_SLANT_ITALIC
      when BOLDITALIC
        @text_weight = Cairo::FONT_WEIGHT_BOLD
        @text_slant = Cairo::FONT_SLANT_ITALIC
      end
    end

    def load_font(path) = FontLoader.load_file(path)

    def text_font(font = nil, size = nil)
      return @text_font if font.nil?

      @text_font = font.respond_to?(:family) ? font.family : font.to_s
      @text_size = size if size
    end

    # ascents might be valid
    def font_ascent  = with_font { |cr| cr.font_extents.ascent }
    def font_descent = with_font { |cr| cr.font_extents.descent }

    def text_ascent(str = nil)
      return font_ascent if str.nil?

      with_font { |cr| [-cr.text_extents(str.to_s).y_bearing, 0.0].max }
    end

    def text_descent(str = nil)
      return font_descent if str.nil?

      with_font do |cr|
        e = cr.text_extents(str.to_s)
        [e.y_bearing + e.height, 0.0].max
      end
    end

    def text_leading(val = nil)
      if val.nil?
        if @text_leading
          @text_leading
        else
          @cr.set_font_size(@text_size)
          @cr.select_font_face(@text_font, @text_slant, @text_weight)
          @cr.font_extents.height
        end
      else
        @text_leading = val.to_f
      end
    end

    def nf(n, left = 0, right = nil)
      return n.map { |v| nf(v, left, right) } if n.is_a?(Array)
      raise ArgumentError, "nf expects a number" unless n.is_a?(Numeric)
      return n.to_s if n.respond_to?(:finite?) && !n.finite?

      abs = n.abs
      str = if right
              format("%.#{[right.to_i, 0].max}f", abs)
            elsif abs.is_a?(Float)
              s = abs.to_s
              s.include?("e") ? format("%.20f", abs).sub(/\.?0+\z/, "") : s
            else
              abs.to_s
            end

      int, frac = str.split(".", 2)
      int = int.rjust(left.to_i, "0")
      out = frac ? "#{int}.#{frac}" : int
      n.negative? && str.match?(/[1-9]/) ? "-#{out}" : out
    end

    private

    # every text and measuring method goes through here, so none of them can
    # disagree about which font is active.
    def apply_font(cr = @cr)
      cr.set_font_size(@text_size)
      cr.select_font_face(@text_font, @text_slant, @text_weight)
    end

    def with_font
      @cr.save
      begin
        apply_font
        yield @cr
      ensure
        @cr.restore
      end
    end

    def wrap_text(str, wrap_width)
      paragraphs = str.split("\n", -1)
      wrapped_lines = []

      paragraphs.each do |para|
        if para.empty?
          wrapped_lines << ""
          next
        end

        words = para.split(/\s+/)
        current_line = ""

        words.each do |word|
          test_line = current_line.empty? ? word : "#{current_line} #{word}"
          if @cr.text_extents(test_line).width <= wrap_width
            current_line = test_line
          else
            wrapped_lines << current_line unless current_line.empty?
            current_line = word
          end
        end
        wrapped_lines << current_line unless current_line.empty?
      end
      wrapped_lines
    end

  end

end