require_relative "support"
require "frameit"

Dir.chdir(MuntathirRelease::ROOT)
root = File.expand_path("build/marketing")
config_path = File.expand_path("fastlane/marketing/screenshots.json")
screens = MuntathirRelease::SCREENSHOTS.fetch("screens")
raw = MuntathirRelease::LOCALES.flat_map { |locale| Dir.glob("#{root}/raw/#{locale}/*.png") }.reject { |p| p.include?("_framed") }
raise "No raw screenshots. Run bundle exec fastlane screenshots first." if raw.empty?
FileUtils.mkdir_p("#{root}/tools")
compositor = "#{root}/tools/compose"
MuntathirRelease.run!("xcrun", "swiftc", "fastlane/marketing/compose.swift", "-o", compositor,
                      "-module-cache-path", "#{root}/tools/module-cache")
MuntathirRelease::LOCALES.each do |locale|
  inputs = raw.select { |p| p.include?("/#{locale}/") }
  MuntathirRelease::DEVICES.each do |device|
    selected = screens.map do |screen|
      inputs.find { |path| File.basename(path) == "#{device}-#{screen}.png" } || raise("Missing capture for #{locale}/#{device}/#{screen}")
    end
    Dir.glob("#{root}/store/#{locale}/#{device}-*.png").each do |path|
      FileUtils.rm_f(path) unless selected.any? { |input| File.basename(input) == File.basename(path) }
    end
    ipad = device.start_with?("iPad")
    duo = device == "iPhone Duo"
    stage = "#{root}/frames/#{locale}/#{duo ? 'Duo' : (ipad ? 'iPad' : 'iPhone')}"
    FileUtils.rm_rf(stage)
    FileUtils.mkdir_p(stage)
    selected.each do |path|
      destination = File.join(stage, File.basename(path))
      if ipad
        # frameit has a 12.9-inch bezel; fit the 13-inch capture without stretching the UI.
        MuntathirRelease.run!("magick", path, "-resize", "2048x2732", "-gravity", "center", "-background", "#000000", "-extent", "2048x2732", destination)
      else
        FileUtils.cp(path, destination)
      end
    end
    type = ipad ? Frameit::Devices::IPAD_PRO_12_9_4 : Frameit::Devices::IPHONE_17_PRO_MAX
    unless duo
      Frameit.config = FastlaneCore::Configuration.create(Frameit::Options.available_options,
                                                        force_device_type: type.formatted_name_without_apple)
      Frameit::Runner.new.run(stage)
    end
    selected.zip(screens).each do |path, key|
      name = File.basename(path)
      framed = duo ? File.join(stage, name) : File.join(stage, name.sub(/\.png\z/, "_framed.png"))
      raise "frameit did not create #{framed}" unless File.file?(framed)
      output = "#{root}/store/#{locale}/#{name}"
      FileUtils.mkdir_p(File.dirname(output))
      size = if duo
        MuntathirRelease.run!("magick", "identify", "-format", "%w %h", path).split.map(&:to_i).tap do |dimensions|
          raise "Unexpected Duo screenshot dimensions: #{dimensions}" unless [[1398, 2034], [2007, 2853], [2034, 1398], [2853, 2007]].include?(dimensions)
        end
      else
        ipad ? [2064, 2752] : [1320, 2868]
      end
      MuntathirRelease.run!(compositor, framed, output, *size, locale, key, duo ? "duo" : (ipad ? "tablet" : "phone"), config_path)
      MuntathirRelease.run!("magick", output, "-alpha", "remove", "-alpha", "off", output)
      actual = MuntathirRelease.run!("magick", "identify", "-format", "%wx%h %[channels]", output)
      raise "Invalid styled export: #{actual}" unless actual.start_with?(size.join("x")) && !actual.include?("rgba")
      puts "Styled #{locale}/#{name}"
    end
  end
end
