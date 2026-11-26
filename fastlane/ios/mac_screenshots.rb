require "json"
require "tmpdir"
require_relative "support"

# fastlane snapshot only drives iOS simulators, so the Mac capture runs the MacScreenshots
# test plan once per locale and exports the Mac-<screen> attachments from each result bundle.
Dir.chdir(MuntathirRelease::ROOT)
locales = MuntathirRelease.capture_locales(ARGV[0])
screens = MuntathirRelease::MAC_SCREENS
root = File.expand_path("build/marketing/mac")
derived_data = File.join(root, "DerivedData")
results = File.join(root, "results")
logs = File.join(MuntathirRelease::ROOT, "build/logs/mac-snapshot")
capture_started = Time.now
FileUtils.rm_rf(results)
FileUtils.mkdir_p([results, logs])

def xcodebuild!(log, *arguments)
  ok = system("xcodebuild", "-project", "Muntathir.xcodeproj", "-scheme", "Muntathir", "-testPlan", "MacScreenshots",
              "-destination", "platform=macOS", "-derivedDataPath", arguments.shift, *arguments, out: log, err: log)
  raise "xcodebuild #{arguments.last} failed; see #{log}" unless ok
end

# Debug capture builds need the team's signing for the sandboxed app and its App Group.
xcodebuild!(File.join(logs, "build-for-testing.log"), derived_data, "-allowProvisioningUpdates", "build-for-testing")
app = File.join(derived_data, "Build/Products/Debug/Muntathir.app")
MuntathirRelease.stage_marketing_assets!(app, resources: File.join(app, "Contents/Resources"))
MuntathirRelease.resign_mac_app!(app)

locales.each do |locale|
  result = File.join(results, "#{locale}.xcresult")
  ENV["TEST_RUNNER_MUNTATHIR_CAPTURE_LOCALE"] = locale
  begin
    xcodebuild!(File.join(logs, "#{locale}.log"), derived_data, "-resultBundlePath", result, "test-without-building")
  ensure
    ENV.delete("TEST_RUNNER_MUNTATHIR_CAPTURE_LOCALE")
  end
  Dir.mktmpdir("mac-attachments-") do |exported|
    MuntathirRelease.run!("xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", exported)
    attachments = JSON.parse(File.read(File.join(exported, "manifest.json"))).flat_map { |test| test.fetch("attachments") }
    destination = File.join(root, "raw", locale)
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
    screens.each do |screen|
      name = "Mac-#{screen}"
      # Attachment names gain a numeric suffix; match on the name we gave them.
      attachment = attachments.find { |entry| entry.fetch("suggestedHumanReadableName").start_with?("#{name}_", "#{name}.") }
      raise "Missing Mac capture #{locale}/#{name}" unless attachment

      output = File.join(destination, "#{name}.png")
      FileUtils.cp(File.join(exported, attachment.fetch("exportedFileName")), output)
      MuntathirRelease.validate_capture!(output)
    end
  end
  puts "Captured Mac: #{locale}"
end

missing = locales.product(screens).reject do |locale, screen|
  path = File.join(root, "raw", locale, "Mac-#{screen}.png")
  File.file?(path) && File.mtime(path) >= capture_started
end
raise "Mac screenshots not regenerated: #{missing.map { |locale, screen| "#{locale}/#{screen}" }.join(', ')}" unless missing.empty?

MuntathirRelease.cleanup_build_artifacts!(paths: ["build/marketing/mac/DerivedData", "build/marketing/mac/results"])
puts "CAPTURE COMPLETE"
puts "Raw Mac screenshots: #{File.join(root, 'raw')}"
puts "Styled Mac App Store images: run just lane ios mac_style → apple/build/marketing/mac/store/"
