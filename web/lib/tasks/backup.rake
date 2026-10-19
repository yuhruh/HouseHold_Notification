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

  desc "Restore drill: decrypt an emailed backup into a scratch database and count rows (IN=… [DRILL_DATABASE_URL=…])"
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
    %w[households users memberships categories records].each do |table|
      puts format("%-12s %d", table, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}"))
    end
    puts "Restore drill OK: #{target}"
  end
end
