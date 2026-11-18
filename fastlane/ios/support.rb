require "json"
require "addressable/uri"
require "fileutils"
require "open3"
require_relative "asset_packs"
require_relative "creative_assets"
require_relative "cleanup"

module MuntathirRelease
  # Fastlane 2.241.1 omits editable versions already attached to a draft review.
  module EditableReviewDraft
    def fetch_edit_app_info(client: nil, includes: Spaceship::ConnectAPI::AppInfo::ESSENTIAL_INCLUDES)
      super || (client || Spaceship::ConnectAPI).get_app_infos(app_id: id, includes: includes)
        .to_models.find { |info| info.state == "READY_FOR_REVIEW" }
    end

    def get_edit_app_store_version(**options)
      super || get_app_store_versions(client: options[:client],
                                     filter: { platform: options[:platform] || "IOS", appVersionState: "READY_FOR_REVIEW" },
                                     includes: options[:includes] || Spaceship::ConnectAPI::AppStoreVersion::ESSENTIAL_INCLUDES)
        .max_by { |version| Gem::Version.new(version.version_string) }
    end
  end

  ROOT = File.expand_path("../../apple", __dir__)
  # Apple does not support Persian store metadata; its copy stays in listing-drafts/fa.
  LOCALES = %w[en-US ar-SA fr-FR de-DE id it ja ms ru es-ES tr ur-PK zh-Hans zh-Hant].freeze
  LANGUAGE_ALIASES = { "ar" => "ar-SA", "en" => "en-US" }.freeze
  DEVICES = ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)", "iPhone Duo"].freeze
  PREVIEW_DEVICES = DEVICES.reject { |name| name == "iPhone Duo" }.freeze
  WATCH_SCREENSHOT = "Apple Watch Series 12 (46mm)-01-PrayerTimes.png".freeze
  SCREENSHOTS = JSON.parse(File.read(File.join(__dir__, "marketing/screenshots.json"))).freeze

  SCREENSHOT_LOCALES = SCREENSHOTS.fetch("headlines").keys.freeze

  def self.capture_runtime(device)
    device == "iPhone Duo" ? ENV.fetch("SCREENSHOT_DUO_IOS_VERSION", "27.2") : ENV.fetch("SCREENSHOT_IOS_VERSION", "27.0")
  end

  def self.capture_locales(value)
    return SCREENSHOT_LOCALES if value.to_s.strip.empty?

    locales = value.split(",").map(&:strip).map { |locale| LANGUAGE_ALIASES.fetch(locale, locale) }
    raise "Unknown or duplicate screenshot locale" if locales.empty? || locales.uniq != locales || (locales - SCREENSHOT_LOCALES).any?

    locales
  end

  MAX_SCREENSHOT_WORKERS = 8

  # Workers serialize on the shared simulator lock; keep a small default.
  def self.default_screenshot_workers
    2
  end

  def self.capture_shards(locales, workers)
    count = Integer(workers)
    raise "Screenshot workers must be between 1 and #{MAX_SCREENSHOT_WORKERS}" unless (1..MAX_SCREENSHOT_WORKERS).cover?(count)

    Array.new([count, locales.length].min) { |index| locales.each_slice(count).filter_map { |slice| slice[index] } }
  rescue ArgumentError, TypeError
    raise "Screenshot workers must be between 1 and #{MAX_SCREENSHOT_WORKERS}"
  end

  def self.capture_passes(devices, locales)
    standard = devices - ["iPhone Duo"]
    passes = standard.empty? ? [] : [[standard, locales, capture_runtime(standard.first), false]]
    if devices.include?("iPhone Duo")
      # These locales need the compact capture layout to keep headlines/content within the outer display.
      compact = locales & %w[ja ru ur-PK]
      regular = locales - compact
      passes << [["iPhone Duo"], regular, capture_runtime("iPhone Duo"), false] unless regular.empty?
      passes << [["iPhone Duo"], compact, capture_runtime("iPhone Duo"), true] unless compact.empty?
    end
    passes
  end

  LIMITS = { "name" => 30, "subtitle" => 30, "keywords" => 100, "description" => 4000,
             "promotional_text" => 170, "release_notes" => 4000 }.freeze

  # App Store Connect rejects these in What’s New / metadata text fields.
  ASC_FORBIDDEN = /[ʿʾˈˌː]/u.freeze

  def self.validate_metadata!(root = File.join(__dir__, "metadata"), locales: LOCALES)
    locales.each do |locale|
      LIMITS.each do |field, limit|
        path = File.join(root, locale, "#{field}.txt")
        text = File.read(path).strip
        raise "#{locale}/#{field}: expected 1–#{limit} characters, got #{text.length}" unless (1..limit).cover?(text.length)
        if (bad = text.scan(ASC_FORBIDDEN).uniq).any?
          raise "#{locale}/#{field}: App Store Connect rejects #{bad.map { |c| c.inspect }.join(', ')}"
        end
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

  def self.stage_marketing_assets!(app)
    raise "Missing capture app: #{app}" unless File.directory?(app)
    run!("python3", "AssetPacks/assets.py", "validate", "--content", "all")
    FileUtils.mkdir_p(File.join(app, "Hadith"))
    FileUtils.cp("../build/hadith/dist/hadith.db", File.join(app, "Hadith/hadith.db"))
    FileUtils.mkdir_p(File.join(app, "Supplications"))
    FileUtils.cp("../build/hadith/dist/supplications.db", File.join(app, "Supplications/supplications.db"))
    FileUtils.mkdir_p(File.join(app, "MarketingQuran"))
    Dir.glob("Muntathir/Resources/Quran/*.db").reject { |path| %w[quran.db en.qarai.db].include?(File.basename(path)) }.each do |path|
      FileUtils.cp(path, File.join(app, "MarketingQuran", File.basename(path)))
    end
  end

  def self.validate_capture!(path)
    brightness = run!("magick", path, "-format", "%[fx:mean]", "info:").to_f
    raise "Blank capture: #{path}" unless brightness.between?(0.01, 0.99)
  end

  CREATIVE_SIZE = SCREENSHOTS.fetch("creative").fetch("size").freeze
  # App icon emerald + mark paths from AppIcon.icon/Assets/Muntathir-Icon.svg
  CREATIVE_GRADIENT = %w[#174F45 #082F2B].freeze
  CREATIVE_ICON_SVG = File.join(ROOT, "AppIcon.icon/Assets/Muntathir-Icon.svg").freeze

  def self.render_brand_creative!(root: ROOT, locales: LOCALES)
    width, height = CREATIVE_SIZE
    dir = File.join(root, "build/marketing/creative")
    FileUtils.mkdir_p(dir)
    mark = File.join(dir, "mark.png")
    shared = File.join(dir, "universal.png")
    raise "Missing app icon SVG: #{CREATIVE_ICON_SVG}" unless File.file?(CREATIVE_ICON_SVG)

    # ImageMagick's SVG renderer drops strokes/gradients, so draw the mark with -draw
    # using the same path data as Muntathir-Icon.svg (1024 canvas, no background fill).
    run!("magick", "-size", "1024x1024", "xc:none",
         "-stroke", "#F5F0DF", "-strokewidth", "32", "-fill", "none",
         "-draw", "path 'M 344,272 C 344,390 422,440 480,494 C 490,503 490,521 480,530 C 422,584 344,634 344,752'",
         "-draw", "path 'M 680,272 C 680,390 602,440 544,494 C 534,503 534,521 544,530 C 602,584 680,634 680,752'",
         "-fill", "#DCC18A", "-stroke", "none",
         "-draw", "path 'M 391,330 L 633,330 C 615,386 561,425 512,470 C 463,425 409,386 391,330 Z'",
         "-draw", "circle 512,553 520,553",
         "-draw", "path 'M 394,744 C 394,675 463,648 512,600 C 561,648 630,675 630,744 Z'",
         "-fill", "#F5F0DF",
         "-draw", "roundrectangle 296,232 728,280 24,24",
         "-draw", "roundrectangle 296,744 728,792 24,24",
         mark)
    tile = File.join(dir, "tile.png")
    run!("magick", mark, "-resize", "340x340", "-alpha", "set", "-channel", "A",
         "-evaluate", "multiply", "0.14", "+channel", tile)
    # Safe-area center is (2622, 1141); gravity Center +0-334 places the hero mark there.
    run!("magick", "-size", "#{width}x#{height}", "gradient:#{CREATIVE_GRADIENT.join('-')}",
         "(", "-size", "#{width}x#{height}", "tile:#{tile}", ")",
         "-compose", "over", "-composite",
         "(", mark, "-resize", "900x900", ")",
         "-gravity", "center", "-geometry", "+0-334", "-compose", "over", "-composite",
         "-alpha", "remove", "-alpha", "off", shared)
    actual = run!("magick", "identify", "-format", "%wx%h %[channels]", shared).strip
    raise "Invalid creative export: #{actual}" unless actual.start_with?(CREATIVE_SIZE.join("x")) && !actual.include?("rgba")

    locales.each do |locale|
      destination = File.join(dir, locale, "universal.png")
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(shared, destination)
    end
    shared
  end

  def self.validate_media!(root = ROOT, since: nil)
    expected = DEVICES.product(SCREENSHOTS.fetch("storeScreens")).map { |device, screen| "#{device}-#{screen}.png" } << WATCH_SCREENSHOT
    directory = File.join(root, "build/marketing/store")
    locales = Dir.children(directory).select { |entry| File.directory?(File.join(directory, entry)) }
    raise "Unexpected screenshot locale directories" unless (locales - SCREENSHOT_LOCALES).empty?

    SCREENSHOT_LOCALES.each do |locale|
      images = Dir.glob(File.join(directory, locale, "*.{png,jpg,jpeg}"), File::FNM_CASEFOLD)
      unless images.map { |image| File.basename(image) }.sort == expected.sort &&
             images.all? { |image| File.size?(image) && (!since || File.mtime(image) >= since) }
        raise "Missing, unexpected or stale styled screenshots for #{locale}"
      end
      creative = File.join(root, "build/marketing/creative", locale, "universal.png")
      unless File.file?(creative) && File.size?(creative) && (!since || File.mtime(creative) >= since)
        raise "Missing or stale creative asset for #{locale}"
      end
      actual = run!("magick", "identify", "-format", "%wx%h %[channels]", creative).strip
      raise "Invalid creative asset for #{locale}: #{actual}" unless actual.start_with?(CREATIVE_SIZE.join("x")) && !actual.include?("rgba")
    end
  end

  def self.beta_notes
    LOCALES.to_h do |locale|
      notes = File.read(File.join(__dir__, "beta_notes", "#{locale}.txt")).strip
      raise "Missing or oversized What to Test for #{locale}" unless (1..4000).cover?(notes.length)
      [locale, notes]
    end
  end

  def self.validate_notes_changed!(notes, previous, label, force: false)
    return if force

    prior = previous.to_h { |entry| [entry.locale, entry.whats_new.to_s.strip] }
    return unless prior.any? { |locale, text| notes.key?(locale) && !text.empty? }
    return unless notes.all? { |locale, text| text == prior[locale] }

    raise "#{label} is unchanged from App Store Connect. Update the notes or rerun with force:true."
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

  def self.validate_draft!(draft, version, expected_id: nil)
    if !draft || draft.app_version_state == "WAITING_FOR_REVIEW" || Gem::Version.new(draft.version_string) != Gem::Version.new(version)
      raise "Create or restore an editable iOS App Store draft for version #{version} before running this lane."
    end
    raise "The App Store draft for #{version} changed during the release run." if expected_id && draft.id != expected_id
  end

  def self.with_release_lock(root = ROOT)
    FileUtils.mkdir_p(File.join(root, "build"))
    File.open(File.join(root, "build", "fastlane-release.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
      raise "Another Fastlane release is running in this checkout." unless lock.flock(File::LOCK_EX | File::LOCK_NB)

      yield
    end
  end

  def self.build_uploads(app_id, version)
    versions = [version]
    versions << version.delete_suffix(".0") if version.count(".") == 2 && version.end_with?(".0")
    versions << "#{version}.0" if version.count(".") == 1
    pages = Spaceship::ConnectAPI.get_build_uploads(app_id: app_id, includes: "build", limit: 200,
                                                  filter: { cfBundleShortVersionString: versions.join(","), platform: "IOS" }).all_pages
    pages.flat_map { |page| page.body.fetch("data") }.select do |upload|
      attributes = upload.fetch("attributes")
      attributes.fetch("platform") == "IOS" && Gem::Version.new(attributes.fetch("cfBundleShortVersionString")) == Gem::Version.new(version)
    end
  end

  def self.wait_for_uploaded_build(app_id, version, existing_ids, timeout: 1800)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    observed_ids = []
    retry_message = "Check Build Uploads in App Store Connect before retrying."
    loop do
      uploads = build_uploads(app_id, version).reject { |upload| existing_ids.include?(upload.fetch("id")) }
      observed_ids |= uploads.map { |upload| upload.fetch("id") }
      raise "Multiple new iOS uploads for #{version}. #{retry_message}" if observed_ids.size > 1

      if (upload = uploads.first)
        attributes = upload.fetch("attributes")
        number = attributes.fetch("cfBundleVersion")
        state = attributes.dig("state", "state")
        raise "Build #{version} (#{number}) failed processing. #{retry_message}" if state == "FAILED"

        build_id = upload.dig("relationships", "build", "data", "id")
        if state == "COMPLETE" && build_id
          build = Spaceship::ConnectAPI::Build.get(build_id: build_id)
          raise "Build #{version} (#{number}) failed processing. #{retry_message}" if %w[FAILED INVALID].include?(build&.processing_state)

          if build&.processing_state == "VALID"
            unless build.platform == "IOS" && build.version == number && Gem::Version.new(build.app_version) == Gem::Version.new(version)
              raise "App Store Connect returned an unexpected build for #{version} (#{number}). #{retry_message}"
            end
            return build
          end
        end
      end

      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise "Timed out waiting for the new iOS build for #{version}. #{retry_message}" if remaining <= 0

      sleep([15, remaining].min)
    end
  end

  def self.existing_valid_build(app_id, version, build_number: nil)
    builds = build_uploads(app_id, version).filter_map do |upload|
      next unless upload.dig("attributes", "state", "state") == "COMPLETE"

      build_id = upload.dig("relationships", "build", "data", "id")
      next unless build_id

      build = Spaceship::ConnectAPI::Build.get(build_id: build_id)
      next unless build&.processing_state == "VALID" &&
                  build.platform == "IOS" &&
                  Gem::Version.new(build.app_version) == Gem::Version.new(version)

      build
    end

    if build_number && !build_number.to_s.strip.empty?
      selected = builds.find { |build| build.version.to_s == build_number.to_s }
      raise "No valid iOS build #{version} (#{build_number}) found in App Store Connect. Run testflight_public first." unless selected

      return selected
    end

    selected = builds.max_by { |build| [build.respond_to?(:uploaded_date) ? build.uploaded_date.to_s : "", build.version.to_i] }
    raise "No valid iOS build for version #{version} found in App Store Connect. Run testflight_public first." unless selected

    selected
  end

  def self.project_version
    # Xcode 27 JSON projects are not readable by Fastlane's xcodeproj dependency.
    settings = JSON.parse(run!("xcodebuild", "-project", File.join(ROOT, "Muntathir.xcodeproj"), "-scheme", "Muntathir", "-configuration", "Release",
                               "-destination", "generic/platform=iOS", "-showBuildSettings", "-json"))
    settings.find { |target| target["target"] == "Muntathir" }.fetch("buildSettings").fetch("MARKETING_VERSION")
  end

  def self.test_destinations(include_ipad:, output: nil)
    output ||= run!("xcodebuild", "-project", File.join(ROOT, "Muntathir.xcodeproj"), "-scheme", "Muntathir", "-showdestinations")
    simulators = output.split(/Ineligible destinations|Destinations incompatible/).first.to_s.lines.filter_map do |line|
      next unless line.match?(/platform:\s*iOS Simulator,/) && !line.match?(/\berror:\s*/)

      line.match(/\bid:\s*([\da-f-]+),\s*OS:\s*([\d.]+),\s*name:\s*([^}]+)\}/i)&.captures
    end
    # Use the iPhone generation first, then its installed iOS version and model.
    iphone = simulators.select { |_, _, name| name.match?(/\AiPhone \d/) }.max_by do |_, os, name|
      [name[/\d+/].to_i, Gem::Version.new(os), name.include?("Pro Max") ? 1 : 0, name]
    end
    raise "Install a compatible iPhone simulator for the Muntathir scheme in Xcode." unless iphone

    selected = [iphone]
    if include_ipad
      ipad_name = DEVICES.fetch(1)
      ipad = simulators.select { |_, _, name| name.strip == ipad_name }.max_by { |_, os, _| Gem::Version.new(os) }
      raise "Install a compatible #{ipad_name} simulator for the Muntathir scheme in Xcode." unless ipad

      selected << ipad
    end
    selected.map { |id, _, _| "platform=iOS Simulator,id=#{id}" }
  end

  def self.run!(*command)
    output, status = Open3.capture2e(*command.map(&:to_s))
    raise "#{command.first} failed: #{output.lines.last(12).join}" unless status.success?
    output
  end

  def self.run_parallel!(*commands)
    remaining = commands.to_h { |command| [Process.spawn(*command, chdir: ROOT, pgroup: true), command] }
    failed = nil
    until remaining.empty?
      pid, status = Process.wait2(-1)
      remaining.delete(pid)
      failed ||= [pid, status] unless status.success?
      remaining.each_key { |other| Process.kill("TERM", -other) rescue nil } if failed
    end
    raise "Parallel command failed with #{failed.last.exitstatus || "signal #{failed.last.termsig}"}" if failed
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
    motion = run!("ffmpeg", "-hide_banner", "-nostats", "-i", path, "-vf", "freezedetect=n=-100dB:d=1", "-an", "-f", "null", "-")
    raise "Preview holds a frozen frame for at least one second: #{path}" if motion.include?("lavfi.freezedetect.freeze_start")
  end
end
