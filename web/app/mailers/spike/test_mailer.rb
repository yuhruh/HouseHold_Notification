module Spike
  class TestMailer < ApplicationMailer
    def hello
      mail(to: params[:to], subject: "Household Tracker Gmail API test #{Time.current.in_time_zone('Asia/Taipei').strftime('%F %T')}")
    end
  end
end
