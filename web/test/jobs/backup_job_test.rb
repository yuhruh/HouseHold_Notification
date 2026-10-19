require "test_helper"

class BackupJobTest < ActiveJob::TestCase
  PASSPHRASE = "correct horse battery staple"

  setup do
    @env = ENV.to_h.slice("BACKUP_PASSPHRASE", "BACKUP_RECIPIENT")
    ENV["BACKUP_PASSPHRASE"] = PASSPHRASE
    ENV["BACKUP_RECIPIENT"] = "alex@example.com"
    @dir = Pathname(Dir.mktmpdir("backups"))
    @original_dir = BackupJob.directory
    BackupJob.directory = @dir
    @pings = []
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    %w[BACKUP_PASSPHRASE BACKUP_RECIPIENT].each { |key| ENV[key] = @env[key] }
    BackupJob.directory = @original_dir
    FileUtils.rm_rf(@dir)
  end

  def job(**overrides)
    BackupJob.new.tap do |j|
      pings = @pings
      j.define_singleton_method(:ping) { |suffix = ""| pings << suffix }
      overrides.each { |name, value| j.define_singleton_method(name) { |*| value.respond_to?(:call) ? value.call : value } }
    end
  end

  def server_major = ActiveRecord::Base.connection.select_value("SHOW server_version_num").to_i / 10_000

  test "a pg_dump that doesn't match the server's major version raises and pings /fail" do
    error = assert_raises(BackupJob::Error) { job(pg_dump_major: server_major + 1).perform_now }
    assert_match "doesn't match Postgres #{server_major}", error.message
    assert_equal [ "/fail" ], @pings
    assert_empty Dir.children(@dir)
  end

  test "a missing passphrase raises before dumping" do
    ENV["BACKUP_PASSPHRASE"] = ""
    assert_raises(BackupJob::Error) { job.perform_now }
    assert_equal [ "/fail" ], @pings
    assert_empty Dir.children(@dir)
  end

  test "keeps the last 4 dumps and emails one encrypted attachment that restores cleanly" do
    client = BackupJob.run!({}, "pg_dump", "--version")[/\)\s*(\d+)/, 1].to_i
    skip "pg_dump #{client} can't dump Postgres #{server_major}" if client < server_major

    %w[2026-09-13 2026-09-20 2026-09-27 2026-10-04 2026-10-11].each { |day| File.write(@dir.join("household-#{day}.dump"), "old") }
    job(check_versions!: nil).perform_now

    today = Time.current.in_time_zone("Asia/Taipei").to_date.iso8601
    assert_equal %W[household-2026-09-27.dump household-2026-10-04.dump household-2026-10-11.dump household-#{today}.dump],
      Dir.children(@dir).sort
    assert_equal [ "" ], @pings

    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ "alex@example.com" ], mail.to
    attachment = mail.attachments.sole
    assert_equal "household-#{today}.dump.enc", attachment.filename

    Dir.mktmpdir do |tmp|
      encrypted, decrypted = File.join(tmp, "x.enc"), File.join(tmp, "x.dump")
      File.binwrite(encrypted, attachment.decoded)
      assert_raises(BackupJob::Error) { BackupJob.openssl!("-d", "-in", encrypted, "-out", decrypted, passphrase: "wrong") }
      BackupJob.openssl!("-d", "-in", encrypted, "-out", decrypted, passphrase: PASSPHRASE)
      assert_includes BackupJob.run!({}, "pg_restore", "--list", decrypted), "TABLE DATA public records"
    end
  end

  test "an encrypted dump over the attachment limit sends the warning email instead" do
    fake_dump = -> { @dir.join("household-2026-10-18.dump").tap { |p| File.write(p, "x" * 2048) } }
    job(check_versions!: nil, dump!: fake_dump, max_attachment: 1024).perform_now

    mail = ActionMailer::Base.deliveries.sole
    assert_empty mail.attachments
    assert_match "household-2026-10-18.dump", mail.subject
    assert_equal [ "" ], @pings
  end
end
