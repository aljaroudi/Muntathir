require_relative "support"
require_relative "../gallery"

# frameit has no Mac frames, so each window capture gets rounded corners and a soft shadow,
# then the shared compositor adds the gradient, brand and localized headline at 2880×1800.
Dir.chdir(MuntathirRelease::ROOT)
root = File.expand_path("build/marketing")
locales = MuntathirRelease.capture_locales(ARGV[0])
config_path = File.join(__dir__, "marketing/screenshots.json")
width, height = MuntathirRelease::MAC_SCREENSHOT_SIZE
FileUtils.mkdir_p("#{root}/tools")
compositor = "#{root}/tools/compose"
MuntathirRelease.run!("xcrun", "swiftc", File.join(__dir__, "marketing/compose.swift"), "-o", compositor,
                      "-module-cache-path", "#{root}/tools/module-cache")
locales.each do |locale|
  replace_gallery("#{root}/mac/store/#{locale}") do |gallery|
    stage = "#{root}/mac/frames/#{locale}"
    FileUtils.rm_rf(stage)
    FileUtils.mkdir_p(stage)
    MuntathirRelease::MAC_SCREENS.each do |screen|
      name = "Mac-#{screen}.png"
      raw = "#{root}/mac/raw/#{locale}/#{name}"
      raise "Missing capture for #{locale}/#{name}. Run just lane ios mac_screenshots first." unless File.file?(raw)

      MuntathirRelease.validate_capture!(raw)
      w, h = MuntathirRelease.run!("magick", "identify", "-format", "%w %h", raw).split.map(&:to_i)
      # The window includes its title bar, so it is a little taller than the 16:10 content.
      raise "Unexpected Mac capture size #{w}x#{h} for #{locale}/#{name}; expected a landscape window" unless w > h

      # macOS 26 windows use a 26 pt corner radius; the 2560 px capture is a 1280 pt window at 2x.
      radius = (w / 2560.0 * 26 * 2).round
      framed = File.join(stage, name)
      MuntathirRelease.run!("magick", raw,
                            "(", "-size", "#{w}x#{h}", "xc:black", "-fill", "white",
                            "-draw", "roundrectangle 0,0 #{w - 1},#{h - 1} #{radius},#{radius}", ")",
                            "-alpha", "off", "-compose", "CopyOpacity", "-composite",
                            "(", "+clone", "-background", "black", "-shadow", "45x#{(w / 64.0).round}+0+#{(w / 128.0).round}", ")",
                            "+swap", "-background", "none", "-compose", "over", "-layers", "merge", "+repage", framed)
      output = File.join(gallery, name)
      MuntathirRelease.run!(compositor, framed, output, width, height, locale, screen, "desktop", config_path)
      MuntathirRelease.run!("magick", output, "-alpha", "remove", "-alpha", "off", output)
      actual = MuntathirRelease.run!("magick", "identify", "-format", "%wx%h %[channels]", output)
      raise "Invalid styled export: #{actual}" unless actual.start_with?("#{width}x#{height}") && !actual.include?("rgba")

      puts "Styled #{locale}/#{name}"
    end
  end
end
store = File.join(root, "mac/store")
puts "STYLE COMPLETE"
puts "Styled Mac screenshots: #{store}"
locales.each { |locale| puts "  #{store}/#{locale}/" }
