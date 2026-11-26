require_relative "support"
require "tmpdir"

module MuntathirRelease
  def self.export_web_media!(marketing: File.join(ROOT, "build/marketing"), destination: File.expand_path("../../web/public/marketing", __dir__))
    locales = { "en" => "en-US", "ar" => "ar-SA" }
    inputs = locales.values.flat_map do |locale|
      SCREENSHOTS.fetch("screens").map { |screen| File.join(marketing, "raw", locale, "#{DEVICES.first}-#{screen}.png") } +
        [File.join(marketing, "previews", locale, "01-IPHONE_67-SunriseToSunset.mp4")]
    end
    missing = inputs.reject { |path| File.file?(path) && File.size?(path) }
    raise "Missing web media inputs: #{missing.join(', ')}" unless missing.empty?

    FileUtils.mkdir_p(File.dirname(destination))
    Dir.mktmpdir(".marketing-", File.dirname(destination)) do |stage|
      output = File.join(stage, "output")
      manifest = {}
      locales.each do |language, locale|
        folder = File.join(output, language)
        FileUtils.mkdir_p(folder)
        arabic_names = %w[اليوم القرآن الحديث التظليلات الأدعية التسبيح الركعات النشاط التقويم القبلة]
        images = SCREENSHOTS.fetch("screens").each_with_index.map do |screen, index|
          input = File.join(marketing, "raw", locale, "#{DEVICES.first}-#{screen}.png")
          width, height = run!("magick", "identify", "-format", "%w %h", input).split.map(&:to_i)
          raise "Invalid portrait capture: #{input}" unless width.positive? && height > width
          validate_capture!(input)
          sources = [286, 572, 858].map do |size|
            filename = "#{screen}-#{size}.webp"
            path = File.join(folder, filename)
            run!("magick", input, "-resize", "#{size}x", "-strip", "-quality", "85", path)
            raise "Invalid WebP export" unless run!("magick", "identify", "-format", "%m %w", path) == "WEBP #{size}"
            "/marketing/#{language}/#{filename} #{size}w"
          end
          { id: screen, src: sources[1].split.first, srcset: sources.join(", "), width: width, height: height,
            caption: SCREENSHOTS.fetch("headlines").fetch(locale).fetch(screen),
            alt: language == "ar" ? "شاشة #{arabic_names.fetch(index)} في منتظِر" : "Muntathir #{screen.split('-', 2).last} screen" }
        end
        video = File.join(folder, "sky.webm")
        run!("ffmpeg", "-v", "error", "-y", "-i", File.join(marketing, "previews", locale, "01-IPHONE_67-SunriseToSunset.mp4"),
             "-an", "-vf", "scale=572:-2", "-c:v", "libvpx-vp9", "-crf", "35", "-b:v", "0", "-deadline", "good", "-cpu-used", "4", video)
        probe = JSON.parse(run!("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", video))
        streams = probe.fetch("streams")
        raise "Invalid WebM export" unless streams.size == 1 && streams.first.fetch("codec_name") == "vp9" &&
          streams.first.fetch("width") == 572 && (probe.fetch("format").fetch("duration").to_f - 15).abs < 0.2
        manifest[language] = { images: images, video: { src: "/marketing/#{language}/sky.webm", poster: images.first.fetch(:src),
          caption: language == "ar" ? "من الشروق إلى الغروب" : "From sunrise to sunset" } }
      end
      File.write(File.join(output, "manifest.json"), JSON.pretty_generate(manifest) + "\n")
      # Publish only after every locale has passed; restore the old export if the rename fails.
      backup = File.join(stage, "previous")
      File.rename(destination, backup) if File.exist?(destination)
      begin
        File.rename(output, destination)
      rescue StandardError
        File.rename(backup, destination) if File.exist?(backup)
        raise
      end
    end
    puts "WebP and WebM media exported to #{destination}"
  end
end

MuntathirRelease.export_web_media! if $PROGRAM_NAME == __FILE__
