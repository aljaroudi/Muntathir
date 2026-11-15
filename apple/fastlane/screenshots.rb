require "fastlane"
require "snapshot"
require "rbconfig"
require_relative "support"

script_path = File.expand_path(__FILE__)
Dir.chdir(MuntathirRelease::ROOT)
devices = ARGV[0].to_s.empty? ? MuntathirRelease::DEVICES : ARGV[0].split(",")
locales = MuntathirRelease.capture_locales(ARGV[1])
workers = ARGV[2].to_s.empty? ? MuntathirRelease.default_screenshot_workers : ARGV[2]
raise "Unknown screenshot device" unless (devices - MuntathirRelease::DEVICES).empty?
capture_started = Time.now
derived_data = ENV.fetch("MUNTATHIR_SCREENSHOT_DERIVED_DATA", "./build/marketing/TranslationDerivedData")
buildlog_path = ENV.fetch("MUNTATHIR_SCREENSHOT_BUILDLOGS", "./build/logs/localized-snapshot")
worker = ENV["MUNTATHIR_SCREENSHOT_WORKER"]

# Capture runs stage local assets without depending on hosted delivery.
# Stage identical pack inputs in this Debug capture build; Release excludes these files.
unless worker
  MuntathirRelease.run!("xcodebuild", "build-for-testing", "-project", "./Muntathir.xcodeproj", "-scheme", "Muntathir",
                       "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived_data, "CODE_SIGNING_ALLOWED=NO")
end
products = File.expand_path(File.join(derived_data, "Build/Products"))
app = File.join(products, "Debug-iphonesimulator/Muntathir.app")
raise "Missing capture app" unless File.directory?(app)
# Snapshot runs only UI tests. Avoid installing the second full corpus in the unit-test bundle.
unless worker
  FileUtils.rm_rf(File.join(app, "PlugIns/MuntathirTests.xctest"))
  MuntathirRelease.stage_marketing_assets!(app)
end

def capture(devices, locales, os, derived_data, buildlog_path, output_directory, compact = false)
  options = {
    project: "./Muntathir.xcodeproj", scheme: "Muntathir", configuration: "Debug", devices: devices, languages: locales, ios_version: os,
    only_testing: ["MuntathirUITests/MarketingScreenshotTests"], output_directory: output_directory, buildlog_path: buildlog_path,
    derived_data_path: derived_data, test_without_building: true, skip_open_summary: true, concurrent_simulators: true,
    xcargs: "-parallel-testing-enabled NO -collect-test-diagnostics never", number_of_retries: 1, stop_after_first_error: true,
    clear_previous_screenshots: false, reinstall_app: false, app_identifier: "com.aljaroudi.Muntathir", override_status_bar: true,
    override_status_bar_arguments: "--time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100",
    launch_arguments: compact ? ["--marketing-compact"] : [""],
    # vendor/bundle ships an outdated snapshot/example SnapshotHelper that find_helper otherwise rejects.
    skip_helper_version_check: true,
  }
  Snapshot.config = FastlaneCore::Configuration.create(Snapshot::Options.available_options, options)
  Snapshot::Runner.new.work
end

screens = MuntathirRelease::SCREENSHOTS.fetch("screens")
unless worker
  Dir.glob("./build/marketing/raw/screenshots*.html").each { |path| FileUtils.rm_f(path) }
  # Drop prior captures for locales in this run so renamed/retired screens do not accumulate.
  locales.each do |locale|
    FileUtils.rm_rf("./build/marketing/raw/#{locale}")
    FileUtils.rm_rf("./build/marketing/frames/#{locale}")
  end
  commands = MuntathirRelease.capture_shards(locales, workers).each_with_index.map do |shard, index|
    worker_root = "./build/marketing/workers/#{index}"
    worker_derived_data = "#{worker_root}/DerivedData"
    FileUtils.rm_rf(worker_root)
    FileUtils.mkdir_p(worker_root)
    # Snapshot writes into DerivedData; cheap APFS clones prevent worker collisions without rebuilding.
    MuntathirRelease.run!("cp", "-cR", derived_data, worker_derived_data)
    env = { "MUNTATHIR_SCREENSHOT_WORKER" => index.to_s,
            "MUNTATHIR_SCREENSHOT_DERIVED_DATA" => worker_derived_data,
            "MUNTATHIR_SCREENSHOT_BUILDLOGS" => "./build/logs/localized-snapshot-worker-#{index}",
            "SIMULATOR_DEVICE_SET_PATH" => File.expand_path("#{worker_root}/devices") }
    [env, RbConfig.ruby, script_path, devices.join(","), shard.join(","), "1"]
  end
  MuntathirRelease.run_parallel!(*commands)
  MuntathirRelease.run!(RbConfig.ruby, File.join(File.dirname(script_path), "watch_screenshots.rb")) if ENV["MUNTATHIR_CAPTURE_WATCH"] == "1"
  MuntathirRelease.capture_shards(locales, workers).each_with_index do |shard, index|
    summary = "./build/marketing/workers/#{index}/raw/screenshots.html"
    FileUtils.cp(summary, "./build/marketing/raw/screenshots-worker-#{index + 1}.html") if File.file?(summary)
    shard.each do |locale|
      source = "./build/marketing/workers/#{index}/raw/#{locale}"
      raise "Missing worker screenshots: #{locale}" unless File.directory?(source)
      destination = "./build/marketing/raw/#{locale}"
      FileUtils.mkdir_p(destination)
      devices.product(screens).each do |device, screen|
        name = "#{device}-#{screen}.png"
        FileUtils.mv(File.join(source, name), File.join(destination, name))
      end
    end
  end
else
  # Snapshot resolves devices by name from the shared simulator service, so workers
  # must not drive the same iPhone/iPad/Duo concurrently even with per-worker DerivedData.
  output_directory = "./build/marketing/workers/#{worker}/raw"
  File.open("./build/marketing/workers/simulator.lock", "w") do |lock|
    lock.flock(File::LOCK_EX)
    MuntathirRelease.capture_passes(devices, locales).each do |pass_devices, pass_locales, runtime, compact|
      capture(pass_devices, pass_locales, runtime, derived_data, buildlog_path, output_directory, compact)
    end
  end
end
raw_root = worker ? "./build/marketing/workers/#{worker}/raw" : "./build/marketing/raw"
missing = devices.product(locales, screens).reject do |device, locale, screen|
  path = "#{raw_root}/#{locale}/#{device}-#{screen}.png"
  File.file?(path) && File.mtime(path) >= capture_started
end
raise "Screenshots not regenerated: #{missing.map { |device, locale, screen| "#{locale}/#{device}-#{screen}" }.join(', ')}" unless missing.empty?
unless worker
  paths = ["build/marketing/workers"]
  paths << "build/marketing/TranslationDerivedData" if File.expand_path(derived_data) == File.join(MuntathirRelease::ROOT, "build/marketing/TranslationDerivedData")
  MuntathirRelease.cleanup_build_artifacts!(paths: paths)
  raw = File.expand_path("./build/marketing/raw")
  puts "CAPTURE COMPLETE"
  puts "Raw screenshots: #{raw}"
  locales.each { |locale| puts "  #{raw}/#{locale}/ (#{devices.length * screens.length} PNGs)" }
  puts "Styled App Store images: run just apple-style languages=#{locales.map { |locale| MuntathirRelease::LANGUAGE_ALIASES.key(locale) || locale }.join(',')} → apple/build/marketing/store/"
end
