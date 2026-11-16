# Be sure to restart your server when you modify this file.

# What a page of this app may load and run: its own files, and nothing else. If text someone typed
# ever reached a page as HTML, the browser would still refuse to run it as script, load a script
# from elsewhere, or send a form anywhere but here.
#
# Everything is served from this app (the JavaScript, pdf.js and ZXing under /vendor, the chart
# library, fonts, icons), so no other host is listed, with one exception: a form may end at Google,
# where "Continue with Google" and "Connect Google Drive" send the browser.
#
# Scripts: files from this app, plus the two small inline tags the importmap needs, which carry
# the request's nonce. There are no inline event handlers (onclick="…"); use a Stimulus action.
# test/integration/content_security_policy_test.rb keeps the views that way.
#
# Styles: 'unsafe-inline' stays, for style="…" attributes (the supplies bars, the chart's tooltip).
# A style can't run code, and it can't load anything from another host under img-src and font-src.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.script_src      :self
    policy.style_src       :self, :unsafe_inline
    policy.img_src         :self, :data, :blob # blob: a picked photo's preview before it uploads
    policy.font_src        :self, :data
    policy.media_src       :self, :blob
    policy.connect_src     :self
    policy.worker_src      :self # pdf.js's worker and the service worker
    policy.manifest_src    :self
    policy.object_src      :none
    policy.base_uri        :self
    policy.form_action     :self, "https://accounts.google.com"
    policy.frame_ancestors :none
  end

  # A new one for each response. Turbo copies it from <meta name="csp-nonce"> where it needs it.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
