require "test_helper"

class DiskUsageJobTest < ActiveJob::TestCase
  setup { @pings = [] }

  def job(used_kb:, size_kb:)
    pings = @pings
    DiskUsageJob.new.tap do |j|
      j.define_singleton_method(:ping) { |suffix = ""| pings << suffix }
      j.define_singleton_method(:current_usage) { DiskUsageJob::Usage.new(used_kb:, size_kb:) }
    end
  end

  test "below 80% pings success" do
    usage = job(used_kb: 1_000_000, size_kb: 5_000_000).perform_now
    assert_equal 20.0, usage.percent
    assert_equal [ "" ], @pings
  end

  test "at 80% pings /fail" do
    job(used_kb: 4_000_000, size_kb: 5_000_000).perform_now
    assert_equal [ "/fail" ], @pings
  end

  test "reads the real filesystem with df" do
    usage = DiskUsageJob.usage(Dir.tmpdir)
    assert_operator usage.size_kb, :>, 0
    assert usage.percent.between?(0, 100)
    assert_match(/GB \(\d+(\.\d)?%\)/, usage.to_s)
  end
end
