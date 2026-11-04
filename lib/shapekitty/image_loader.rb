# frozen_string_literal: true

require "net/http"
require "uri"
require "digest"
require "tmpdir"
require "cairo"

module Shapekitty
  Image = Struct.new(:surface, :width, :height, :path, keyword_init: true) do
    def to_s = path
  end

  module ImageLoader
    @loaded = {}

    class << self
      def load_file(path_or_url)
        path_str = path_or_url.to_s

        path = if path_str.match?(%r{\Ahttps?://}i)
                 download_url(path_str)
               else
                 expanded = File.expand_path(path_str)
                 raise ArgumentError, "image file not found: #{expanded}" unless File.file?(expanded)
                 expanded
               end

        @loaded[path] ||= begin
          surface = load_surface(path)
          Image.new(surface: surface, width: surface.width, height: surface.height, path: path)
        end
      end

      private

      def load_surface(path)
        begin
          surface = Cairo::ImageSurface.from_png(path)

          # Because of the LibUI hack in Sketch#to_rgba, colors are swapped (BGR).
          # Cairo loads images natively as BGRA, so we must swap the Red and Blue
          # channels here using fast C-level unpacking to match LibUI's RGBA format.
          data = surface.data
          swapped = data.unpack("V*").map! { |p|
            (p & 0xFF00FF00) | ((p & 0x00FF0000) >> 16) | ((p & 0x000000FF) << 16)
          }.pack("V*")

          # Overwrite the surface's memory with the corrected data
          data.replace(swapped)

          surface
        rescue Cairo::Error => e
          raise ArgumentError, "Failed to load image '#{path}'. Cairo only natively supports .png files. (Error: #{e.message})"
        end
      end

      def download_url(url_str, limit = 5)
        raise "HTTP redirect too deep" if limit == 0

        uri = URI.parse(url_str)
        raise ArgumentError, "invalid image URL: #{url_str}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        ext = File.extname(uri.path)
        ext = ".png" if ext.empty? || ext.length > 5
        cache_path = File.join(Dir.tmpdir, "shapekitty_image_#{Digest::SHA256.hexdigest(url_str)}#{ext}")

        unless File.exist?(cache_path)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
            request = Net::HTTP::Get.new(uri)
            response = http.request(request)
            case response
            when Net::HTTPSuccess
              File.binwrite(cache_path, response.body)
            when Net::HTTPRedirection
              return download_url(response["location"], limit - 1)
            else
              raise "failed to download image from #{url_str}: #{response.code} #{response.message}"
            end
          end
        end

        cache_path
      end
    end
  end
end
