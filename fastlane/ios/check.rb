require_relative "support"
require_relative "../gallery"
require "tmpdir"
require "spaceship"
Dir.chdir(MuntathirRelease::ROOT)
check_media = !ARGV.include?("--skip-media")

def assert(value, message)
  raise message unless value
end

def rejects(message)
  begin
    yield
  rescue StandardError
    return
  end
  raise message
end

MuntathirRelease.validate_metadata!
MuntathirRelease.validate_metadata!(File.join(__dir__, "listing-drafts"), locales: ["fa"])
require "fastlane_core/languages"
assert((MuntathirRelease::LOCALES - FastlaneCore::Languages::ALL_LANGUAGES).empty?, "Unsupported App Store locale")
if check_media
  assert(MuntathirRelease.capture_locales("ar,en") == %w[ar-SA en-US], "Screenshot language aliases changed")
  assert(MuntathirRelease.capture_locales("en-US,ar-SA") == %w[en-US ar-SA], "Canonical screenshot locales rejected")
  rejects("Unknown screenshot alias accepted") { MuntathirRelease.capture_locales("english") }
  rejects("Duplicate screenshot locale accepted") { MuntathirRelease.capture_locales("en,en-US") }
  assert(MuntathirRelease.capture_shards(%w[en-US ar-SA fr-FR], 2) == [["en-US", "fr-FR"], ["ar-SA"]], "Screenshot shards changed")
  assert(MuntathirRelease.capture_shards(["en-US"], 2) == [["en-US"]], "Single locale created an empty worker")
  assert(MuntathirRelease.capture_shards(%w[en-US ar-SA fr-FR], 3) == [["en-US"], ["ar-SA"], ["fr-FR"]], "Three screenshot shards changed")
  rejects("Too many screenshot workers accepted") { MuntathirRelease.capture_shards(%w[en-US ar-SA], 99) }
  assert(MuntathirRelease.default_screenshot_workers == 2, "Default screenshot workers changed")
  passes = MuntathirRelease.capture_passes(MuntathirRelease::DEVICES, %w[en-US ja])
  assert(passes.map { |pass| pass[0] }.flatten.uniq.sort == MuntathirRelease::DEVICES.sort, "Capture device missing")
  assert(passes.select { |pass| pass[0] == ["iPhone Duo"] }.map { |pass| [pass[1], pass[3]] } == [[["en-US"], false], [["ja"], true]], "Duo locale capture layouts changed")
  assert(!MuntathirRelease::PREVIEW_DEVICES.include?("iPhone Duo"), "Unsupported preview must not block releases")

  require "snapshot"
  require "frameit"
  assert(Frameit::Devices.const_defined?(:IPHONE_DUO_OUTER) && Frameit::Devices.const_defined?(:IPHONE_DUO_INNER), "Pinned Fastlane lacks native Duo frames")
  snapshot_config = FastlaneCore::Configuration.create(Snapshot::Options.available_options, {})
  snapshot_options = FastlaneCore::ConfigurationFile.new(snapshot_config, File.join(__dir__, "../Snapfile"), nil, true).options
  assert(snapshot_options[:languages] == MuntathirRelease::SCREENSHOT_LOCALES, "Screenshot locales must match metadata")
  screenshot_config = MuntathirRelease::SCREENSHOTS
  screens = screenshot_config.fetch("screens")
  assert(screens.length <= 10, "Store screenshot limit exceeded")
  headlines = screenshot_config.fetch("headlines")
  assert(screens == screens.uniq.sort && screens.each_with_index.all? { |screen, i| screen.start_with?(format("%02d-", i + 1)) }, "Screens must use ordered, unique upload filenames")
  marketing_tests = File.read("MuntathirUITests/MarketingScreenshotTests.swift")
  assert(marketing_tests.scan(/snapshot\("([^"]+)"/).flatten.uniq.sort == screens, "Capture and screenshot config disagree")
  assert(headlines.values.all? { |entries| entries.keys.sort == screens && entries.values.all? { |text| !text.strip.empty? } }, "Missing localized screenshot headline")
  assert(!screenshot_config.fetch("brand").strip.empty?, "Screenshot brand is empty")
  store = screenshot_config.fetch("storeScreens")
  assert(store == %w[01-Today 02-Quran 03-Hadith 05-Supplications 06-Tasbih 07-Rakaat 09-Calendar 10-Qibla], "Store scene order changed")
  play = screenshot_config.fetch("playLocales")
  listings = Dir.glob(File.join(__dir__, "../android/metadata/*/title.txt")).map { |path| File.basename(File.dirname(path)) }
  assert(play.keys.sort == listings.sort && play.values.sort == headlines.keys.sort, "Play locales must map every listing to its headlines")
  android_test = File.read(File.join(__dir__, "../../android/app/src/androidTest/kotlin/com/aljaroudi/muntathir/ui/MarketingScreenshotTest.kt"))
  assert(android_test.scan(/capture\("([^"]+)"/).flatten.sort == store, "Android capture and store gallery disagree")
  Dir.mktmpdir do |root|
    gallery = File.join(root, "gallery")
    replace_gallery(gallery) { |stage| File.write(File.join(stage, "retired.png"), "previous") }
    rejects("Partial gallery accepted") do
      replace_gallery(gallery) do |stage|
        File.write(File.join(stage, "01-Today.png"), "partial")
        raise "Missing capture"
      end
    end
    assert(Dir.children(gallery) == ["retired.png"], "Failed render replaced the prior gallery")
    replace_gallery(gallery) { |stage| File.write(File.join(stage, "01-Today.png"), "complete") }
    assert(Dir.children(gallery) == ["01-Today.png"], "Retired screenshot survived a successful render")
  end
  colors = screenshot_config.fetch("background")
  assert(colors.size == 2 && colors.all? { |rgb| rgb.size == 3 && rgb.all? { |value| (0..1).cover?(value) } }, "Invalid screenshot gradient")
  creative = screenshot_config.fetch("creative")
  assert(creative.fetch("size") == [5244, 2950], "Creative canvas must be Apple's universal 5244×2950")
  assert(MuntathirRelease::CREATIVE_SIZE == [5244, 2950], "Creative constants drifted")
  assert(File.file?(MuntathirRelease::CREATIVE_ICON_SVG), "App icon SVG missing for brand creative")
  group, spec_ids = MuntathirRelease.creative_placement_target(
    "features" => [{ "featureId" => "APP_STORE_VERSIONS",
                     "placementPolicies" => MuntathirRelease::CREATIVE_PLACEMENTS.map { |type|
                       { "placementType" => type, "groupLimits" => [{ "groupIds" => %w[DEFAULT_PROFILE OTHER], "maxCount" => 1 }] }
                     } }],
    "imageSpecs" => [{ "specId" => "universal-spec", "universalAsset" => true,
                       "dimensions" => { "minWidth" => 5244, "maxWidth" => 5244, "minHeight" => 2950, "maxHeight" => 2950 } }],
    "placementTypes" => MuntathirRelease::CREATIVE_PLACEMENTS.map { |type|
      { "placementTypeId" => type, "acceptsAssetCategories" => ["CREATIVE_ASSETS"],
        "specMappings" => [{ "placementGroupId" => "DEFAULT_PROFILE", "specs" => ["universal-spec"] },
                           { "placementGroupId" => "OTHER", "specs" => ["universal-spec"] }] }
    }
  )
  assert(group == "DEFAULT_PROFILE" && spec_ids == ["universal-spec"], "Creative placement target resolution changed")
  rejects("Invalid creative category accepted") do
    MuntathirRelease.creative_placement_target(
      "features" => [{ "featureId" => "APP_STORE_VERSIONS", "placementPolicies" => [] }],
      "imageSpecs" => [{ "specId" => "universal-spec",
                         "dimensions" => { "minWidth" => 5244, "maxWidth" => 5244, "minHeight" => 2950, "maxHeight" => 2950 } }],
      "placementTypes" => [{ "placementTypeId" => "PRODUCT_PAGE_HEADER_ASSET", "acceptsAssetCategories" => ["APP_SCREENSHOTS_AND_PREVIEWS"],
                            "specMappings" => [{ "placementGroupId" => "DEFAULT_PROFILE", "specs" => ["universal-spec"] }] }]
    )
  end

end

notes = MuntathirRelease.beta_notes
previous = notes.map { |locale, text| Struct.new(:locale, :whats_new).new(locale, "  #{text}  ") }
rejects("Unchanged notes accepted") { MuntathirRelease.validate_notes_changed!(notes, previous, "What to Test") }
MuntathirRelease.validate_notes_changed!(notes, previous, "What to Test", force: true)
MuntathirRelease.validate_notes_changed!(notes.merge("ar-SA" => "Updated"), previous, "What to Test")
MuntathirRelease.validate_notes_changed!(notes, [], "What to Test")

destinations = <<~XCODE
  Available destinations for the "Muntathir" scheme:
    { platform:iOS Simulator, arch:arm64, id:00000000-0000-0000-0000-000000000017, OS:27.2, name:iPhone 17 Pro Max }
    { platform:iOS Simulator, arch:arm64, id:00000000-0000-0000-0000-000000000018, OS:27.0, name:iPhone 18 Pro Max }
    { platform:iOS Simulator, arch:arm64, id:00000000-0000-0000-0000-000000000001, OS:27.2, name:iPad Pro 13-inch (M5) }
  Destinations incompatible with the "Muntathir" scheme:
    { platform:iOS Simulator, id:00000000-0000-0000-0000-000000000019, OS:28.0, name:iPhone 19 }
XCODE
iphone = "platform=iOS Simulator,id=00000000-0000-0000-0000-000000000018"
ipad = "platform=iOS Simulator,id=00000000-0000-0000-0000-000000000001"
assert(MuntathirRelease.test_destinations(include_ipad: false, output: destinations) == [iphone], "TestFlight must use the newest compatible iPhone")
assert(MuntathirRelease.test_destinations(include_ipad: true, output: destinations) == [iphone, ipad], "App Store must test iPhone and iPad")
rejects("Missing iPhone accepted") { MuntathirRelease.test_destinations(include_ipad: false, output: "") }
rejects("Missing iPad accepted") { MuntathirRelease.test_destinations(include_ipad: true, output: destinations.lines.reject { |line| line.include?("iPad") }.join) }
rejects("Missing review contact accepted") { MuntathirRelease.required!({}, %w[email], "review") }
rejects("Invalid URL accepted") { MuntathirRelease.validate_url!("http://example.com", "support") }
MuntathirRelease.validate_url!("https://example.com/support", "support")
Dir.mktmpdir do |dir|
  FileUtils.cp_r(File.join(__dir__, "metadata", "."), dir)
  File.write(File.join(dir, "en-US", "subtitle.txt"), "x" * 31)
  rejects("Oversize subtitle accepted") { MuntathirRelease.validate_metadata!(dir) }
end

pack_version = { "id" => "pack-v2", "relationships" => { "assetFile" => { "data" => { "id" => "archive" } } } }
pack_files = { "archive" => { "attributes" => { "sourceFileChecksums" => { "file" => { "hash" => "A1B2" } } } } }
assert(MuntathirRelease.matching_pack_version([pack_version], pack_files, ["a1b2"]) == pack_version, "Known archive must reuse its uploaded version")
assert(MuntathirRelease.matching_pack_version([pack_version], pack_files, ["changed"]).nil?, "Changed archive matched an old upload")

if check_media
  # Preserve Duo proportions inside Apple's required portrait preview canvas.
  Dir.mktmpdir do |dir|
    output = File.join(dir, "duo.png")
    MuntathirRelease.run!("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=white:s=1398x2034", "-frames:v", "1",
                         "-vf", MuntathirRelease.preview_filter([886, 1920], duo: true), output)
    assert(MuntathirRelease.run!("magick", "identify", "-format", "%wx%h", output).strip == "886x1920", "Duo preview canvas mismatch")
    bounds = MuntathirRelease.run!("magick", output, "-threshold", "99%", "-format", "%@", "info:").split(/[x+]/).map(&:to_i)
    assert((bounds[0].to_f / bounds[1] - 1398.0 / 2034).abs < 0.001, "Duo preview stretched the captured screen")
    assert(bounds[2] > 0 && bounds[3] > 0, "Duo frame/background missing")
  end

  # Every supported device/locale must include Quran, not merely four arbitrary images.
  Dir.mktmpdir do |dir|
    %w[color=blue:s=32x64:d=2:r=30 testsrc2=s=32x64:d=2:r=30].each_with_index do |source, index|
      path = File.join(dir, "motion-#{index}.mp4")
      MuntathirRelease.run!("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", source, "-c:v", "libx264", "-pix_fmt", "yuv420p", path)
      if index.zero?
        rejects("Frozen preview accepted") { MuntathirRelease.validate_video!(path, [32, 64], seconds: 2) }
      else
        MuntathirRelease.validate_video!(path, [32, 64], seconds: 2)
      end
    end
  end
  Dir.mktmpdir do |root|
    started = Time.now
    size = MuntathirRelease::CREATIVE_SIZE.join("x")
    MuntathirRelease::SCREENSHOT_LOCALES.each do |locale|
      directory = File.join(root, "build/marketing/store", locale)
      FileUtils.mkdir_p(directory)
      MuntathirRelease::DEVICES.product(store).each do |device, screen|
        File.write(File.join(directory, "#{device}-#{screen}.png"), "PNG")
      end
      File.write(File.join(directory, MuntathirRelease::WATCH_SCREENSHOT), "PNG")
      creative = File.join(root, "build/marketing/creative", locale, "universal.png")
      FileUtils.mkdir_p(File.dirname(creative))
      MuntathirRelease.run!("magick", "-size", size, "xc:#10263f", "-alpha", "off", creative)
    end
    MuntathirRelease.validate_media!(root, since: started)
    foreign = File.join(root, "build/marketing/store/unknown")
    FileUtils.mkdir_p(foreign)
    rejects("Unexpected locale accepted") { MuntathirRelease.validate_media!(root) }
    Dir.rmdir(foreign)
    quran = File.join(root, "build/marketing/store/en-US/#{MuntathirRelease::DEVICES.first}-#{screens.find { |screen| screen.end_with?('-Quran') }}.png")
    stale = started - 10
    File.utime(stale, stale, quran)
    rejects("Stale screenshot accepted") { MuntathirRelease.validate_media!(root, since: started) }
    FileUtils.mv(quran, File.join(File.dirname(quran), "99-Extra.png"))
    rejects("Missing Quran screenshot accepted") { MuntathirRelease.validate_media!(root) }
    FileUtils.mv(File.join(File.dirname(quran), "99-Extra.png"), quran)
    creative = File.join(root, "build/marketing/creative/en-US/universal.png")
    File.utime(stale, stale, creative)
    rejects("Stale creative accepted") { MuntathirRelease.validate_media!(root, since: started) }
    FileUtils.rm_f(creative)
    rejects("Missing creative accepted") { MuntathirRelease.validate_media!(root) }
  end
end

Dir.mktmpdir do |root|
  MuntathirRelease.with_release_lock(root) do
    rejects("Concurrent release accepted") { MuntathirRelease.with_release_lock(root) { nil } }
  end
  MuntathirRelease.with_release_lock(root) { nil }
end

# Cleanup removes only lane-owned caches, preserves release files, and rejects redirected paths.
Dir.mktmpdir do |root|
  FileUtils.mkdir_p(File.join(root, "build/DerivedData"))
  File.write(File.join(root, "build/keep.ipa"), "release")
  MuntathirRelease.cleanup_build_artifacts!(root: root)
  assert(!File.exist?(File.join(root, "build/DerivedData")), "Disposable cache retained")
  assert(File.file?(File.join(root, "build/keep.ipa")), "Release IPA deleted")
  rejects("Unknown cleanup path accepted") { MuntathirRelease.cleanup_build_artifacts!(root: root, paths: ["build"]) }
  File.symlink(root, File.join(root, "build/DerivedData"))
  rejects("Symlink cleanup accepted") { MuntathirRelease.cleanup_build_artifacts!(root: root) }
  archive = File.join(root, "test.xcarchive")
  FileUtils.mkdir_p(File.join(archive, "dSYMs"))
  File.write(File.join(archive, "dSYMs/app.dSYM"), "symbols")
  symbols = File.join(root, "symbols")
  MuntathirRelease.retire_archive!(archive, symbols: symbols)
  assert(!File.exist?(archive) && File.read(File.join(symbols, "app.dSYM")) == "symbols", "Archive cleanup lost symbols")
end
# Lane wiring tests must never clean the developer's real artifacts.
MuntathirRelease.define_singleton_method(:cleanup_build_artifacts!) { |**_| }

# Exercise lane wiring without network access, builds, uploads, or credentials.
module UI
  def self.user_error!(message) = raise(message)
  def self.header(*) = nil
  def self.success(*) = nil
  def self.error(*) = nil
end
class LaneCheck
  attr_reader :calls
  def initialize = @calls = []
  def default_platform(*) = nil
  def desc(*) = nil
  def sh(*args) = @calls << [:sh, args]
  def platform(name)
    @platform = name
    yield
  end
  def lane(name, &block)
    name = :"android_#{name}" if @platform == :android
    define_singleton_method(name) { |options = {}| instance_exec(options, &block) }
  end
  alias private_lane lane
  def method_missing(name, *args, **options)
    @calls << [name, options]
    true if name == :precheck
  end
  def respond_to_missing?(*) = true
end
check = LaneCheck.new
fastfile = File.expand_path("../Fastfile", __dir__)
check.instance_eval(File.read(fastfile), fastfile)

Dir.mktmpdir do |dir|
  bundle = File.join(dir, "app release.aab")
  key = File.join(dir, "play key.json")
  File.write(bundle, "")
  File.write(key, "{}")
  previous_key = ENV["SUPPLY_JSON_KEY"]
  begin
    ENV["SUPPLY_JSON_KEY"] = key
    rejects("Missing AAB accepted") { check.android_internal(aab: File.join(dir, "missing.aab")) }
    check.android_internal(aab: bundle)
    action, upload = check.calls.pop
    assert(action == :upload_to_play_store && upload[:aab] == bundle && upload[:json_key] == key &&
           upload[:track] == "internal" && upload[:release_status] == "completed" && !upload[:validate_only],
           "Android internal lane must publish by default")
    check.android_internal(aab: bundle, validate_only: true)
    assert(check.calls.pop.last[:validate_only], "Explicit validation must prevent publishing")
    check.android_internal(aab: bundle, draft: true)
    draft = check.calls.pop.last
    assert(draft[:release_status] == "draft" && !draft[:validate_only], "Explicit Android draft must save a draft")
  ensure
    ENV["SUPPLY_JSON_KEY"] = previous_key
  end
end

%i[screenshots style].each do |operation|
  check.public_send(:"android_#{operation}", languages: "ar,en,fa")
  _, args = check.calls.pop
  assert(args.last(2) == [operation.to_s, "ar,en,fa"], "Android #{operation} arguments changed")
end
check.screenshots(languages: "ar,en", workers: 1)
screenshot_command = check.calls.assoc(:sh).last
assert(screenshot_command.last(3) == ["", "ar,en", "1"], "Screenshot lane options changed")
check.calls.clear
check.style(languages: "ar,en")
assert(check.calls.assoc(:sh).last.last == "ar,en", "Style locale filter changed")
version = "1.1.0"
draft_version = Struct.new(:id, :version_string, :app_version_state, :release_type)
                     .new("draft", "1.1", "READY_FOR_REVIEW", "AFTER_APPROVAL")
MuntathirRelease.validate_draft!(draft_version, version)
rejects("Missing draft accepted") { MuntathirRelease.validate_draft!(nil, version) }
rejects("Mismatched draft accepted") { MuntathirRelease.validate_draft!(draft_version, "1.2.0") }
rejects("Replaced draft accepted") { MuntathirRelease.validate_draft!(draft_version, version, expected_id: "other") }
queued = draft_version.dup
queued.app_version_state = "WAITING_FOR_REVIEW"
rejects("Queued draft accepted") { MuntathirRelease.validate_draft!(queued, version) }
draft_base = Class.new do
  attr_accessor :draft
  def id = "draft-app"
  def fetch_edit_app_info(**_) = nil
  def get_edit_app_store_version(**_) = nil
  def get_app_store_versions(**_) = [draft]
end
draft_base.prepend(MuntathirRelease::EditableReviewDraft)
draft_app = draft_base.new
draft_app.draft = draft_version
assert(draft_app.get_edit_app_store_version(platform: "IOS", includes: "build") == draft_version, "Existing review draft must be editable")
draft_info = Struct.new(:state).new("READY_FOR_REVIEW")
info_response = Struct.new(:to_models).new([draft_info])
info_client = Object.new
info_client.define_singleton_method(:get_app_infos) { |**_| info_response }
assert(draft_app.fetch_edit_app_info(client: info_client, includes: "") == draft_info, "Ready draft app information must be editable")
draft_info.state = "IN_REVIEW"
assert(draft_app.fetch_edit_app_info(client: info_client, includes: "").nil?, "Fallback must not edit app information already in review")

# Use recorded API shapes so selection checks never depend on an Apple account.
upload = lambda do |id, number, state = "COMPLETE", platform = "IOS", version_string = "1.1"|
  { "id" => id, "attributes" => { "platform" => platform, "cfBundleShortVersionString" => version_string,
                                 "cfBundleVersion" => number, "state" => { "state" => state } },
    "relationships" => { "build" => { "data" => { "id" => "build-#{id}" } } } }
end
existing = upload.call("old", "16")
new_upload = upload.call("new", "17")
rows = [existing, new_upload, upload.call("other-platform", "17", "COMPLETE", "MAC_OS"),
        upload.call("other-version", "1", "COMPLETE", "IOS", "1.2")]
page_type = Struct.new(:body)
response_type = Struct.new(:all_pages)
spaceship = Spaceship::ConnectAPI
spaceship.define_singleton_method(:get_build_uploads) do |app_id:, filter:, **options|
  assert(app_id == "6824304362" && options[:includes] == "build" && filter[:platform] == "IOS", "Build upload query lost app, platform or build relationship")
  response_type.new(rows.each_slice(2).map { |batch| page_type.new({ "data" => batch }) })
end
build = Struct.new(:id, :version, :app_version, :platform, :processing_state).new("build-new", "17", "1.1", "IOS", "VALID")
Spaceship::ConnectAPI::Build.define_singleton_method(:get) do |build_id:|
  assert(build_id == build.id, "Selected a build unrelated to the new upload")
  build
end
app_id = "6824304362"
assert(MuntathirRelease.build_uploads(app_id, version).map { |entry| entry.fetch("id") } == %w[old new], "Build upload filter missed an equivalent version or accepted a different platform/version")
assert(MuntathirRelease.wait_for_uploaded_build(app_id, version, ["old"], timeout: 0) == build, "Wrong processed build selected")

build_old = Struct.new(:id, :version, :app_version, :platform, :processing_state, :uploaded_date).new("build-old", "16", "1.1", "IOS", "VALID", "2026-11-15T10:00:00Z")
build_new = Struct.new(:id, :version, :app_version, :platform, :processing_state, :uploaded_date).new("build-new", "17", "1.1", "IOS", "VALID", "2026-11-15T12:00:00Z")
build_lookup = { "build-old" => build_old, "build-new" => build_new }
Spaceship::ConnectAPI::Build.define_singleton_method(:get) { |build_id:| build_lookup.fetch(build_id) }
rows.replace([existing, new_upload])
assert(MuntathirRelease.existing_valid_build(app_id, version) == build_new, "App Store must select the latest valid build")
assert(MuntathirRelease.existing_valid_build(app_id, version, build_number: "16") == build_old, "App Store must honor explicit build_number")
rejects("Missing build number accepted") { MuntathirRelease.existing_valid_build(app_id, version, build_number: "99") }
rows.replace([upload.call("failed", "17", "FAILED")])
rejects("Failed upload accepted as existing build") { MuntathirRelease.existing_valid_build(app_id, version) }
rows.replace([existing, new_upload])
Spaceship::ConnectAPI::Build.define_singleton_method(:get) do |build_id:|
  assert(build_id == build.id, "Selected a build unrelated to the new upload")
  build
end

rows << upload.call("competing", "18")
rejects("Competing uploads accepted") { MuntathirRelease.wait_for_uploaded_build(app_id, version, ["old"], timeout: 0) }
rows.replace([existing, upload.call("failed", "17", "FAILED")])
rejects("Failed upload accepted") { MuntathirRelease.wait_for_uploaded_build(app_id, version, ["old"], timeout: 0) }
rows.replace([existing])
rejects("Existing upload reused after timeout") { MuntathirRelease.wait_for_uploaded_build(app_id, version, ["old"], timeout: 0) }

MuntathirRelease.define_singleton_method(:test_destinations) { |include_ipad:| include_ipad ? [iphone, ipad] : [iphone] }
check.tests
regressions = check.calls.find { |name, _| name == :run_tests }.last
assert(regressions[:destination] == [iphone], "Local regression lane must run on one iPhone by default")
assert(regressions[:testplan] == "Muntathir" && !regressions.key?(:skip_testing), "Regression lane must use the Muntathir test plan, which excludes marketing captures")
assert(!regressions[:parallel_testing] && regressions[:disable_concurrent_testing], "Regression lane must serialize UI tests")
assert(regressions[:derived_data_path] == File.join(MuntathirRelease::ROOT, "build/DerivedData"), "Regression and marketing build caches must stay separate")

MuntathirRelease.define_singleton_method(:validate_media!) { |**_| }
config = { "submission_information" => { "export_compliance_uses_encryption" => false } }
assert(MuntathirRelease.compliance!(config) == false, "Confirmed exemption lost")
rejects("Unconfirmed compliance accepted") { MuntathirRelease.compliance!({}) }
app = Struct.new(:id, :bundle_id).new(app_id, "com.aljaroudi.Muntathir")
app.define_singleton_method(:get_edit_app_store_version) { |**_| draft_version }
context = { app: app, version: version, draft: draft_version, config: config, encryption: false,
            release_notes: MuntathirRelease.release_notes(version).slice(*MuntathirRelease::LOCALES), beta_notes: notes, feedback_email: "review@example.com" }
synced_packs = 0
synced_creatives = 0
draft_localizations = [Struct.new(:locale, :id).new("en-US", "loc-en")]
MuntathirRelease.define_singleton_method(:sync_asset_packs!) do
  synced_packs += 1
  [{ name: "hadith", version: "2", version_id: "pack-v2", store_version_id: "pack-v1", external_version_id: "pack-v2" },
   { name: "rulings", version: "1", version_id: "rulings-v1", store_version_id: "rulings-v1", external_version_id: "rulings-v1" }]
end
MuntathirRelease.define_singleton_method(:sync_creative_assets!) do |localizations|
  synced_creatives += 1
  raise "Creative sync must use the draft localizations" unless localizations == draft_localizations
end
draft_version.define_singleton_method(:get_app_store_version_localizations) { draft_localizations }
check.define_singleton_method(:check) { |**_| }
check.define_singleton_method(:release_context) { |**options| calls << [:release_context, options]; context }

Dir.mktmpdir do |root|
  declared_root = MuntathirRelease::ROOT
  local_run = MuntathirRelease.method(:run!)
  select_build = MuntathirRelease.method(:wait_for_uploaded_build)
  MuntathirRelease.send(:remove_const, :ROOT)
  MuntathirRelease.const_set(:ROOT, root)
  FileUtils.mkdir_p(File.join(root, "build"))
  MuntathirRelease.define_singleton_method(:run!) do |*args|
    assert(args.first == "plutil" && args.last.end_with?("/Muntathir.app/Info.plist"), "Archive version must come from the built app")
    { "CFBundleShortVersionString" => version, "CFBundleVersion" => "1" }.to_plist
  end
  MuntathirRelease.define_singleton_method(:wait_for_uploaded_build) do |app_id, app_version, previous_ids|
    assert([app_id, app_version, previous_ids] == ["6824304362", version, ["old"]], "Upload did not snapshot pre-existing build uploads")
    build
  end
  key_env = %w[ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID].to_h { |key| [key, ENV[key]] }
  key_env.each_key { |key| ENV[key] = "offline-check" }
  begin
    check.calls.clear
    assert(check.archive_and_upload(context) == build, "Archive lane did not return the processed build")
    archive, bundle_check, export = check.calls.map(&:last)
    assert(archive.last == "archive" && bundle_check.include?("check-bundle") && export.include?("-exportArchive"), "Archive and bundle validation must precede the upload")
    assert(archive.none? { |argument| argument.start_with?("MARKETING_VERSION=", "CURRENT_PROJECT_VERSION=") }, "Archive must use manually set project versions")
    options = Plist.parse_xml(File.join(root, "build", "ReleaseExportOptions.plist"))
    assert(options["destination"] == "upload" && options["manageAppVersionAndBuildNumber"] && !options["testFlightInternalTestingOnly"], "Xcode must assign the build number during direct upload")
  ensure
    key_env.each { |key, value| ENV[key] = value }
    MuntathirRelease.send(:remove_const, :ROOT)
    MuntathirRelease.const_set(:ROOT, declared_root)
    MuntathirRelease.define_singleton_method(:run!, &local_run)
    MuntathirRelease.define_singleton_method(:wait_for_uploaded_build, &select_build)
  end
end

MuntathirRelease.define_singleton_method(:with_release_lock) { |&block| block.call }
check.define_singleton_method(:archive_and_upload) { |_| calls << [:archive_and_upload]; build }

synced_packs = 0
check.calls.clear
check.testflight_public(force: "true")
assert(synced_packs == 1, "TestFlight must sync Asset Packs")
assert(check.calls.assoc(:release_context).last == { app_store: false, force: true }, "TestFlight force did not reach the freshness check")
assert(check.calls.assoc(:run_tests).last[:destination] == [iphone], "TestFlight ran on multiple devices")
capture = check.calls.select { |name, _| name == :sh }.map(&:last).flatten.grep(/\/(?:screenshots|watch_screenshots|style)\.rb$/)
assert(capture.empty? && !check.calls.assoc(:upload_to_app_store), "TestFlight must avoid capture and App Store mutations")
beta = check.calls.assoc(:upload_to_testflight).last
assert(beta[:groups] == ["Public"] && beta[:distribute_external] && beta[:submit_beta_review], "Public beta wiring failed")
assert(beta[:distribute_only] && beta[:app_version] == build.app_version && beta[:build_number] == build.version, "Public beta must distribute only the processed build")
assert(!beta[:skip_waiting_for_build_processing] && beta[:wait_processing_timeout_duration].positive?, "Pilot must wait for beta details before distributing the processed build")
assert(beta[:localized_build_info] == notes.transform_values { |text| { whats_new: text } }, "Beta localization missing")

synced_packs = 0
synced_creatives = 0
check.calls.clear
draft_version.release_type = "MANUAL"
check.define_singleton_method(:upload_to_app_store) do |**options|
  if options[:screenshots_path]
    assert(Dir.children(options[:screenshots_path]).sort == MuntathirRelease::LOCALES.sort, "Unexpected upload locales")
  end
  calls << [:upload_to_app_store, options]
  draft_version.release_type = "AFTER_APPROVAL" if options[:automatic_release]
end
rows.replace([new_upload])
check.app_store
assert(synced_packs == 1, "App Store must sync Asset Packs")
assert(synced_creatives == 1, "App Store must sync header and search creatives")
assert(check.calls.none? { |name, _| name == :archive_and_upload }, "App Store must reuse the TestFlight build instead of uploading a new binary")
assert(MuntathirRelease.review_pack_versions == ["pack-v2"], "App Store review must attach only pack versions that differ from the live packs")
assert(check.calls.assoc(:run_tests).last[:destination] == [iphone, ipad], "App Store must test on both devices")
listing, review = check.calls.filter_map { |name, options| options if name == :upload_to_app_store }
assert(listing.fetch(:release_notes) == context.fetch(:release_notes), "App Store listing must use the bundled release notes")
assert(listing[:metadata_path] == File.join(__dir__, "metadata") &&
       File.basename(listing[:screenshots_path]).start_with?("app-store-screenshots-"),
       "App Store listing must use the platform metadata and Apple build output")
assert(listing[:automatic_release] && listing[:overwrite_screenshots] && !listing[:submit_for_review] && !listing.key?(:app_previews_path), "App Store listing upload must replace screenshots and preserve videos")
assert(review[:submit_for_review] && review[:build_number] == build.version && review[:app_version] == build.app_version, "App Store review must use the processed build")
assert([listing, review].all? { |options| options[:skip_binary_upload] && options[:skip_app_version_update] }, "Deliver must leave binary upload and version numbering to Xcode and the operator")
assert(check.calls.index { |name, _| name == :upload_to_app_store } < check.calls.rindex { |name, _| name == :upload_to_app_store }, "App Store listing must precede review submit")

%i[tests refresh_screenshots].each do |step|
  original = check.method(step)
  check.define_singleton_method(step) { |**_| raise "#{step} failed" }
  lanes = step == :tests ? %i[testflight_public app_store] : [:app_store]
  lanes.each do |lane|
    check.calls.clear
    synced_creatives = 0
    rejects("#{lane} ignored failing #{step}") { check.public_send(lane) }
    assert(check.calls.none? { |name, _| %i[archive_and_upload upload_to_app_store upload_to_testflight].include?(name) }, "Uploaded after failing #{step}")
    assert(synced_creatives.zero?, "Creative sync ran after failing #{step}")
  end
  check.define_singleton_method(step, &original)
end

check.calls.clear
synced_packs = 0
synced_creatives = 0
draft_version.release_type = "MANUAL"
validated_media = 0
MuntathirRelease.define_singleton_method(:validate_media!) { |**_| validated_media += 1 }
refresh = check.method(:refresh_screenshots)
check.define_singleton_method(:refresh_screenshots) { |**_| raise "refresh_screenshots must be skipped" }
check.app_store(force: "true", skip_tests: "true", skip_screenshots: "true")
assert(validated_media == 1, "skip_screenshots must still validate existing store and creative assets")
assert(synced_creatives == 1, "skip_screenshots must still sync creatives after listing upload")
assert(check.calls.none? { |name, _| name == :run_tests }, "skip_tests must skip regressions")
check.define_singleton_method(:refresh_screenshots, &refresh)

synced_creatives = 0
MuntathirRelease.define_singleton_method(:sync_creative_assets!) { |_| raise "creative sync failed" }
check.calls.clear
draft_version.release_type = "MANUAL"
rejects("App Store ignored failing creative sync") { check.app_store }
assert(check.calls.one? { |name, _| name == :upload_to_app_store }, "Creative failure must stop before review submit")
assert(check.calls.assoc(:upload_to_app_store).last[:submit_for_review] != true, "Review submitted after creative failure")
MuntathirRelease.define_singleton_method(:sync_creative_assets!) do |localizations|
  synced_creatives += 1
  raise "Creative sync must use the draft localizations" unless localizations == draft_localizations
end

assert(!File.exist?(File.expand_path("../../.github/workflows/apple-deploy.yml", __dir__)), "CI release workflow still exists")

if check_media
  require_relative "web_media"
  # Failed web exports must leave the last usable website assets intact.
  Dir.mktmpdir do |dir|
    destination = File.join(dir, "web")
    FileUtils.mkdir_p(destination)
    marker = File.join(destination, "existing.webp")
    File.write(marker, "previous export")
    rejects("Missing capture inputs accepted") { MuntathirRelease.export_web_media!(marketing: dir, destination: destination) }
    %w[en-US ar-SA].each do |locale|
      FileUtils.mkdir_p(File.join(dir, "raw", locale))
      screens.each do |screen|
        MuntathirRelease.run!("magick", "-size", "32x64", "xc:black", File.join(dir, "raw", locale, "iPhone 17 Pro Max-#{screen}.png"))
      end
      FileUtils.mkdir_p(File.join(dir, "previews", locale))
      File.write(File.join(dir, "previews", locale, "01-IPHONE_67-SunriseToSunset.mp4"), "unreached")
    end
    rejects("Blank captures accepted") { MuntathirRelease.export_web_media!(marketing: dir, destination: destination) }
    assert(File.read(marker) == "previous export", "Failed export replaced existing website media")
  end
end

puts "Metadata, screenshots, build selection and both manual release lanes passed offline checks."
