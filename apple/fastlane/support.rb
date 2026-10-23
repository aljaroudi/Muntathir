require "json"
require "addressable/uri"
require "fileutils"
require "open3"
require_relative "asset_packs"

module MuntathirRelease
  # Fastlane 2.241.1 omits editable versions already attached to a draft review.
  module EditableReviewDraft
    def get_edit_app_store_version(**options)
      super || get_app_store_versions(client: options[:client],
                                     filter: { platform: options[:platform] || "IOS", appVersionState: "READY_FOR_REVIEW" },
                                     includes: options[:includes] || Spaceship::ConnectAPI::AppStoreVersion::ESSENTIAL_INCLUDES)
        .max_by { |version| Gem::Version.new(version.version_string) }
    end
  end

  ROOT = File.expand_path("..", __dir__)
  # Apple does not support Persian store metadata; its copy stays in listing-drafts/fa.
  LOCALES = %w[en-US ar-SA fr-FR de-DE id it ja ms ru es-ES tr ur-PK zh-Hans zh-Hant].freeze
  DEVICES = ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)", "iPhone Duo"].freeze
  LIMITS = { "name" => 30, "subtitle" => 30, "keywords" => 100, "description" => 4000,
             "promotional_text" => 170, "release_notes" => 4000 }.freeze

  def self.validate_metadata!(root = File.join(__dir__, "metadata"), locales: LOCALES)
    locales.each do |locale|
      LIMITS.each do |field, limit|
        path = File.join(root, locale, "#{field}.txt")
        text = File.read(path).strip
        raise "#{locale}/#{field}: expected 1–#{limit} characters, got #{text.length}" unless (1..limit).cover?(text.length)
      end
    end
  end

  def self.optional_model(response)
    response.body && response.body["data"] ? response.to_models.first : nil
  end

  def self.metadata(locale, field)
    path = File.join(__dir__, "metadata", locale, "#{field}.txt")
    File.file?(path) ? File.read(path).strip : nil
  end

  def self.compliance!(config)
    value = config.fetch("submission_information", {})["export_compliance_uses_encryption"]
    raise "Set submission_information.export_compliance_uses_encryption to a confirmed boolean in the private review JSON" unless value == true || value == false
    value
  end

  def self.validate_media!(root = ROOT)
    headlines = JSON.parse(File.read(File.join(__dir__, "marketing/headlines.json")))
    LOCALES.each do |locale|
      DEVICES.each do |device|
        images = Dir.glob(File.join(root, "build/marketing/store", locale, "#{device}-*.png"))
        required = headlines.fetch(locale).keys
        raise "Missing styled screenshots for #{locale}/#{device}; run marketing" unless images.size == required.size && required.all? { |key| images.any? { |path| File.basename(path) == "#{device}-#{key}.png" } }
      end
      watch = File.join(root, "build/marketing/store", locale, "Apple Watch Series 12 (46mm)-01-PrayerTimes.png")
      raise "Missing required Apple Watch screenshot for #{locale}; run watch_screenshots" unless File.file?(watch)
      %w[IPHONE_67 IPAD_PRO_3GEN_129 IPHONE_DUO].each do |type|
        folder = type == "IPHONE_DUO" ? "duo-previews" : "previews"
        path = File.join(root, "build/marketing", folder, locale, "01-#{type}-SunriseToSunset.mp4")
        raise "Missing preview #{path}; run marketing" unless File.file?(path)
        validate_video!(path, type.start_with?("IPAD") ? [1200, 1600] : [886, 1920])

      end
    end
  end

  def self.review_config
    path = ENV["MUNTATHIR_REVIEW_CONFIG"]
    path && !path.empty? ? JSON.parse(File.read(File.expand_path(path))) : {}
  end

  def self.required!(values, fields, context)
    missing = fields.select { |field| values[field].to_s.strip.empty? }
    raise "#{context}: missing #{missing.join(', ')}. Set MUNTATHIR_REVIEW_CONFIG; see review.example.json." unless missing.empty?
  end

  def self.validate_url!(value, context)
    uri = Addressable::URI.parse(value.to_s)
    raise "#{context}: expected an HTTPS URL" unless uri.scheme == "https" && !uri.host.to_s.empty?
  rescue Addressable::URI::InvalidURIError
    raise "#{context}: expected an HTTPS URL"
  end

  def self.next_version(project_version, live_version, editable_version)
    # Reuse a pending version; after publication, default to the next patch.
    versions = [project_version, live_version].compact.map { |v| Gem::Version.new(v) }
    return editable_version if editable_version && (!live_version || Gem::Version.new(editable_version) > Gem::Version.new(live_version))
    current = versions.max
    return project_version unless live_version && current == Gem::Version.new(live_version)
    parts = current.segments.fill(0, current.segments.length...3)
    parts[2] += 1
    parts.join(".")
  end

  def self.run!(*command)
    output, status = Open3.capture2e(*command.map(&:to_s))
    raise "#{command.first} failed: #{output.lines.last(12).join}" unless status.success?
    output
  end

  def self.preview_filter(size, duo: false)
    if duo
      "scale=830:1800:force_original_aspect_ratio=decrease:force_divisible_by=2," \
        "pad=iw+16:ih+16:8:8:color=0x0d1117,pad=886:1920:(ow-iw)/2:(oh-ih)/2:color=0x10263f,setsar=1"
    else
      "scale=#{size.join(':')}:force_original_aspect_ratio=decrease,pad=#{size.join(':')}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1"
    end
  end

  def self.validate_video!(path, size, seconds: 15)
    data = JSON.parse(run!("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path))
    video = data.fetch("streams").find { |s| s["codec_type"] == "video" }
    duration = data.fetch("format").fetch("duration").to_f
    raise "Invalid preview dimensions/codec: #{path}" unless video && [video["width"], video["height"]] == size && video["codec_name"] == "h264" && video["pix_fmt"] == "yuv420p"
    raise "Invalid preview duration: #{duration}" unless ((seconds - 0.1)..(seconds + 0.1)).cover?(duration)
    raise "Preview exceeds 30 fps" if Rational(video.fetch("r_frame_rate")) > 30
    raise "Preview exceeds 500 MB" if File.size(path) > 500_000_000
  end
end
