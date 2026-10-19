require "io/console"

namespace :backup do
  passphrase = -> { BackupJob.passphrase.presence || $stdin.getpass("Backup passphrase: ") }

  desc "Decrypt an emailed backup (IN=household-YYYY-MM-DD.dump.enc [OUT=…dump])"
  task decrypt: :environment do
    input = ENV["IN"].presence&.then { File.expand_path(_1) } or abort "Usage: bin/rails backup:decrypt IN=path/to/household-YYYY-MM-DD.dump.enc"
    output = ENV["OUT"].presence&.then { File.expand_path(_1) } || input.delete_suffix(".enc")
    BackupJob.openssl!("-d", "-in", input, "-out", output, passphrase: passphrase.call)
    puts "Decrypted to #{output}"
    puts BackupJob.run!({}, "pg_restore", "--list", output).lines.grep(/TABLE DATA/).size.to_s + " tables with data"
  end

  desc "Restore drill: decrypt an emailed backup into a scratch database and count rows; with PHOTOS=household-photos-….tgz also check every photo file against the restored blobs (IN=… [PHOTOS=…] [DRILL_DATABASE_URL=…])"
  task restore_drill: :environment do
    input = ENV["IN"].presence&.then { File.expand_path(_1) } or abort "Usage: bin/rails backup:restore_drill IN=path/to/household-YYYY-MM-DD.dump.enc"
    target = ENV["DRILL_DATABASE_URL"].presence || "postgres:///household_restore_drill"
    name = URI(target).path.delete_prefix("/")
    abort "Refusing to restore over #{name}" if name.empty? || name == ActiveRecord::Base.connection_db_config.database
    maintenance = target.sub(%r{/[^/?]*(\?|\z)}, '/postgres\\1')
    Dir.mktmpdir("drill") do |tmp|
      dump = File.join(tmp, "drill.dump")
      BackupJob.openssl!("-d", "-in", input, "-out", dump, passphrase: passphrase.call)
      BackupJob.run!({}, "psql", maintenance, "-c", "DROP DATABASE IF EXISTS \"#{name}\"", "-c", "CREATE DATABASE \"#{name}\"")
      BackupJob.run!({}, "pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--dbname", target, dump)
    end
    ActiveRecord::Base.establish_connection(target)
    %w[households users memberships categories records active_storage_blobs].each do |table|
      puts format("%-20s %d", table, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}"))
    end
    photos = ENV["PHOTOS"].presence&.then { File.expand_path(_1) }
    check_photos(photos, ActiveRecord::Base.connection) if photos
    puts "Restore drill OK: #{target}"
  end

  # Every restored blob needs its file (Disk service layout: ab/cd/abcd…) with the same size and
  # MD5. Files without a blob are only counted: photos added after the database dump, or orphans
  # the daily sweep hasn't removed yet. Use a dump and a photo archive taken the same day.
  def check_photos(archive, connection)
    Dir.mktmpdir("drill-photos") do |root|
      BackupJob.run!({}, "tar", "xzf", archive, "-C", root)
      blobs = connection.select_rows("SELECT key, byte_size, checksum FROM active_storage_blobs WHERE service_name = 'local'")
      problems = blobs.filter_map do |key, byte_size, checksum|
        file = File.join(root, key[0, 2], key[2, 2], key)
        next "#{key}: missing" unless File.file?(file)
        next "#{key}: #{File.size(file)} bytes, expected #{byte_size}" unless File.size(file) == byte_size.to_i
        "#{key}: checksum differs" unless checksum.nil? || Digest::MD5.file(file).base64digest == checksum
      end
      keys = blobs.map(&:first).to_set
      extra = Dir.glob("??/??/*", base: root).count { |path| !keys.include?(File.basename(path)) }
      puts format("%-20s %d checked, %d without a blob", "photo files", blobs.size, extra)
      abort "Photo check failed:\n  #{problems.join("\n  ")}" if problems.any?
    end
  end
end
