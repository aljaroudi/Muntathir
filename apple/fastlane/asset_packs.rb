require "json"
require "net/http"

module MuntathirRelease
  def self.app_store_asset_gate?(release, live_version)
    (release == true || release == "true") && !live_version.nil?
  end

  def self.validate_asset_packs!(release: false, get: method(:asset_pack_request))
    relation = release ? "appStoreVersion" : "externalBetaVersion"
    path = "/v1/apps/6824304362/backgroundAssets?include=#{relation}&limit=200"
    assets = []
    versions = {}
    while path
      page = get.call(path)
      assets.concat(page.fetch("data"))
      page.fetch("included", []).each { |version| versions[version.fetch("id")] = version }
      path = page.dig("links", "next")
    end
    expected = Dir[File.join(__dir__, "../AssetPacks/manifests/*.json")].map { |file| JSON.parse(File.read(file)).fetch("assetPackID") }
    raise "Expected 13 Quran asset packs" unless expected.size == 13
    missing = expected.reject do |identifier|
      asset = assets.find { |item| item.dig("attributes", "assetPackIdentifier") == identifier && !item.dig("attributes", "archived") }
      version_id = asset&.dig("relationships", relation, "data", "id")
      version = versions[version_id]
      version && version.dig("attributes", "platforms")&.include?("IOS")
    end
    unless missing.empty?
      raise "Quran packs unavailable for #{release ? 'App Store' : 'external TestFlight'}: #{missing.join(', ')}. " \
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
