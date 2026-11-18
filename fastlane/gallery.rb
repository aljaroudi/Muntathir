require "fileutils"
require "tmpdir"

# Stage alongside the destination so a failed render can never replace a complete gallery.
def replace_gallery(destination)
  parent = File.dirname(destination)
  FileUtils.mkdir_p(parent)
  File.open(parent, "r") do |lock|
    lock.flock(File::LOCK_EX)
    Dir.mktmpdir(".gallery-", parent) do |temp|
      stage = File.join(temp, "new")
      backup = File.join(temp, "previous")
      Dir.mkdir(stage)
      yield stage
      File.rename(destination, backup) if File.directory?(destination)
      begin
        File.rename(stage, destination)
      rescue SystemCallError
        File.rename(backup, destination) if File.directory?(backup)
        raise
      end
    end
  end
end
