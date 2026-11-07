require "fastlane"
require "snapshot"
require_relative "support"

Dir.chdir(MuntathirRelease::ROOT)
devices = ARGV[0].to_s.empty? ? MuntathirRelease::DEVICES : ARGV[0].split(",")
locales = ARGV[1].to_s.empty? ? MuntathirRelease::LOCALES : ARGV[1].split(",")
raise "Unknown screenshot device or locale" unless (devices - MuntathirRelease::DEVICES).empty? && (locales - MuntathirRelease::LOCALES).empty?
capture_started = Time.now
derived_data = ENV.fetch("MUNTATHIR_SCREENSHOT_DERIVED_DATA", "./build/marketing/TranslationDerivedData")
buildlog_path = ENV.fetch("MUNTATHIR_SCREENSHOT_BUILDLOGS", "./build/logs/localized-snapshot")

# Capture runs stage local assets without depending on hosted delivery.
# Stage identical pack inputs in this Debug capture build; Release excludes these files.
MuntathirRelease.run!("xcodebuild", "build-for-testing", "-project", "./Muntathir.xcodeproj", "-scheme", "Muntathir",
                     "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived_data, "CODE_SIGNING_ALLOWED=NO")
products = File.expand_path(File.join(derived_data, "Build/Products"))
app = File.join(products, "Debug-iphonesimulator/Muntathir.app")
raise "Missing capture app" unless File.directory?(app)
# Snapshot runs only UI tests. Avoid installing the second full corpus in the unit-test bundle.
FileUtils.rm_rf(File.join(app, "PlugIns/MuntathirTests.xctest"))
MuntathirRelease.run!("python3", "AssetPacks/assets.py", "validate", "--content", "all")
FileUtils.mkdir_p(File.join(app, "Hadith"))
FileUtils.cp("../build/hadith/dist/hadith.db", File.join(app, "Hadith/hadith.db"))
FileUtils.mkdir_p(File.join(app, "MarketingQuran"))
Dir.glob("Muntathir/Resources/Quran/*.db").reject { |path| %w[quran.db en.qarai.db].include?(File.basename(path)) }.each do |path|
  FileUtils.cp(path, File.join(app, "MarketingQuran", File.basename(path)))
end

def capture(devices, locales, os, derived_data, buildlog_path, compact = false)
  options = {
    project: "./Muntathir.xcodeproj", scheme: "Muntathir", configuration: "Debug", devices: devices, languages: locales, ios_version: os,
    only_testing: ["MuntathirUITests/MarketingScreenshotTests"], output_directory: "./build/marketing/raw", buildlog_path: buildlog_path,
    derived_data_path: derived_data, test_without_building: true, skip_open_summary: true, concurrent_simulators: true,
    xcargs: "-parallel-testing-enabled NO -collect-test-diagnostics never", number_of_retries: 1, stop_after_first_error: true,
    clear_previous_screenshots: false, reinstall_app: false, app_identifier: "com.aljaroudi.Muntathir", override_status_bar: true,
    override_status_bar_arguments: "--time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100",
    launch_arguments: compact ? ["--marketing-compact"] : [""],
  }
  Snapshot.config = FastlaneCore::Configuration.create(Snapshot::Options.available_options, options)
  Snapshot::Runner.new.work
end

standard = devices - ["iPhone Duo"]
capture(standard, locales, ENV.fetch("SCREENSHOT_IOS_VERSION", "27.0"), derived_data, buildlog_path) unless standard.empty?
if devices.include?("iPhone Duo")
  compact = locales & %w[ja ru ur-PK]
  regular = locales - compact
  capture(["iPhone Duo"], regular, ENV.fetch("SCREENSHOT_DUO_IOS_VERSION", "27.2"), derived_data, buildlog_path) unless regular.empty?
  capture(["iPhone Duo"], compact, ENV.fetch("SCREENSHOT_DUO_IOS_VERSION", "27.2"), derived_data, buildlog_path, true) unless compact.empty?
end
screens = JSON.parse(File.read("fastlane/marketing/headlines.json")).fetch("en-US").keys
missing = devices.product(locales, screens).reject do |device, locale, screen|
  path = "build/marketing/raw/#{locale}/#{device}-#{screen}.png"
  File.file?(path) && File.mtime(path) >= capture_started
end
raise "Screenshots not regenerated: #{missing.map { |device, locale, screen| "#{locale}/#{device}-#{screen}" }.join(', ')}" unless missing.empty?
if File.expand_path(derived_data) == File.join(MuntathirRelease::ROOT, "build/marketing/TranslationDerivedData")
  MuntathirRelease.cleanup_build_artifacts!(paths: ["build/marketing/TranslationDerivedData"])
end
puts "CAPTURE COMPLETE"
