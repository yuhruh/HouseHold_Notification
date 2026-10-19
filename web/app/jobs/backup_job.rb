require "open3"

# Weekly logical backup (PRD → Backups, ADR 0005 X3): a `pg_dump -Fc` on the volume, keeping the
# last KEEP, and an encrypted copy emailed to Alex as the off-Railway copy. A version mismatch or
# a failed command raises (Sentry) and pings the heartbeat's /fail.
#
# Settings: BACKUP_PASSPHRASE (or credentials backup.passphrase), BACKUP_RECIPIENT (default: the
# Gmail sender), BACKUP_HEARTBEAT_URL (optional Healthchecks.io ping URL).
class BackupJob < ApplicationJob
  queue_as :default

  KEEP = 4
  MAX_ATTACHMENT = 20.megabytes
  PBKDF2_ITERATIONS = 600_000

  class Error < StandardError; end

  cattr_accessor :directory, default: Rails.root.join("storage", "backups")

  def self.passphrase = ENV["BACKUP_PASSPHRASE"].presence || Rails.application.credentials.dig(:backup, :passphrase)

  # `openssl enc` with the passphrase from the environment, never on the command line
  def self.openssl!(*args, passphrase:)
    run!({ "BACKUP_PASS" => passphrase }, "openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", PBKDF2_ITERATIONS.to_s,
      *args, "-pass", "env:BACKUP_PASS")
  end

  def self.run!(env, *command)
    output, status = Open3.capture2e(env, *command)
    raise Error, "#{command.first} failed (exit #{status.exitstatus}): #{output.strip.last(500)}" unless status.success?
    output
  end

  # libpq environment for the app's own database
  def self.pg_env
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    { "PGHOST" => config[:host], "PGPORT" => config[:port]&.to_s, "PGUSER" => config[:username],
      "PGPASSWORD" => config[:password], "PGDATABASE" => config[:database] }.compact
  end

  def perform
    passphrase = self.class.passphrase.presence or raise Error, "Missing BACKUP_PASSPHRASE"
    check_versions!
    dump = dump!
    prune!
    email(dump, passphrase)
    ping
  rescue StandardError
    ping("/fail")
    raise
  end

  private

  def check_versions!
    client = pg_dump_major
    server = ActiveRecord::Base.connection.select_value("SHOW server_version_num").to_i / 10_000
    raise Error, "pg_dump #{client} doesn't match Postgres #{server}" unless client == server
  end

  def pg_dump_major = self.class.run!({}, "pg_dump", "--version")[/\)\s*(\d+)/, 1].to_i

  def dump!
    FileUtils.mkdir_p(directory)
    path = directory.join("household-#{Time.current.in_time_zone('Asia/Taipei').to_date.iso8601}.dump")
    self.class.run!(self.class.pg_env, "pg_dump", "--format=custom", "--no-owner", "--no-acl", "--file", path.to_s)
    path
  end

  def prune!
    Dir[directory.join("household-*.dump")].sort.reverse.drop(KEEP).each { |old| File.delete(old) }
  end

  def email(dump, passphrase)
    to = ENV["BACKUP_RECIPIENT"].presence || Rails.application.credentials.dig(:gmail, :sender)
    Dir.mktmpdir("backup") do |tmp|
      encrypted = File.join(tmp, "#{dump.basename}.enc")
      self.class.openssl!("-salt", "-in", dump.to_s, "-out", encrypted, passphrase:)
      if File.size(encrypted) > max_attachment
        BackupMailer.with(to:, filename: dump.basename.to_s, size: File.size(encrypted)).too_large.deliver_now
      else
        BackupMailer.with(to:, path: encrypted).dump.deliver_now
      end
    end
  end

  def max_attachment = MAX_ATTACHMENT

  def ping(suffix = "") = Heartbeat.ping(ENV["BACKUP_HEARTBEAT_URL"], suffix)
end
