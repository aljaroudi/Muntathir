require "json"
require "net/http"
require "digest"
require "base64"
require "tmpdir"

module MuntathirRelease
  REQUIRED_ASSET_PACKS = %w[hadith supplications quran-translations rulings-v2].freeze

  class << self
    attr_accessor :review_pack_versions
  end

  module ReviewAssetPacks
    def submit_for_review(client: nil)
      MuntathirRelease.review_pack_versions.each { |version_id| MuntathirRelease.post_review_item(id, version_id) }
      super
    end
  end

  def self.asset_pack_rows(path)
    rows = []
    while path
      page = asset_pack_request(path)
      rows.concat(page.fetch("data"))
      path = page.dig("links", "next")
    end
    rows
  end

  def self.archive_current?(manifest_path, archive)
    return false unless File.file?(archive)

    manifest = JSON.parse(File.read(manifest_path))
    Dir.mktmpdir("muntathir-asset") do |directory|
      run!("xcrun", "aa", "extract", "-i", archive, "-d", directory)
      archived = JSON.parse(File.read(File.join(directory, "Manifest.json")))
      # ba-package stores platforms as a set, so their order varies between runs.
      ordered = ->(pack) { pack.merge("platforms" => pack.fetch("platforms", []).sort) }
      return false unless ordered.call(archived.reject { |key, _| key == "toolsVersion" }) == ordered.call(manifest)

      root = File.expand_path(manifest.fetch("sourceRoot"), File.dirname(manifest_path))
      manifest.fetch("fileSelectors").all? do |file|
        original = File.join(root, file.fetch("fileSource"))
        packaged = File.join(directory, "Contents", file.fetch("fileDestination"))
        FileUtils.compare_file(original, packaged)
      end
    end
  end

  def self.matching_pack_version(versions, files, checksums)
    versions.find do |version|
      file = files[version.dig("relationships", "assetFile", "data", "id")]
      next false unless file

      hashes = [file.dig("attributes", "sourceFileChecksums", "file", "hash"), file.dig("attributes", "sourceFileChecksum")]
      hashes.compact.any? { |hash| checksums.include?(hash) || checksums.include?(hash.downcase) }
    end
  end

  def self.sync_asset_packs!(platforms: ["IOS"])
    directory = File.join(ROOT, "build/AssetPacks/archives")
    REQUIRED_ASSET_PACKS.map do |name|
      archive = File.join(directory, "#{name}.aar")
      manifest = File.join(ROOT, "AssetPacks/manifests", "#{name}.json")
      unless archive_current?(manifest, archive)
        content = { "quran-translations" => "quran", "rulings-v2" => "rulings" }.fetch(name, name)
        run!("python3", File.join(ROOT, "AssetPacks/assets.py"), "package", directory, "--content", content)
      end
      checksums = [Digest::SHA256.file(archive), Digest::MD5.file(archive)].flat_map do |digest|
        [digest.hexdigest, Base64.strict_encode64(digest.digest)]
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1800
      uploaded = false
      loop do
        asset = asset_pack_rows("/v1/apps/6824304362/backgroundAssets?include=appStoreVersion,externalBetaVersion&limit=200").find do |row|
          row.dig("attributes", "assetPackIdentifier") == name && !row.dig("attributes", "archived")
        end
        versions = []
        files = {}
        path = asset && "/v1/backgroundAssets/#{asset.fetch('id')}/versions?include=assetFile&limit=200"
        while path
          page = asset_pack_request(path)
          versions.concat(page.fetch("data"))
          page.fetch("included", []).each { |file| files[file.fetch("id")] = file }
          path = page.dig("links", "next")
        end
        versions.sort_by! { |version| Gem::Version.new(version.dig("attributes", "version")) }
        candidates = uploaded ? versions : versions.reject { |version| version.dig("attributes", "state") == "FAILED" }
        match = matching_pack_version(candidates.reverse, files, checksums)
        if match && match.dig("attributes", "state") == "FAILED"
          raise "Apple failed to process asset pack #{name}. Check App Store Connect before retrying."
        end
        if match && match.dig("attributes", "state") == "COMPLETE"
          if (missing = platforms - (match.dig("attributes", "platforms") || [])).any?
            raise "Processed asset pack #{name} lacks #{missing.map { |platform| PLATFORM_NAMES.fetch(platform) }.join(' and ')} support. " \
                  "Add it to the platforms in apple/AssetPacks/manifests/#{name}.json and upload a new pack version."
          end

          break { name: name, version: match.dig("attributes", "version"), version_id: match.fetch("id"),
                  store_version_id: asset.dig("relationships", "appStoreVersion", "data", "id"),
                  external_version_id: asset.dig("relationships", "externalBetaVersion", "data", "id") }
        end
        if !match && !uploaded
          FastlaneCore::UI.message("Uploading changed or missing asset pack #{name}")
          unless system("bundle", "exec", "ruby", File.join(__dir__, "asset_pack_delivery.rb"), "--upload", name)
            raise "Asset pack upload failed for #{name}. Check App Store Connect before retrying."
          end
          uploaded = true
        end
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise "Timed out processing asset pack #{name}. Check App Store Connect before retrying." if remaining <= 0

        sleep([15, remaining].min)
      end
    end
  end

  def self.post_review_item(submission_id, version_id)
    Spaceship::ConnectAPI.tunes_request_client.post("v1/reviewSubmissionItems", {
      data: {
        type: "reviewSubmissionItems",
        relationships: {
          reviewSubmission: { data: { type: "reviewSubmissions", id: submission_id } },
          backgroundAssetVersion: { data: { type: "backgroundAssetVersions", id: version_id } }
        }
      }
    })
  end

  def self.asset_pack_request(path)
    uri = URI.join("https://api.appstoreconnect.apple.com", path)
    raise "Unexpected App Store Connect URL" unless uri.scheme == "https" && uri.host == "api.appstoreconnect.apple.com"
    request = Net::HTTP::Get.new(uri)
    token = Spaceship::ConnectAPI.token
    token.refresh! if token.expired?
    request["Authorization"] = "Bearer #{token.text}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 30) { |http| http.request(request) }
    raise "Could not verify Apple-hosted asset packs (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end
end
