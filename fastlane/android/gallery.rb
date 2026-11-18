require_relative "../ios/support"
require_relative "../gallery"
require "frameit"

root = File.expand_path("../..", __dir__)
metadata = File.join(__dir__, "metadata")
marketing = File.join(root, "android/build/marketing")
config = File.join(root, "fastlane/ios/marketing/screenshots.json")
scenes = MuntathirRelease::SCREENSHOTS.fetch("storeScreens")
play_locales = MuntathirRelease::SCREENSHOTS.fetch("playLocales")
available = play_locales.keys
operation, languages = ARGV
locales = languages.to_s.empty? ? available : languages.split(",").map { |s| s.strip == "en" ? "en-US" : s.strip }
raise "Unknown Play locale" unless locales.any? && locales.uniq == locales && (locales - available).empty?
run = MuntathirRelease.method(:run!)
FileUtils.mkdir_p(marketing)
if operation == "style"
  compositor = File.join(marketing, "compose")
  run.call("xcrun", "swiftc", File.join(File.dirname(config), "compose.swift"), "-o", compositor)
else
  serial = ENV.fetch("ANDROID_SERIAL") do
    devices = run.call("adb", "devices").scan(/^(emulator-\d+)\s+device$/).flatten
    raise "Set ANDROID_SERIAL to one emulator" unless devices.one?
    devices.first
  end
  raise "Select a Pixel emulator" unless serial.start_with?("emulator-")
  ENV["ANDROID_SERIAL"] = serial
  previous = run.call("adb", "shell", "wm", "size")[/Override size: (\d+x\d+)/, 1] || "reset"
  at_exit { run.call("adb", "shell", "wm", "size", previous) }
  run.call("adb", "shell", "wm", "size", "1080x2160")
  ENV["JAVA_HOME"] ||= "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  Dir.chdir(File.join(root, "android")) do
    run.call("./gradlew", ":app:assembleDebug", ":app:assembleDebugAndroidTest")
    %w[app/build/outputs/apk/debug/app-debug.apk app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk].each do |apk|
      run.call("adb", "install", "-r", "-g", "-t", apk)
    end
    Dir.mktmpdir do |tmp|
      folder = File.join(tmp, "QuranTranslations")
      Dir.mkdir(folder)
      files = Dir.glob("packs/quran_translations/src/main/assets/Quran/*.db")
      raise "Run just android-packs to stage translations" if files.empty?
      installed = files.to_h do |file|
        FileUtils.cp(file, folder)
        [File.basename(file, ".db"), File.basename(file)]
      end
      File.write(File.join(folder, "index.json"), JSON.generate(installed: installed, hasInstalled: true))
      run.call("adb", "push", folder, "/data/local/tmp/")
      run.call("adb", "shell", "run-as", "com.aljaroudi.muntathir", "cp", "-R", "/data/local/tmp/QuranTranslations", "no_backup/")
    end
    %w[hadith supplications].each do |pack|
      source = Dir.glob("packs/#{pack}/src/main/assets/*/#{pack}.db").fetch(0)
      remote = "/data/local/tmp/muntathir-#{pack}.db"
      Dir.mktmpdir do |tmp|
        prepared = File.join(tmp, "library.db")
        FileUtils.cp(source, prepared)
        run.call("sqlite3", prepared, "CREATE TABLE IF NOT EXISTS download_catalog AS SELECT * FROM collection")
        run.call("adb", "push", prepared, remote)
      end
      folder = "no_backup/Libraries/#{pack}"
      run.call("adb", "shell", "run-as", "com.aljaroudi.muntathir", "mkdir", "-p", folder)
      run.call("adb", "shell", "run-as", "com.aljaroudi.muntathir", "cp", remote, "#{folder}/library.db")
    end
  end
end
locales.each do |locale|
  language = play_locales.fetch(locale)
  raw = File.join(marketing, "raw", locale)
  if operation == "screenshots"
    remote = "/data/local/tmp/muntathir-marketing"
    replace_gallery(raw) do |stage|
      run.call("adb", "shell", "mkdir", "-p", remote)
      run.call("adb", "shell", "rm", "-f", *scenes.map { |scene| "#{remote}/#{scene}.png" })
      result = run.call("adb", "shell", "am", "instrument", "-w", "-e", "class",
                        "com.aljaroudi.muntathir.ui.MarketingScreenshotTest#storeGallery", "-e", "galleryLocale", language,
                        "com.aljaroudi.muntathir.test/com.aljaroudi.muntathir.HiltTestRunner")
      raise result unless result.include?("OK (1 test)")
      scenes.each do |scene|
        path = File.join(stage, "#{scene}.png")
        run.call("adb", "pull", "#{remote}/#{scene}.png", path)
        raise "Invalid capture: #{path}" unless run.call("magick", "identify", "-format", "%wx%h", path) == "1080x2160"
      end
    end
    next
  end
  replace_gallery(File.join(metadata, locale, "images/phoneScreenshots")) do |gallery|
    Dir.mktmpdir do |frames|
      scenes.each do |scene|
        path = File.join(raw, "#{scene}.png")
        size = run.call("magick", "identify", "-format", "%wx%h", path).strip
        raise "Expected a 1080x2160 Pixel capture: #{path}" unless size == "1080x2160"
        FileUtils.cp(path, frames)
      end
      Frameit.config = FastlaneCore::Configuration.create(Frameit::Options.available_options,
        force_device_type: Frameit::Devices::GOOGLE_PIXEL_3.formatted_name_without_apple)
      Frameit::Runner.new.run(frames)
      scenes.each do |scene|
        output = File.join(gallery, "#{scene}.png")
        run.call(compositor, File.join(frames, "#{scene}_framed.png"), output, 1080, 1920, language, scene, "phone", config)
        run.call("magick", output, "-alpha", "off", "PNG24:#{output}")
        raise "Invalid Play export" unless run.call("magick", "identify", "-format", "%wx%h %[opaque]", output).strip.downcase == "1080x1920 true"
      end
    end
  end
end
