require "fileutils"

module MuntathirRelease
  # Only disposable directories owned by these lanes; never global Xcode caches or release media.
  BUILD_ARTIFACTS = %w[
    build/DerivedData build/ArchiveDerivedData build/WatchCapture
    build/marketing/TranslationDerivedData build/marketing/PreviewDerivedData
    build/marketing/ReleaseCapture-phone build/marketing/ReleaseCapture-duo
  ].freeze

  def self.cleanup_build_artifacts!(root: ROOT, paths: BUILD_ARTIFACTS)
    raise "Unknown build artifact" unless (paths - BUILD_ARTIFACTS).empty?
    paths.each do |relative|
      path = File.join(root, relative)
      # Refuse redirected build directories, including symlinks in parent components.
      current = root
      relative.split("/").each do |component|
        current = File.join(current, component)
        raise "Refusing symlink: #{current}" if File.symlink?(current)
      end
      FileUtils.rm_rf(path)
    end
  end

  def self.retire_archive!(archive, symbols:)
    return unless File.directory?(archive)
    raise "Refusing symlink archive" if File.symlink?(archive) || File.symlink?(symbols)
    source = File.join(archive, "dSYMs")
    if File.directory?(source)
      FileUtils.mkdir_p(symbols)
      FileUtils.cp_r(File.join(source, "."), symbols)
    end
    # The caller has successfully exported and validated its IPA. Keep symbols for crash reports.
    FileUtils.rm_rf(archive)
  end
end
