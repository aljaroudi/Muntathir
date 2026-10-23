# Uses the existing release credentials; never prints key contents or signs into the GUI.
require "dotenv"
Dotenv.load(ENV.fetch("MUNTATHIR_FASTLANE_ENV_FILE", File.expand_path("~/.config/muntathir/fastlane.env")))

mode = ARGV.shift || "--list"
abort "Usage: ruby fastlane/asset_pack_delivery.rb [--list|--upload]" unless %w[--list --upload].include?(mode) && ARGV.empty?
root = File.expand_path("..", __dir__)
altool = "/Applications/Transporter.app/Contents/Frameworks/ContentDelivery.framework/Versions/A/Resources/altool"
abort "Install Apple's Transporter app first" unless File.executable?(altool)
%w[ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH].each { |key| abort "Missing #{key} in release credentials" if ENV[key].to_s.empty? }
key_path = File.expand_path(ENV.fetch("ASC_KEY_PATH"))
abort "Configured App Store Connect key file is missing" unless File.file?(key_path)
auth = ["--api-key", ENV.fetch("ASC_KEY_ID"), "--api-issuer", ENV.fetch("ASC_ISSUER_ID"), "--p8-file-path", key_path]
if mode == "--upload"
  abort "Asset manifest validation failed" unless system("python3", File.join(root, "AssetPacks/assets.py"), "validate")
  manifests = Dir[File.join(root, "AssetPacks/manifests/*.json")].sort
  archives = manifests.map { |file| File.join(root, "build/AssetPacks", File.basename(file, ".json") + ".aar") }
  abort "Run python3 apple/AssetPacks/assets.py package first" unless archives.size == 13 && archives.all? { |file| File.file?(file) }
  archives.each do |file|
    puts "Uploading #{File.basename(file)} to Muntathir (6824304362)"
    abort "Upload failed; inspect the preceding Apple error before retrying" unless system(altool, "--upload-asset-pack", file, "--apple-id", "6824304362", *auth)
  end
end
abort "Could not list Apple's received asset packs" unless system(altool, "--list-asset-packs", "--apple-id", "6824304362", *auth)
