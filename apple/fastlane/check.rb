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
pack_ids = Dir[File.join(__dir__, "../AssetPacks/manifests/*.json")].map { |file| JSON.parse(File.read(file)).fetch("assetPackID") }
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
      %w[IPHONE_67 IPAD_PRO_3GEN_129 IPHONE_DUO].each do |type|
        folder = type == "IPHONE_DUO" ? "duo-previews" : "previews"
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
MuntathirRelease.define_singleton_method(:validate_media!) {}
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
assert(release[:submit_for_review] && release[:automatic_release] == false, "Release must submit with manual publication")
assert(release[:overwrite_screenshots] == false && release[:overwrite_preview_videos] == false, "Existing assets must not be deleted")
replacement = check.store_options(app: beta_app, replace_media: true)
assert(replacement[:overwrite_screenshots] && replacement[:overwrite_preview_videos], "Approved replacement must overwrite existing media")
manual_app = Object.new
manual_app.define_singleton_method(:get_edit_app_store_version) { |**_| Struct.new(:release_type).new("MANUAL") }
assert(check.store_options(app: manual_app)[:automatic_release].nil?, "Existing manual release must not receive a redundant write")
check.beta
beta = check.calls.find { |name, _| name == :upload_to_testflight }.last
assert(beta[:groups] == ["Public"] && beta[:distribute_external] && beta[:submit_beta_review], "Public beta wiring failed")
assert(beta[:skip_waiting_for_build_processing] == false, "Beta must wait for processing")
assert(beta[:localized_build_info].keys == MuntathirRelease::LOCALES, "Beta localization missing")
uploads_before = check.calls.count { |name, _| [:upload_to_app_store, :upload_to_testflight].include?(name) }
check.define_singleton_method(:tests) { raise "Regression suite failed" }
rejects("Beta ignored failing tests") { check.beta }
rejects("Release ignored failing tests") { check.release }
assert(check.calls.count { |name, _| [:upload_to_app_store, :upload_to_testflight].include?(name) } == uploads_before, "Uploaded after failed tests")
workflow = File.read(File.expand_path("../../.github/workflows/apple-deploy.yml", __dir__))
assert(workflow.include?("cancel-in-progress: false"), "Deployment queue must not cancel uploads")
assert(workflow.include?("head.repo.full_name == github.repository"), "Fork PR guard missing")
assert(workflow.include?("github.actor == github.repository_owner"), "Owner guard missing")
assert(workflow.include?("persist-credentials: false"), "Checkout credentials must not persist")
puts "Metadata, version selection, fail-closed validation, deployment lanes and workflow guards passed."
