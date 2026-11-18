require_relative "support"
require "frameit"
require_relative "../gallery"

Dir.chdir(MuntathirRelease::ROOT)
root = File.expand_path("build/marketing")
locales = MuntathirRelease.capture_locales(ARGV[0])
config_path = File.join(__dir__, "marketing/screenshots.json")
screens = MuntathirRelease::SCREENSHOTS.fetch("storeScreens")
raw = locales.flat_map { |locale| Dir.glob("#{root}/raw/#{locale}/*.png") }.reject { |p| p.include?("_framed") }
raise "No raw screenshots. Run just lane ios screenshots first." if raw.empty?
FileUtils.mkdir_p("#{root}/tools")
compositor = "#{root}/tools/compose"
MuntathirRelease.run!("xcrun", "swiftc", File.join(__dir__, "marketing/compose.swift"), "-o", compositor,
                      "-module-cache-path", "#{root}/tools/module-cache")
locales.each do |locale|
  inputs = raw.select { |p| p.include?("/#{locale}/") }
  replace_gallery("#{root}/store/#{locale}") do |gallery|
    watch = File.join(root, "store", locale, MuntathirRelease::WATCH_SCREENSHOT)
    FileUtils.cp(watch, gallery, preserve: true) if File.file?(watch)
    FileUtils.rm_rf("#{root}/frames/#{locale}")
    MuntathirRelease::DEVICES.each do |device|
      selected = screens.map do |screen|
        inputs.find { |path| File.basename(path) == "#{device}-#{screen}.png" } || raise("Missing capture for #{locale}/#{device}/#{screen}")
      end
      ipad = device.start_with?("iPad")
      duo = device == "iPhone Duo"
      stage = "#{root}/frames/#{locale}/#{duo ? 'Duo' : (ipad ? 'iPad' : 'iPhone')}"
      FileUtils.mkdir_p(stage)
      selected.each do |path|
        MuntathirRelease.validate_capture!(path)
        destination = File.join(stage, File.basename(path))
        if ipad
          # frameit has a 12.9-inch bezel; fit the 13-inch capture without stretching the UI.
          MuntathirRelease.run!("magick", path, "-resize", "2048x2732", "-gravity", "center", "-background", "#000000", "-extent", "2048x2732", destination)
        else
          FileUtils.cp(path, destination)
        end
      end
      duo_dimensions = MuntathirRelease.run!("magick", "identify", "-format", "%w %h", selected.first).split.map(&:to_i) if duo
      type = if duo
               case duo_dimensions
               when [1398, 2034], [2034, 1398] then Frameit::Devices::IPHONE_DUO_OUTER
               when [2007, 2853], [2853, 2007] then Frameit::Devices::IPHONE_DUO_INNER
               else raise "Unexpected Duo screenshot dimensions: #{duo_dimensions}"
               end
             elsif ipad
               Frameit::Devices::IPAD_PRO_12_9_4
             else
               Frameit::Devices::IPHONE_17_PRO_MAX
             end
      Frameit.config = FastlaneCore::Configuration.create(Frameit::Options.available_options,
                                                          force_device_type: type.formatted_name_without_apple)
      Frameit::Runner.new.run(stage)
      selected.zip(screens).each do |path, key|
        name = File.basename(path)
        framed = File.join(stage, name.sub(/\.png\z/, "_framed.png"))
        raise "frameit did not create #{framed}" unless File.file?(framed)
        output = File.join(gallery, name)
        FileUtils.mkdir_p(File.dirname(output))
        size = duo ? duo_dimensions : (ipad ? [2064, 2752] : [1320, 2868])
        MuntathirRelease.run!(compositor, framed, output, *size, locale, key, duo ? "duo" : (ipad ? "tablet" : "phone"), config_path)
        MuntathirRelease.run!("magick", output, "-alpha", "remove", "-alpha", "off", output)
        actual = MuntathirRelease.run!("magick", "identify", "-format", "%wx%h %[channels]", output)
        raise "Invalid styled export: #{actual}" unless actual.start_with?(size.join("x")) && !actual.include?("rgba")
        puts "Styled #{locale}/#{name}"
      end
    end
  end
end
creative = MuntathirRelease.render_brand_creative!(locales: locales)
store = File.join(root, "store")
puts "STYLE COMPLETE"
puts "Styled screenshots: #{store}"
locales.each { |locale| puts "  #{store}/#{locale}/" }
puts "Creative: #{creative}"
