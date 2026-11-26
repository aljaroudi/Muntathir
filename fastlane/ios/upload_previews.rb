# Replaces the App Preview videos on the editable iOS version with the ones `previews` recorded.
# Fastlane's upload_to_app_store can't (it has no Duo type and the release lane keeps videos), so this
# talks to the App Store Connect API directly. Each new video is uploaded before the old one is removed,
# so a failed run never leaves a set empty.
require_relative "support"
require "dotenv"
require "spaceship"
$stdout.sync = true

Dotenv.load(ENV.fetch("MUNTATHIR_FASTLANE_ENV_FILE", File.expand_path("~/.config/muntathir/fastlane.env")))
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("ASC_KEY_ID"), issuer_id: ENV.fetch("ASC_ISSUER_ID"), filepath: File.expand_path(ENV.fetch("ASC_KEY_PATH"))
)

marketing = File.join(MuntathirRelease::ROOT, "build/marketing")
# Store preview type → [folder, file name, canvas].
TYPES = {
  "IPHONE_67" => ["previews", "01-IPHONE_67-SunriseToSunset.mp4", [886, 1920]],
  "IPAD_PRO_3GEN_129" => ["previews", "01-IPAD_PRO_3GEN_129-SunriseToSunset.mp4", [1200, 1600]],
  "IPHONE_DUO" => ["duo-previews", "01-IPHONE_DUO-SunriseToSunset.mp4", [886, 1920]],
}.freeze

videos = MuntathirRelease::LOCALES.flat_map do |locale|
  TYPES.map do |type, (folder, name, size)|
    path = File.join(marketing, folder, locale, name)
    raise "Missing #{path}; run `just lane ios previews` (and devices:\"iPhone Duo\") first" unless File.file?(path)
    MuntathirRelease.validate_video!(path, size)
    [locale, type, path]
  end
end

app = Spaceship::ConnectAPI::App.find("com.aljaroudi.Muntathir")
raise "Muntathir not found in App Store Connect" unless app&.id == "6824304362"
version = app.get_edit_app_store_version(platform: "IOS") or raise "No editable iOS version in App Store Connect"
localizations = version.get_app_store_version_localizations.to_h { |l| [l.locale, l] }
puts "Replacing #{videos.size} previews on iOS #{version.version_string} (#{version.app_store_state})"

videos.each do |locale, type, path|
  localization = localizations[locale] or (puts("#{locale}: not on this version, skipped") || next)
  set = localization.get_app_preview_sets.find { |s| s.preview_type == type } ||
        localization.create_app_preview_set(attributes: { previewType: type })
  old = Spaceship::ConnectAPI::AppPreviewSet.get(app_preview_set_id: set.id).app_previews
  # Apple processes the video after the upload completes; the check below reports the outcome.
  Spaceship::ConnectAPI::AppPreview.create(app_preview_set_id: set.id, path: path, wait_for_processing: false)
  old.each(&:delete!)
  puts "#{locale} #{type}: uploaded #{File.basename(path)}, removed #{old.size} old"
end

# Wait (up to 30 minutes) for Apple to finish processing; report any video it rejected.
deadline = Time.now + 1800
loop do
  states = version.get_app_store_version_localizations.flat_map do |localization|
    localization.get_app_preview_sets.flat_map do |set|
      set.app_previews.map { |p| ["#{localization.locale} #{set.preview_type}", p.asset_delivery_state&.fetch("state", nil), p.asset_delivery_state&.fetch("errors", nil)] }
    end
  end
  failed = states.select { |_, state, _| state == "FAILED" }
  failed.each { |name, _, errors| puts "#{name}: processing FAILED #{errors.inspect}" }
  pending = states.reject { |_, state, _| %w[COMPLETE FAILED].include?(state) }
  extra = states.group_by(&:first).select { |_, rows| rows.size > 1 }.keys
  raise "Sets still hold more than one video: #{extra.join(', ')}" if extra.any?
  if pending.empty?
    raise "#{failed.size} previews failed processing" if failed.any?
    puts "All #{states.size} previews processed"
    break
  end
  raise "Still processing after 30 minutes: #{pending.map(&:first).join(', ')}" if Time.now > deadline
  puts "Waiting for #{pending.size} previews to process"
  sleep 30
end
