# Healthchecks.io pings (PRD → Monitoring). A missing URL or a failed ping never breaks the job.
module Heartbeat
  def self.ping(url, suffix = "")
    return if url.blank?
    Net::HTTP.get_response(URI("#{url}#{suffix}"))
  rescue StandardError => e
    Rails.logger.warn("Heartbeat ping failed: #{e.message}")
  end
end
