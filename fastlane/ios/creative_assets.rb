require "json"
require "net/http"

module MuntathirRelease
  CREATIVE_PLACEMENTS = %w[PRODUCT_PAGE_HEADER_ASSET APP_STORE_SEARCH_RESULTS_ASSET].freeze
  CREATIVE_CATEGORY = "CREATIVE_ASSETS"
  CREATIVE_FEATURE = "APP_STORE_VERSIONS"

  def self.sync_creative_assets!(localizations)
    library = creative_request("/v1/apps/6824304362/assetLibrary").dig("data", "id")
    raise "Apple returned no asset library for Muntathir" unless library

    reference = creative_request("/v1/appAssetLibraryRefData").fetch("data").fetch(0).fetch("attributes")
    group, spec_ids = creative_placement_target(reference)
    by_locale = localizations.to_h { |entry| [entry.locale, entry] }
    stamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
    LOCALES.each do |locale|
      localization = by_locale[locale]
      raise "No App Store localization for #{locale}" unless localization

      path = File.join(ROOT, "build/marketing/creative", locale, "universal.png")
      raise "Missing creative asset: #{path}" unless File.file?(path)

      image = upload_creative_image!(library, path, locale, stamp: stamp)
      unless spec_ids.include?(image.fetch("specId"))
        raise "Creative for #{locale} matched spec #{image['specId'].inspect}, expected one of #{spec_ids}"
      end

      CREATIVE_PLACEMENTS.each do |placement_type|
        replace_creative_placement!(localization.id, image.fetch("id"), placement_type, group)
      end
      FastlaneCore::UI.message("Placed header and search creatives for #{locale}")
    end
  end

  def self.creative_dimensions(spec)
    dims = spec["dimensions"] || spec
    width = dims["width"] || dims["maxWidth"] || dims["minWidth"]
    height = dims["height"] || dims["maxHeight"] || dims["minHeight"]
    [width.to_i, height.to_i]
  end

  def self.creative_placement_target(reference)
    specs = reference.fetch("imageSpecs").select do |spec|
      creative_dimensions(spec) == CREATIVE_SIZE
    end
    raise "Reference data has no #{CREATIVE_SIZE.join('×')} creative image spec" if specs.empty?

    preferred = specs.find { |spec| spec["universalAsset"] } || specs.first
    spec_id = preferred.fetch("specId") || preferred.fetch("id")
    groups = CREATIVE_PLACEMENTS.map do |placement_type|
      policy = reference.fetch("features").find { |feature| feature["featureId"] == CREATIVE_FEATURE }
                        &.fetch("placementPolicies", [])&.find { |entry| entry["placementType"] == placement_type }
      allowed = (policy || {}).fetch("groupLimits", []).flat_map { |limit| limit.fetch("groupIds", []) }
      type = reference.fetch("placementTypes").find { |entry| entry["placementTypeId"] == placement_type }
      unless type&.fetch("acceptsAssetCategories", [])&.include?(CREATIVE_CATEGORY)
        raise "Placement #{placement_type} no longer accepts #{CREATIVE_CATEGORY}"
      end
      candidates = type.fetch("specMappings", []).select { |entry| entry.fetch("specs", []).include?(spec_id) }
      candidates.select! { |entry| allowed.include?(entry["placementGroupId"]) } unless allowed.empty?
      mapping = candidates.find { |entry| entry["placementGroupId"] == "DEFAULT_PROFILE" } ||
                candidates.find { |entry| entry["placementGroupId"] == "UNIVERSAL" } ||
                candidates.first
      raise "No placement group maps #{placement_type} to #{spec_id}" unless mapping

      mapping.fetch("placementGroupId")
    end
    raise "Header and search creatives require the same placement group" unless groups.uniq.size == 1

    [groups.first, specs.filter_map { |spec| spec["specId"] || spec["id"] }]
  end

  def self.upload_creative_image!(library_id, path, locale, stamp: Time.now.utc.strftime("%Y%m%d-%H%M%S"))
    bytes = File.binread(path)
    reserved = creative_request("/v1/appAssetLibraryImages", method: :post, body: {
      data: {
        type: "appAssetLibraryImages",
        attributes: {
          fileName: File.basename(path),
          fileSize: bytes.bytesize,
          category: CREATIVE_CATEGORY,
          referenceName: "Muntathir #{locale} brand #{stamp}"
        },
        relationships: { assetLibrary: { data: { type: "appAssetLibraries", id: library_id } } }
      }
    }).fetch("data")
    upload_creative_bytes!(reserved.dig("attributes", "uploadOperations") || [], bytes)
    creative_request("/v1/appAssetLibraryImages/#{reserved.fetch('id')}", method: :patch,
                     body: { data: { type: "appAssetLibraryImages", id: reserved.fetch("id"), attributes: { uploaded: true } } })
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 300
    loop do
      image = creative_request("/v1/appAssetLibraryImages/#{reserved.fetch('id')}").fetch("data").fetch("attributes")
      return image.merge("id" => reserved.fetch("id")) if %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW ACCEPTED APPROVED].include?(image["state"])
      raise "Creative processing failed for #{locale}: #{image['state']} #{image['stateDetails']}" if %w[FAILED REJECTED ARCHIVED].include?(image["state"])

      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise "Timed out processing creative for #{locale}" if remaining <= 0

      sleep([2, remaining].min)
    end
  end

  def self.upload_creative_bytes!(operations, bytes)
    raise "Apple returned no upload operations for the creative image" if operations.empty?

    operations.each do |operation|
      uri = URI(operation.fetch("url"))
      request = Net::HTTP.const_get(operation.fetch("method").capitalize).new(uri)
      operation.fetch("requestHeaders", []).each { |header| request[header.fetch("name")] = header.fetch("value") }
      request.body = bytes.byteslice(operation.fetch("offset"), operation.fetch("length"))
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 20, read_timeout: 120) do |http|
        http.request(request)
      end
      raise "Creative upload failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
    end
  end

  def self.replace_creative_placement!(localization_id, image_id, placement_type, group)
    existing = creative_rows("/v1/appStoreVersionLocalizations/#{localization_id}/placements?filter[placementType]=#{placement_type}&limit=200")
    existing.select { |row| row.dig("attributes", "placementGroup") == group }.each do |row|
      creative_request("/v1/appAssetLibraryPlacements/#{row.fetch('id')}", method: :delete)
    end
    creative_request("/v1/appAssetLibraryPlacements", method: :post, body: {
      data: {
        type: "appAssetLibraryPlacements",
        attributes: { placementType: placement_type, placementGroup: group },
        relationships: {
          image: { data: { type: "appAssetLibraryImages", id: image_id } },
          appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: localization_id } }
        }
      }
    })
  end

  def self.creative_rows(path)
    rows = []
    while path
      page = creative_request(path)
      rows.concat(page.fetch("data"))
      path = page.dig("links", "next")
    end
    rows
  end

  def self.creative_request(path, method: :get, body: nil)
    uri = path.start_with?("http") ? URI(path) : URI.join("https://api.appstoreconnect.apple.com", path)
    raise "Unexpected App Store Connect URL" unless uri.scheme == "https" && uri.host == "api.appstoreconnect.apple.com"

    request = case method
              when :get then Net::HTTP::Get.new(uri)
              when :post then Net::HTTP::Post.new(uri)
              when :patch then Net::HTTP::Patch.new(uri)
              when :delete then Net::HTTP::Delete.new(uri)
              else raise "Unsupported creative request method: #{method}"
              end
    token = Spaceship::ConnectAPI.token
    token.refresh! if token.expired?
    request["Authorization"] = "Bearer #{token.text}"
    if body
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
    end
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) { |http| http.request(request) }
    return {} if method == :delete && response.is_a?(Net::HTTPSuccess)
    raise "Asset Library request failed (HTTP #{response.code}): #{response.body.to_s.lines.first}" unless response.is_a?(Net::HTTPSuccess)

    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  end
end
