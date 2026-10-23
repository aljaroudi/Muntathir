require_relative "support"
require "timeout"
$stdout.sync = true

Dir.chdir(MuntathirRelease::ROOT)
root = File.expand_path("build/marketing")
all_devices = JSON.parse(MuntathirRelease.run!("xcrun", "simctl", "list", "devices", "available", "--json")).fetch("devices")
names = ARGV.empty? ? MuntathirRelease::DEVICES : ARGV
raise "Unknown capture device" unless (names - MuntathirRelease::DEVICES).empty?
names.each do |name|
  version = name == "iPhone Duo" ? "27.1" : ENV.fetch("SCREENSHOT_IOS_VERSION", "27.0")
  runtime = "com.apple.CoreSimulator.SimRuntime.iOS-#{version.tr('.', '-')}"
  devices = all_devices.fetch(runtime) { raise "Install iOS #{version} in Xcode." }
  device = devices.find { |d| d["name"] == name && d["state"] == "Shutdown" } || devices.find { |d| d["name"] == name }
  raise "Missing simulator #{name}" unless device
  id = device.fetch("udid")
  was_booted = device["state"] == "Booted"
  begin
    MuntathirRelease.run!("xcrun", "simctl", "boot", id) unless was_booted
    MuntathirRelease.run!("xcrun", "simctl", "bootstatus", id, "-b")
    derived_data = "#{root}/PreviewDerivedData/#{id}"
    puts "Building simulator capture app for #{name}"
    MuntathirRelease.run!("xcodebuild", "-project", "Muntathir.xcodeproj", "-scheme", "Muntathir", "-configuration", "Debug",
                         "-destination", "platform=iOS Simulator,id=#{id}", "-derivedDataPath", derived_data, "CODE_SIGNING_ALLOWED=NO", "build")
    MuntathirRelease.run!("xcrun", "simctl", "install", id, "#{derived_data}/Build/Products/Debug-iphonesimulator/Muntathir.app")
    MuntathirRelease.run!("xcrun", "simctl", "status_bar", id, "override", "--time", "9:41", "--dataNetwork", "wifi",
                         "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged", "--batteryLevel", "100")
    MuntathirRelease::LOCALES.each do |locale|
      ipad = name.start_with?("iPad")
      duo = name == "iPhone Duo"
      folder = "#{root}/#{duo ? 'duo-previews' : 'previews'}/#{locale}"
      FileUtils.mkdir_p(folder)
      recording = "#{root}/#{locale}-#{duo ? 'duo' : (ipad ? 'ipad' : 'iphone')}-recording.mov"
      FileUtils.rm_f(recording)
      puts "Recording #{locale}/#{name}: sunrise through sunset"
      begins_at = Time.now.to_f + 10
      MuntathirRelease.run!("xcrun", "simctl", "launch", "--terminate-running-process", id, "com.aljaroudi.Muntathir",
                           "--ui-testing", "--ui-testing-mecca", "--marketing-capture", "--sky-date", "2026-10-21T03:19:00Z",
                           "--sky-end", "2026-10-21T14:52:00Z", "--sky-duration", "15", "--sky-begins-at", begins_at,
                           "--ui-testing-weather", "--weather-condition", "clear",
                           "-AppleLanguages", "(#{locale})", "-AppleLocale", locale.tr('-', '_'), "-AppleInterfaceStyle", "Light")
      log = "#{recording}.log"
      record_command = ["xcrun", "simctl", "io", id, "recordVideo", "--codec=h264"]
      record_command << "--display=primary" if duo
      recorder = Process.spawn(*record_command, recording, out: log, err: [:child, :out])
      begin
        Timeout.timeout(15) do
          sleep(0.1) until File.exist?(log) && File.read(log).include?("Recording started")
        end
        recorded_at = Time.now.to_f
        raise "App launch took too long to record sunrise; retry previews" if recorded_at >= begins_at
        sleep([begins_at + 16 - Time.now.to_f, 0].max)
      ensure
        Process.kill("INT", recorder) rescue Errno::ESRCH
        Process.wait(recorder)
      end
      type = duo ? "IPHONE_DUO" : (ipad ? "IPAD_PRO_3GEN_129" : "IPHONE_67")
      output = "#{folder}/01-#{type}-SunriseToSunset.mp4"
      size = ipad ? [1200, 1600] : [886, 1920]
      MuntathirRelease.run!("ffmpeg", "-y", "-ss", (begins_at - recorded_at).round(3), "-i", recording,
                           "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
                           "-t", "15", "-vf", MuntathirRelease.preview_filter(size, duo: duo),
                           "-r", "30", "-c:v", "libx264", "-b:v", "10M", "-pix_fmt", "yuv420p",
                           "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", output)
      MuntathirRelease.validate_video!(output, size)
      [0, 7.5, 14.9].each_with_index do |time, index|
        frame = "#{folder}/#{type}-qa-#{index}.png"
        MuntathirRelease.run!("ffmpeg", "-y", "-ss", time, "-i", output, "-frames:v", "1", frame)
        content_crop = duo ? ["-gravity", "center", "-crop", "80%x50%+0+0", "+repage"] : []
        brightness = MuntathirRelease.run!("magick", frame, *content_crop, "-format", "%[fx:mean]", "info:").to_f
        raise "Blank simulator display captured for #{name}; inspect #{frame}" if brightness < 0.01
      end
      puts "Validated #{output}"
    end
  ensure
    system("xcrun", "simctl", "terminate", id, "com.aljaroudi.Muntathir", out: File::NULL, err: File::NULL)
    system("xcrun", "simctl", "status_bar", id, "clear")
    system("xcrun", "simctl", "shutdown", id) unless was_booted
  end
end
