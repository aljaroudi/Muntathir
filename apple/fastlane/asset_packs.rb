require "json"
require "net/http"

module MuntathirRelease
  REQUIRED_ASSET_PACKS = %w[hadith quran-translations].freeze

  module ReviewAssetPacks
    def submit_for_review(client: nil)
      MuntathirRelease.attach_unreleased_asset_packs!(id)
      super
    end
  end

  def self.attach_unreleased_asset_packs!(submission_id, get: method(:asset_pack_request), post: method(:post_review_item))
    assets = get.call("/v1/apps/6824304362/backgroundAssets?include=appStoreVersion&limit=200").fetch("data")
    versions = REQUIRED_ASSET_PACKS.filter_map do |identifier|
      asset = assets.find { |item| item.dig("attributes", "assetPackIdentifier") == identifier && !item.dig("attributes", "archived") }
      raise "Missing required asset pack: #{identifier}" unless asset
      next if asset.dig("relationships", "appStoreVersion", "data", "id")
      candidates = get.call("/v1/backgroundAssets/#{asset.fetch('id')}/versions?limit=200").fetch("data")
      version = candidates.select do |candidate|
        candidate.dig("attributes", "state") == "COMPLETE" && candidate.dig("attributes", "platforms")&.include?("IOS")
      end.max_by { |candidate| Gem::Version.new(candidate.dig("attributes", "version")) }
      raise "Missing processed iOS version for #{identifier}" unless version
      version.fetch("id")
    end
    versions.each { |version_id| post.call(submission_id, version_id) }
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

  def self.app_store_asset_gate?(release, live_version)
    (release == true || release == "true") && !live_version.nil?
  end

  def self.validate_asset_packs!(release: false, review: false, get: method(:asset_pack_request))
    relation = release ? "appStoreVersion" : "externalBetaVersion"
    path = review ? "/v1/apps/6824304362/backgroundAssets?limit=200" : "/v1/apps/6824304362/backgroundAssets?include=#{relation}&limit=200"
    assets = []
    versions = {}
    while path
      page = get.call(path)
      assets.concat(page.fetch("data"))
      page.fetch("included", []).each { |version| versions[version.fetch("id")] = version }
      path = page.dig("links", "next")
    end
    # Both libraries use Apple-hosted on-demand delivery.
    missing = REQUIRED_ASSET_PACKS.reject do |identifier|
      asset = assets.find { |item| item.dig("attributes", "assetPackIdentifier") == identifier && !item.dig("attributes", "archived") }
      if review
        candidates = asset ? get.call("/v1/backgroundAssets/#{asset.fetch('id')}/versions?limit=200").fetch("data") : []
        candidates.any? do |version|
          version.dig("attributes", "state") == "COMPLETE" && version.dig("attributes", "platforms")&.include?("IOS")
        end
      else
        version_id = asset&.dig("relationships", relation, "data", "id")
        version = versions[version_id]
        version && version.dig("attributes", "platforms")&.include?("IOS")
      end
    end
    unless missing.empty?
      raise "Asset packs unavailable for #{review ? 'App Store review' : (release ? 'App Store' : 'external TestFlight')}: #{missing.join(', ')}. " \
            "Upload missing packs or submit their processed versions for review in App Store Connect."
    end
    true
  end

  def self.asset_pack_request(path)
    uri = URI.join("https://api.appstoreconnect.apple.com", path)
    raise "Unexpected App Store Connect URL" unless uri.scheme == "https" && uri.host == "api.appstoreconnect.apple.com"
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{Spaceship::ConnectAPI.token.text}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 30) { |http| http.request(request) }
    raise "Could not verify Quran asset packs (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end
end
