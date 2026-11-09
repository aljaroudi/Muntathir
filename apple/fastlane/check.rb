require_relative "support"
require "tmpdir"
require "yaml"
Dir.chdir(MuntathirRelease::ROOT)

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

passes = MuntathirRelease.capture_passes(MuntathirRelease::DEVICES, %w[en-US ja])
assert(passes.map { |pass| pass[0] }.flatten.uniq.sort == MuntathirRelease::DEVICES.sort, "Capture device missing")
assert(passes.select { |pass| pass[0] == ["iPhone Duo"] }.map { |pass| [pass[1], pass[3]] } == [[["en-US"], false], [["ja"], true]], "Duo locale capture layouts changed")
assert(!MuntathirRelease::PREVIEW_DEVICES.include?("iPhone Duo"), "Unsupported preview must not block releases")

MuntathirRelease.validate_metadata!
MuntathirRelease.validate_metadata!(File.join(__dir__, "listing-drafts"), locales: ["fa"])
require "fastlane_core/languages"
assert((MuntathirRelease::LOCALES - FastlaneCore::Languages::ALL_LANGUAGES).empty?, "Unsupported App Store locale")
require "snapshot"
snapshot_config = FastlaneCore::Configuration.create(Snapshot::Options.available_options, {})
snapshot_options = FastlaneCore::ConfigurationFile.new(snapshot_config, File.join(__dir__, "Snapfile"), nil, true).options
assert(snapshot_options[:languages] == MuntathirRelease::LOCALES, "Screenshot locales must match metadata")
headlines = JSON.parse(File.read(File.join(__dir__, "marketing/headlines.json")))
assert(headlines.keys.sort == MuntathirRelease::LOCALES.sort, "Store headline locale mismatch")
assert(headlines.values.all? { |screens| screens.keys == headlines.fetch("en-US").keys && screens.values.all? { |text| !text.strip.empty? } }, "Missing localized screenshot headline")
assert(headlines.fetch("en-US").key?("05-Hadith"), "Missing Hadith screenshot")
MuntathirRelease::LOCALES.each do |locale|
  notes = File.read(File.join(__dir__, "beta_notes/#{locale}.txt")).strip
  assert((1..4000).cover?(notes.length), "Missing or oversized What to Test for #{locale}")
end
assert(MuntathirRelease.next_version("1.0.0", nil, nil) == "1.0.0", "First version changed")
assert(MuntathirRelease.next_version("1.0.0", "1.0.0", nil) == "1.0.1", "Patch increment failed")
assert(MuntathirRelease.next_version("1.0.0", "1.0.0", "1.1.0") == "1.1.0", "Pending version not reused")
assert(MuntathirRelease.next_version("2.0.0", "1.0.0", nil) == "2.0.0", "Explicit project version ignored")
rejects("Missing review contact accepted") { MuntathirRelease.required!({}, %w[email], "review") }
rejects("Invalid URL accepted") { MuntathirRelease.validate_url!("http://example.com", "support") }
MuntathirRelease.validate_url!("https://example.com/support", "support")
Dir.mktmpdir do |dir|
  FileUtils.cp_r(File.join(__dir__, "metadata", "."), dir)
  File.write(File.join(dir, "en-US", "subtitle.txt"), "x" * 31)
  rejects("Oversize subtitle accepted") { MuntathirRelease.validate_metadata!(dir) }
end

assert(!MuntathirRelease.app_store_asset_gate?(true, nil), "First submission cannot require packs already live on App Store")
assert(MuntathirRelease.app_store_asset_gate?(true, Object.new), "Existing App Store release must require live packs")
assert(!MuntathirRelease.app_store_asset_gate?(false, Object.new), "Beta must use beta pack availability")
# The release gate must reject missing packs and accept only active iOS versions.
pack_ids = %w[hadith supplications quran-translations]
page = { "data" => pack_ids.map { |id| { "attributes" => { "assetPackIdentifier" => id }, "relationships" => { "externalBetaVersion" => { "data" => { "id" => id } }, "appStoreVersion" => { "data" => { "id" => id } } } } },
         "included" => pack_ids.map { |id| { "id" => id, "attributes" => { "platforms" => ["IOS"] } } } }
assert(MuntathirRelease.validate_asset_packs!(get: ->(_) { page }), "Ready beta packs rejected")
assert(MuntathirRelease.validate_asset_packs!(release: true, get: ->(_) { page }), "Ready App Store packs rejected")
rejects("Missing asset packs accepted") { MuntathirRelease.validate_asset_packs!(get: ->(_) { { "data" => [] } }) }
review_page = Marshal.load(Marshal.dump(page))
review_page["data"].each { |asset| asset["id"] = asset["attributes"]["assetPackIdentifier"] }
review_page["included"].each { |version| version["attributes"]["state"] = "COMPLETE" }
review_get = lambda do |path|
  identifier = path[%r{/backgroundAssets/([^/]+)/versions}, 1]
  identifier ? { "data" => review_page["included"].select { |v| v["id"] == identifier } } : review_page
end
assert(MuntathirRelease.validate_asset_packs!(review: true, get: review_get), "Processed packs must not require external beta approval for first App Store review")
review_page["included"].each { |version| version["attributes"]["version"] = "1" }
review_page["data"][0]["relationships"].delete("appStoreVersion")
attached = []
MuntathirRelease.attach_unreleased_asset_packs!("draft", get: review_get, post: ->(*args) { attached << args })
assert(attached == [["draft", "hadith"]], "App Review must include the required pack that is not yet live")
review_page["included"][0]["attributes"]["state"] = "PROCESSING"
rejects("Unprocessed pack accepted for App Store review") { MuntathirRelease.validate_asset_packs!(review: true, get: review_get) }

wrong_platform = Marshal.load(Marshal.dump(page))
wrong_platform["included"][0]["attributes"]["platforms"] = ["MAC_OS"]
rejects("Non-iOS pack accepted") { MuntathirRelease.validate_asset_packs!(get: ->(_) { wrong_platform }) }

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
original_video_check = MuntathirRelease.method(:validate_video!)
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
begin
  MuntathirRelease.define_singleton_method(:validate_video!) { |*_, **_| }
  Dir.mktmpdir do |root|
    headlines = JSON.parse(File.read(File.join(__dir__, "marketing/headlines.json")))
    MuntathirRelease::LOCALES.each do |locale|
      directory = File.join(root, "build/marketing/store", locale)
      FileUtils.mkdir_p(directory)
      MuntathirRelease::DEVICES.each do |device|
        headlines.fetch(locale).each_key { |key| File.write(File.join(directory, "#{device}-#{key}.png"), "") }
      end
      File.write(File.join(directory, "Apple Watch Series 12 (46mm)-01-PrayerTimes.png"), "")
      %w[IPHONE_67 IPAD_PRO_3GEN_129].each do |type|
        folder = "previews"
        output = File.join(root, "build/marketing", folder, locale)
        FileUtils.mkdir_p(output)
        File.write(File.join(output, "01-#{type}-SunriseToSunset.mp4"), "")
      end
    end
    MuntathirRelease.validate_media!(root)
    quran = File.join(root, "build/marketing/store/en-US/iPhone 17 Pro Max-03-Quran.png")
    FileUtils.mv(quran, quran.sub("03-Quran", "99-Extra"))
    rejects("Missing Quran screenshot accepted") { MuntathirRelease.validate_media!(root) }
  end
ensure
  MuntathirRelease.define_singleton_method(:validate_video!, &original_video_check)
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
MuntathirRelease.define_singleton_method(:retire_archive!) { |*_, **_| }

# Exercise lane wiring without network access, builds, uploads, or credentials.
module UI
  def self.user_error!(message) = raise(message)
  def self.header(*) = nil
  def self.success(*) = nil
end
class LaneCheck
  attr_reader :calls
  def initialize = @calls = []
  def default_platform(*) = nil
  def desc(*) = nil
  def sh(*args) = @calls << [:sh, args]
  def platform(*) = yield
  def lane(name, &block) = define_singleton_method(name) { |options = {}| instance_exec(options, &block) }
  alias private_lane lane
  def method_missing(name, *args, **options)
    @calls << [name, options]
    return "/tmp/Muntathir.ipa" if name == :build_app
    if name == :latest_testflight_build_number
      raise "Version filter can miss equivalent 1.0/1.0.0 trains" if options.key?(:version)
      return 9
    end
    nil
  end
  def respond_to_missing?(*) = true
end
check = LaneCheck.new
check.instance_eval(File.read(File.join(__dir__, "Fastfile")), File.join(__dir__, "Fastfile"))
config = { "submission_information" => { "export_compliance_uses_encryption" => false } }
beta_app = Object.new
beta_app.define_singleton_method(:get_edit_app_store_version) { |**_| nil }
beta_app.define_singleton_method(:get_beta_app_localizations) { [Struct.new(:feedback_email).new("review@example.com")] }
draft_version = Struct.new(:version_string).new("1.0")
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
check.tests
regressions = check.calls.find { |name, _| name == :run_tests }.last
assert(regressions[:skip_testing] == ["MuntathirUITests/MarketingScreenshotTests", "MuntathirUITests/QuranScreenshotRefreshTests"], "Regression lane must exclude only marketing captures")
assert(regressions[:parallel_testing] == false, "Regression lane must serialize UI tests")
assert(regressions[:derived_data_path] == "./build/DerivedData", "Regression and marketing build caches must stay separate")
check.screenshots
capture = check.calls.reverse.find { |name, args| name == :sh && args.include?(File.join(__dir__, "screenshots.rb")) }
assert(capture, "Screenshot lane must stage local pack inputs in a Debug capture build")
check.define_singleton_method(:store) { |**_| { app: beta_app, version: "1.0.1", config: config } }
Dir.mktmpdir { |dir| rejects("Missing media accepted") { MuntathirRelease.validate_media!(dir) } }
rejects("Unconfirmed compliance accepted") { MuntathirRelease.compliance!({}) }
assert(MuntathirRelease.compliance!(config) == false, "Confirmed exemption lost")
MuntathirRelease.define_singleton_method(:validate_media!) { |**_| }
MuntathirRelease.define_singleton_method(:review_config) { config }
check.define_singleton_method(:check) {}
check.define_singleton_method(:tests) {}
check.define_singleton_method(:marketing) {}
# Build allocation must search all trains: Apple treats 1.0 and 1.0.0 as equivalent.
original_key_env = %w[ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID].to_h { |key| [key, ENV[key]] }
begin
  %w[ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID].each { |key| ENV[key] ||= "offline-check" }
  check.archive(version: "1.0")
ensure
  original_key_env.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
end
check.define_singleton_method(:archive) { |**_| { ipa: "/tmp/Muntathir.ipa", build: 10 } }
Dir.mktmpdir do |dir|
  ipa = File.join(dir, "approved.ipa")
  File.write(ipa, "archive fixture")
  check.upload_prepared(ipa: ipa)
  prepared = check.calls.reverse.find { |name, _| name == :upload_to_app_store }.last
  assert(!prepared[:submit_for_review] && !prepared[:reject_if_possible], "Approved upload must preserve the existing review draft")
  assert(prepared[:overwrite_screenshots] && prepared[:overwrite_preview_videos], "Approved upload must replace media")
  assert(prepared[:ipa] == ipa, "Approved archive must not be regenerated")
end
check.release
release = check.calls.reverse.find { |name, _| name == :upload_to_app_store }.last
assert(release[:submit_for_review] && release[:automatic_release] == true, "Default release must publish automatically after approval")
assert(release[:overwrite_screenshots] == true && release[:overwrite_preview_videos] == false, "Screenshots must be replaced while existing previews are preserved")
check.define_singleton_method(:processed_build) { |**_| Struct.new(:version).new("10") }
check.release(build: "10")
reused = check.calls.reverse.find { |name, _| name == :upload_to_app_store }.last
assert(reused[:skip_binary_upload] && reused[:build_number] == "10" && !reused.key?(:ipa), "Review should reuse the specified processed build")
replacement = check.store_options(app: beta_app, replace_media: true)
assert(replacement[:overwrite_screenshots] && replacement[:overwrite_preview_videos], "Approved replacement must overwrite existing media")
manual_app = Object.new
manual_app.define_singleton_method(:get_edit_app_store_version) { |**_| Struct.new(:release_type).new("MANUAL") }
assert(check.store_options(app: manual_app)[:automatic_release].nil?, "Existing manual release must not receive a redundant write")
assert(check.store_options(app: manual_app, automatic_release: "true")[:automatic_release] == true, "Opt-in release must switch to automatic publication")
automatic_app = Object.new
automatic_app.define_singleton_method(:get_edit_app_store_version) { |**_| Struct.new(:release_type).new("AFTER_APPROVAL") }
assert(check.store_options(app: automatic_app, automatic_release: true)[:automatic_release].nil?, "Existing automatic release must not receive a redundant write")
check.beta
beta = check.calls.find { |name, _| name == :upload_to_testflight }.last
assert(beta[:groups] == ["Public"] && beta[:distribute_external] && beta[:submit_beta_review], "Public beta wiring failed")
assert(beta[:skip_waiting_for_build_processing] == false, "Beta must wait for processing")
assert(beta[:localized_build_info].keys == MuntathirRelease::LOCALES, "Beta localization missing")
assert(beta[:changelog] == File.read(File.join(__dir__, "beta_notes/en-US.txt")).strip, "What to Test must use testing instructions")
check.define_singleton_method(:processed_build) { |**_| Struct.new(:version, :app_version).new("14", "1.0.1.0") }
check.public_beta(build: 14)
existing_beta = check.calls.reverse.find { |name, _| name == :upload_to_testflight }.last
assert(existing_beta[:distribute_only] && existing_beta[:build_number] == "14" && existing_beta[:app_version] == "1.0.1.0", "Public distribution must reuse the uploaded build train")
uploads_before = check.calls.count { |name, _| [:upload_to_app_store, :upload_to_testflight].include?(name) }
check.define_singleton_method(:tests) { raise "Regression suite failed" }
rejects("Beta ignored failing tests") { check.beta }
rejects("Release ignored failing tests") { check.release }
assert(check.calls.count { |name, _| [:upload_to_app_store, :upload_to_testflight].include?(name) } == uploads_before, "Uploaded after failed tests")
workflow = File.read(File.expand_path("../../.github/workflows/apple-deploy.yml", __dir__))
assert(workflow.include?("cancel-in-progress: false"), "Deployment queue must not cancel uploads")
assert(workflow.include?("head.repo.id == github.event.repository.id"), "Fork PR guard missing")
assert(workflow.include?("github.actor == github.repository_owner"), "Owner guard missing")
assert(workflow.include?("persist-credentials: false"), "Checkout credentials must not persist")
assert(workflow.include?("github.event.pull_request.merged && 'release' || 'beta'"), "PR and merge deployment lanes changed")
assert(workflow.include?("types: [opened, synchronize, reopened, ready_for_review, closed]"), "PR lifecycle triggers missing")
assert(!workflow.include?("    paths:"), "Deployment must run for every eligible PR")
puts "Metadata, version selection, fail-closed validation, deployment lanes and workflow guards passed."
