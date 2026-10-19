module Spike
  # M0 exit-criteria checks: volume persistence, Sentry, Gmail API delivery.
  class ChecksController < BaseController
    VOLUME_FILE = "spike/volume-check.txt".freeze

    def show
      path = volume_path
      @volume_history = path.exist? ? path.read.lines.last(20) : []
      @volume_writable = path.dirname.writable? || !path.dirname.exist?
    end

    # Appends a line to a file on the volume. After a redeploy, the old lines must still be there.
    def write_volume
      path = volume_path
      FileUtils.mkdir_p(path.dirname)
      File.open(path, "a") { |f| f.puts "#{Time.current.iso8601} written by #{Process.uid} on #{ENV.fetch('RAILWAY_DEPLOYMENT_ID', 'local')}" }
      redirect_to spike_checks_path, notice: "Wrote to #{path}"
    end

    def raise_error
      raise "Spike: deliberate exception to verify Sentry (#{Time.current.iso8601})"
    end

    def send_email
      TestMailer.with(to: params.require(:to)).hello.deliver_now
      redirect_to spike_checks_path, notice: "Email sent to #{params[:to]}"
    end

    # Runs the weekly backup now (first run and restore drill, M2)
    def run_backup
      BackupJob.perform_later
      redirect_to spike_checks_path, notice: "Backup queued; the encrypted copy arrives by email in a minute or two"
    end

    private

    def volume_path
      Rails.root.join("storage", VOLUME_FILE)
    end
  end
end
