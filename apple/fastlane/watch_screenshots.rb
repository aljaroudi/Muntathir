require_relative "support"
require "base64"

Dir.chdir(MuntathirRelease::ROOT)
root = File.expand_path("build/marketing")
devices = JSON.parse(MuntathirRelease.run!("xcrun", "simctl", "list", "devices", "available", "--json")).fetch("devices").values.flatten
watch = devices.find { |d| d["name"] == "Apple Watch Series 12 (46mm)" && d["state"] == "Shutdown" }
raise "Install and shut down an Apple Watch Series 12 (46mm) simulator for capture" unless watch
id = watch.fetch("udid")
bundle = "com.aljaroudi.Muntathir.watchkitapp"
preferences = nil
original_preferences = nil
begin
  MuntathirRelease.run!("xcodebuild", "-project", "Muntathir.xcodeproj", "-scheme", "MuntathirWatch", "-configuration", "Debug",
                       "-destination", "platform=watchOS Simulator,id=#{id}", "-derivedDataPath", "build/WatchCapture", "build")
  MuntathirRelease.run!("xcrun", "simctl", "boot", id)
  MuntathirRelease.run!("xcrun", "simctl", "bootstatus", id, "-b")
  MuntathirRelease.run!("xcrun", "simctl", "install", id, "build/WatchCapture/Build/Products/Debug-watchsimulator/MuntathirWatch.app")
  MuntathirRelease.run!("xcrun", "simctl", "launch", "--terminate-running-process", id, bundle)
  sleep(3)
  MuntathirRelease.run!("xcrun", "simctl", "terminate", id, bundle)
  groups = MuntathirRelease.run!("xcrun", "simctl", "get_app_container", id, bundle, "groups")
  group = groups.lines.find { |line| line.start_with?("group.com.aljaroudi.Muntathir\t") }&.split("\t", 2)&.last&.strip
  raise "Watch App Group container missing" unless group
  preferences = File.join(group, "Library/Preferences/group.com.aljaroudi.Muntathir.plist")
  original_preferences = File.binread(preferences) if File.file?(preferences)
  MuntathirRelease.run!("xcrun", "simctl", "shutdown", id)
  settings = { version: 1, prayers: { location: { latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh" },
                                     method: "tehran", hiddenPrayers: %w[imsak sunrise asr isha midnight], imsakMinutes: 10 },
               calendar: { timeZoneID: "Asia/Riyadh", manual: [], confirmed: [] } }
  # Seed the real connectivity cache; no capture-only Watch UI or Release changes.
  FileUtils.mkdir_p(File.dirname(preferences))
  MuntathirRelease.run!("/usr/libexec/PlistBuddy", "-c", "Clear dict", preferences)
  payload = Base64.strict_encode64(JSON.generate(settings))
  File.write(preferences, %(<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>watchSettings.v1</key><data>#{payload}</data></dict></plist>))
  MuntathirRelease.run!("xcrun", "simctl", "boot", id)
  MuntathirRelease.run!("xcrun", "simctl", "bootstatus", id, "-b")
  MuntathirRelease::LOCALES.each do |locale|
    MuntathirRelease.run!("xcrun", "simctl", "launch", "--terminate-running-process", id, bundle,
                         "-AppleLanguages", "(#{locale})", "-AppleLocale", locale.tr("-", "_"))
    sleep(5)
    raw = "#{root}/watch/#{locale}/AppleWatch-PrayerTimes.png"
    FileUtils.mkdir_p(File.dirname(raw))
    loaded = false
    6.times do
      MuntathirRelease.run!("xcrun", "simctl", "io", id, "screenshot", raw)
      brightness = MuntathirRelease.run!("magick", raw, "-crop", "416x350+0+100", "-format", "%[fx:mean]", "info:").to_f
      loaded = brightness > 0.03
      break if loaded
      sleep(3)
    end
    raise "Watch prayer screen is still loading: #{locale}" unless loaded
    dimensions = MuntathirRelease.run!("magick", "identify", "-format", "%wx%h", raw)
    raise "Unexpected Watch screenshot dimensions: #{dimensions}" unless dimensions == "416x496"
    output = "#{root}/store/#{locale}/Apple Watch Series 12 (46mm)-01-PrayerTimes.png"
    FileUtils.mkdir_p(File.dirname(output))
    MuntathirRelease.run!("magick", raw, "-alpha", "remove", "-alpha", "off", output)
    puts "Captured Watch: #{locale}"
  end
ensure
  system("xcrun", "simctl", "terminate", id, bundle, out: File::NULL, err: File::NULL)
  system("xcrun", "simctl", "shutdown", id, out: File::NULL, err: File::NULL)
  if preferences
    original_preferences ? File.binwrite(preferences, original_preferences) : FileUtils.rm_f(preferences)
  end
end
