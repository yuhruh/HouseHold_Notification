require "open3"

# Daily volume check (PRD → Infrastructure: alert at 80% usage). Reads the size of the volume behind
# /rails/storage with `df`, so it follows whatever limit the Railway plan gives. At or above
# THRESHOLD it reports to Sentry and pings DISK_HEARTBEAT_URL's /fail (optional Healthchecks.io
# check); below it pings success.
class DiskUsageJob < ApplicationJob
  queue_as :default

  THRESHOLD = 80

  Usage = Data.define(:used_kb, :size_kb) do
    def percent = size_kb.zero? ? 0 : (used_kb * 100.0 / size_kb).round(1)
    def to_s = format("%.1f of %.1f GB (%s%%)", used_kb / 1024.0**2, size_kb / 1024.0**2, percent)
  end

  cattr_accessor :path, default: Rails.root.join("storage")

  # `df -Pk`: 1024-byte blocks, one line per filesystem. Size is used + available, as df's own
  # Capacity column counts it (root-reserved blocks are out of reach either way).
  def self.usage(dir = path)
    output, status = Open3.capture2e("df", "-Pk", dir.to_s)
    raise "df failed: #{output.strip}" unless status.success?

    _filesystem, _blocks, used, available = output.lines.last.split
    Usage.new(used_kb: used.to_i, size_kb: used.to_i + available.to_i)
  end

  def perform
    usage = current_usage
    if usage.percent >= THRESHOLD
      message = "Railway volume #{usage}: over #{THRESHOLD}%. Delete old photos or grow the volume (docs/M0-SETUP.md §7)."
      Rails.logger.warn(message)
      Sentry.capture_message(message, level: :warning) if defined?(Sentry)
      ping("/fail")
    else
      ping
    end
    usage
  end

  private

  def current_usage = self.class.usage

  def ping(suffix = "") = Heartbeat.ping(ENV["DISK_HEARTBEAT_URL"], suffix)
end
