require_relative "image_loader"

module Shapekitty

  class Sketch

    def load_image(path) = Shapekitty::ImageLoader.load_file(path)

    def image(img, dx, dy, *args)
      surface = img.respond_to?(:surface) ? img.surface : img
      raise ArgumentError, "image() expects a Shapekitty::Image" unless surface.is_a?(Cairo::ImageSurface)

      img_w = surface.width
      img_h = surface.height

      dw = nil
      dh = nil
      sx = 0
      sy = 0
      sw = img_w
      sh = img_h
      tl = 0
      tr = nil
      br = nil
      bl = nil

      case args.size
      when 1
        dw = dh = args[0]
      when 2
        dw, dh = args
      when 3
        dw, dh, tl = args
      when 4
        sx, sy, sw, sh = args
      when 6
        dw, dh, sx, sy, sw, sh = args
      when 7
        dw, dh, sx, sy, sw, sh, tl = args
      when 10
        dw, dh, sx, sy, sw, sh, tl, tr, br, bl = args
      end

      tl ||= 0
      tr ||= tl
      br ||= tl
      bl ||= tl

      rx, ry, rdw, rdh =
      case @image_mode
      when CORNER
        [dx, dy, dw || img_w, dh || img_h]
      when CENTER
        w_val = dw || img_w
        h_val = dh || img_h
        [dx - (w_val / 2.0), dy - (h_val / 2.0), w_val, h_val]
      when CORNERS
        # if dw/dh are passed, they act as x2/y2. if not, use img_w/img_h as offsets.
        x2 = dw || (dx + img_w)
        y2 = dh || (dy + img_h)
        [dx, dy, x2 - dx, y2 - dy]
      else
        [dx, dy, dw || img_w, dh || img_h]
      end

      @cr.save

      # rounded corners clipping path
      if [tl, tr, br, bl].max > 0
        @cr.new_path
        @cr.arc(rx + rdw - tr, ry + tr, tr, 3 * Math::PI / 2, 2 * Math::PI)
        @cr.arc(rx + rdw - br, ry + rdh - br, br, 0, Math::PI / 2)
        @cr.arc(rx + bl, ry + rdh - bl, bl, Math::PI / 2, Math::PI)
        @cr.arc(rx + tl, ry + tl, tl, Math::PI, 3 * Math::PI / 2)
        @cr.close_path
        @cr.clip
      else
        @cr.rectangle(rx, ry, rdw, rdh)
        @cr.clip
      end

      @cr.translate(rx, ry)
      @cr.scale(rdw.to_f / sw, rdh.to_f / sh) if sw > 0 && sh > 0
      @cr.translate(-sx, -sy)

      @cr.set_source(surface, 0, 0)
      @cr.paint
      @cr.restore
    end

    def image_mode(mode)
      case mode
      when CORNER then @image_mode = CORNER
      when CORNERS then @image_mode = CORNERS
      when CENTER then @image_mode = CENTER
      end
    end

  end

end