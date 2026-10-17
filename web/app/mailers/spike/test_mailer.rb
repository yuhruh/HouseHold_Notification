module Spike
  class TestMailer < ApplicationMailer
    def hello
      mail(to: params[:to], subject: "我的家 Gmail API test #{Time.current.in_time_zone('Asia/Taipei').strftime('%F %T')}")
    end
  end
end
