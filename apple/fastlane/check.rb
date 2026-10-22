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
check.screenshots
captures = check.calls.select { |name, _| name == :capture_screenshots }.map(&:last)
assert(captures.size == 2, "Expected separate runtime passes")
assert(captures.last[:devices] == ["iPhone Duo"] && captures.last[:ios_version] == "27.1", "Duo runtime mismatch")
assert(captures.last[:clear_previous_screenshots] == false, "Duo pass would delete standard captures")
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
check.release
release = check.calls.find { |name, _| name == :upload_to_app_store }.last
assert(release[:submit_for_review] && release[:automatic_release] == false, "Release must submit with manual publication")
assert(release[:overwrite_screenshots] == false && release[:overwrite_preview_videos] == false, "Existing assets must not be deleted")
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
