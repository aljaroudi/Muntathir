require "fastlane"
require "snapshot"
require_relative "support"

Dir.chdir(MuntathirRelease::ROOT)
devices = ARGV[0].to_s.empty? ? MuntathirRelease::DEVICES : ARGV[0].split(",")
locales = ARGV[1].to_s.empty? ? MuntathirRelease::LOCALES : ARGV[1].split(",")
raise "Unknown screenshot device or locale" unless (devices - MuntathirRelease::DEVICES).empty? && (locales - MuntathirRelease::LOCALES).empty?

# Simulator asset-pack delivery requires a separate TLS server and developer override.
# Stage identical pack inputs in this Debug capture build; Release excludes these files.
MuntathirRelease.run!("xcodebuild", "build-for-testing", "-project", "./Muntathir.xcodeproj", "-scheme", "Muntathir",
                     "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", "./build/marketing/TranslationDerivedData", "CODE_SIGNING_ALLOWED=NO")
products = File.expand_path("build/marketing/TranslationDerivedData/Build/Products")
app = File.join(products, "Debug-iphonesimulator/Muntathir.app")
raise "Missing capture app" unless File.directory?(app)
FileUtils.mkdir_p(File.join(app, "Quran"))
Dir["Muntathir/Resources/Quran/*.db"].each { |source| FileUtils.cp(source, File.join(app, "Quran", File.basename(source))) }

def capture(devices, locales, os, compact = false)
  options = {
    project: "./Muntathir.xcodeproj", scheme: "Muntathir", configuration: "Debug", devices: devices, languages: locales, ios_version: os,
    only_testing: ["MuntathirUITests/MarketingScreenshotTests"], output_directory: "./build/marketing/raw", buildlog_path: "./build/logs/localized-snapshot",
    derived_data_path: "./build/marketing/TranslationDerivedData", test_without_building: true, skip_open_summary: true, concurrent_simulators: false,
    xcargs: "-parallel-testing-enabled NO -collect-test-diagnostics never", number_of_retries: 0, stop_after_first_error: true,
    clear_previous_screenshots: false, reinstall_app: true, app_identifier: "com.aljaroudi.Muntathir", override_status_bar: true,
    override_status_bar_arguments: "--time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100",
    launch_arguments: compact ? ["--marketing-compact"] : [""],
  }
  Snapshot.config = FastlaneCore::Configuration.create(Snapshot::Options.available_options, options)
  Snapshot::Runner.new.work
end

standard = devices - ["iPhone Duo"]
capture(standard, locales, ENV.fetch("SCREENSHOT_IOS_VERSION", "27.0")) unless standard.empty?
if devices.include?("iPhone Duo")
  compact = locales & %w[ja ru ur-PK]
  regular = locales - compact
  capture(["iPhone Duo"], regular, "27.1") unless regular.empty?
  capture(["iPhone Duo"], compact, "27.1", true) unless compact.empty?
end
puts "CAPTURE COMPLETE"
