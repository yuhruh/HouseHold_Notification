require Rails.root.join("lib/delivery_methods/gmail_api")

ActionMailer::Base.add_delivery_method :gmail_api, DeliveryMethods::GmailApi
