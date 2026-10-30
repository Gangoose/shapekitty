# frozen_string_literal: true

require "fiddle"
require "rbconfig"
require "net/http"
require "uri"
require "digest"
require "tmpdir"

module Shapekitty
  # what load_font returns
  Font = Struct.new(:family, :path, keyword_init: true) do
    def to_s = family
  end

  module FontLoader
    SFNT_TAGS = ["\x00\x01\x00\x00".b, "OTTO".b, "true".b, "typ1".b].freeze

    @loaded = {}

    class << self
      def load_file(path_or_url)
        path_str = path_or_url.to_s

        path = if path_str.match?(%r{\Ahttps?://}i) || path_str.include?("fonts.googleapis.com")
                 # make sure protocol is present (e.g. "fonts.googleapis.com/...")
                 url = path_str.match?(%r{\Ahttps?://}i) ? path_str : "https://#{path_str}"
                 resolve_font_url(url)
               else
                 expanded = File.expand_path(path_str)
                 raise ArgumentError, "font file not found: #{expanded}" unless File.file?(expanded)
                 expanded
               end

        @loaded[path] ||= begin
          family = read_family_name(path)
          unless register(path)
            raise "couldn't register #{File.basename(path)} with the system font " \
                  "backend (#{RbConfig::CONFIG['host_os']}). is it a .ttf/.otf/.ttc file?"
            end
          Font.new(family: family, path: path)
        end
      end

      private

      def resolve_font_url(url_str)
        # If it's a Google Fonts CSS URL, scrape the actual .ttf/.woff2 link from it
        if url_str.include?("fonts.googleapis.com/css")
          css_content = fetch_url_content(url_str, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
          # Look for the src url in the CSS
          match =
            css_content.match(/src:\s*url\(([^)]+)\)\s*format\(['"]?(?:truetype|opentype|woff2)['"]?\)/i) ||
            css_content.match(/url\((https?:\/\/[^)]+\.ttf[^)]*)\)/i) ||
            css_content.match(/url\((https?:\/\/[^)]+)\)/i)

          raise "couldn't extract font file URL from Google Fonts CSS: #{url_str}" unless match

          url_str = match[1].gsub(/['"]/, "")
        end

        download_url(url_str)
      end

      def fetch_url_content(url_str, user_agent = nil)
        uri = URI.parse(url_str)
        uri.scheme ||= "https"
        content = nil

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = user_agent if user_agent
          response = http.request(request)
          case response
          when Net::HTTPSuccess
            content = response.body
          when Net::HTTPRedirection
            return fetch_url_content(response["location"], user_agent)
          else
            raise "failed to fetch #{url_str}: #{response.code} #{response.message}"
          end
        end
        content
      end

      def download_url(url_str, limit = 5)
        raise "HTTP redirect too deep" if limit == 0

        uri = URI.parse(url_str)
        raise ArgumentError, "invalid font URL: #{url_str}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        ext = File.extname(uri.path)
        ext = ".ttf" if ext.empty? || ext.length > 5
        cache_path = File.join(Dir.tmpdir, "shapekitty_font_#{Digest::SHA256.hexdigest(url_str)}#{ext}")

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
              raise "failed to download font from #{url_str}: #{response.code} #{response.message}"
            end
          end
        end

        cache_path
      end

      def windows? = RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
      def macos?   = RbConfig::CONFIG["host_os"].match?(/darwin/)

      # registration
      def register(path)
        if windows?
          register_gdi(path)
        elsif macos?
          ok = register_coretext(path)
          register_fontconfig(path) || ok
        else
          register_fontconfig(path)
        end
      end

      def try_dlopen(*names)
        names.each do |n|
          return Fiddle.dlopen(n)
        rescue Fiddle::DLError
          next
        end
        nil
      end

      def register_fontconfig(path)
        lib = try_dlopen(
          "libfontconfig.so.1", "libfontconfig.so",
          "libfontconfig.1.dylib",
          "/opt/homebrew/lib/libfontconfig.1.dylib",
          "/usr/local/lib/libfontconfig.1.dylib"
        )
        return false unless lib

        add = Fiddle::Function.new(
          lib["FcConfigAppFontAddFile"],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], # config (NULL = current), utf-8 path
          Fiddle::TYPE_INT
        )
        add.call(nil, Fiddle::Pointer[path.b + "\0"]) != 0
      end

      def register_coretext(path)
        cf = try_dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        ct = try_dlopen("/System/Library/Frameworks/CoreText.framework/CoreText")
        return false unless cf && ct

        create_url = Fiddle::Function.new(
          cf["CFURLCreateFromFileSystemRepresentation"],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_CHAR],
          Fiddle::TYPE_VOIDP
        )
        release = Fiddle::Function.new(cf["CFRelease"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
        register = Fiddle::Function.new(
          ct["CTFontManagerRegisterFontsForURL"],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], # url, scope, CFError**
          Fiddle::TYPE_CHAR
        )

        bytes = path.b
        url = create_url.call(nil, Fiddle::Pointer[bytes], bytes.bytesize, 0)
        return false if url.null?

        begin
          k_scope_process = 1 # kCTFontManagerScopeProcess
          register.call(url, k_scope_process, nil) != 0
        ensure
          release.call(url)
        end
      end

      def register_gdi(path)
        gdi = try_dlopen("gdi32.dll")
        return false unless gdi

        abi = Fiddle::Function.const_defined?(:STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
        add = Fiddle::Function.new(
          gdi["AddFontResourceExW"],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], # name, flags, reserved
          Fiddle::TYPE_INT,
          abi
        )
        wide = (path.tr("/", "\\") + "\0").encode("UTF-16LE")
        fr_private = 0x10
        add.call(Fiddle::Pointer[wide], fr_private, nil) > 0 # returns number of fonts added
      end

      def read_family_name(path)
        data = File.binread(path)
        base = data[0, 4] == "ttcf" ? data[12, 4].unpack1("N") : 0 # first font of a .ttc
        raise ArgumentError, "not a TrueType/OpenType font: #{path}" unless SFNT_TAGS.include?(data[base, 4])

        num_tables = data[base + 4, 2].unpack1("n")
        name_off = nil
        num_tables.times do |i|
          rec = base + 12 + (i * 16)
          if data[rec, 4] == "name"
            name_off = data[rec + 8, 4].unpack1("N")
            break
          end
        end
        return fallback_family(path) unless name_off

        count, str_off = data[name_off + 2, 4].unpack("nn")
        wanted = windows? ? [1, 16] : [16, 1]
        best = nil

        count.times do |i|
          rec = name_off + 6 + (i * 12)
          pid, eid, _lid, nid, len, off = data[rec, 12].unpack("n6")
          next unless wanted.include?(nid)

          raw = data[name_off + str_off + off, len]
          str = decode_name(raw, pid, eid)
          next if str.nil? || str.strip.empty?

          score = ((wanted.size - wanted.index(nid)) * 10) + (pid == 3 ? 2 : (pid == 0 ? 1 : 0))
          best = [score, str] if best.nil? || score > best[0]
        end

        best ? best[1] : fallback_family(path)
      end

      def decode_name(raw, pid, eid)
        if pid == 3 || pid == 0
          raw.dup.force_encoding("UTF-16BE").encode("UTF-8", invalid: :replace, undef: :replace)
        elsif pid == 1 && eid == 0 # Mac Roman
          raw.dup.force_encoding("macRoman").encode("UTF-8", invalid: :replace, undef: :replace)
        end
      rescue EncodingError
        nil
      end

      def fallback_family(path)
        File.basename(path, ".*").sub(/[-_ ](Regular|Bold|Italic|Oblique|Light|Medium)\b.*/i, "")
      end
    end
  end
end