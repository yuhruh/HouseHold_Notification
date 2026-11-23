require "test_helper"

# config/initializers/content_security_policy.rb: pages load and run only this app's own files
class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  def policy = response.headers["Content-Security-Policy"].split("; ").to_h { it.split(" ", 2) }

  test "every page says what it may load: this app's files, and forms that end here or at Google" do
    get root_path
    assert_equal "'self'", policy["default-src"]
    assert_equal "'none'", policy["object-src"]
    assert_equal "'none'", policy["frame-ancestors"]
    assert_equal "'self'", policy["base-uri"]
    assert_equal "'self'", policy["connect-src"]
    assert_equal "'self' https://accounts.google.com", policy["form-action"]
    assert_equal "'self' data: blob:", policy["img-src"]
    assert_nil response.headers["Content-Security-Policy-Report-Only"], "enforced, not only reported"

    sign_in_as users(:alex)
    get household_path(households(:home))
    assert_equal "'self'", policy["default-src"], "signed-in pages too"
  end

  test "scripts: this app's files (and their WebAssembly) and the importmap's inline tags, by a nonce that's new each time" do
    get new_session_path
    assert_match(/\A'self' 'wasm-unsafe-eval' 'nonce-([^']{20,})'\z/, policy["script-src"])
    nonce = policy["script-src"][/nonce-([^']+)/, 1]
    assert_no_match(/unsafe-inline|(?<!wasm-)unsafe-eval|https:|\*/, policy["script-src"])
    assert_select "meta[name=csp-nonce][content=?]", nonce
    assert_select "script[type=importmap][nonce=?]", nonce
    assert_select "script:not([nonce]):not([src]):not([type='application/json'])", 0, "no inline script without the nonce"

    get new_session_path
    assert_not_equal nonce, policy["script-src"][/nonce-([^']+)/, 1]
  end

  test "no view has an inline event handler, a javascript: link or its own script tag" do
    views = Rails.root.glob("app/{views,helpers,components}/**/*.{erb,rb}").reject { it.to_s.end_with?("service-worker.js.erb") }
    event = /(?:click|change|submit|input|load|error|focus|blur|key[a-z]+|mouse[a-z]+|touch[a-z]+|pointer[a-z]+|drag[a-z]*|drop|toggle)/
    handler = /\bon#{event}\s*(=\s*["']|:\s*["'])|["']on#{event}["']\s*=>|javascript:/
    script = /<script(?![^>]*type="application\/json")|javascript_tag/
    offenders = views.flat_map do |path|
      path.each_line.with_index(1).filter_map { |line, number| "#{path.relative_path_from(Rails.root)}:#{number}" if line.match?(handler) || line.match?(script) }
    end
    assert_empty offenders, "the policy blocks these; use a Stimulus action (data-action) instead"
  end

  test "fields that used to submit with onchange do it with the auto-submit controller" do
    sign_in_as users(:alex)
    get household_dashboard_path(households(:home))
    assert_select "form[data-controller=auto-submit] select[data-action='auto-submit#submit']", 3
    get household_members_path(households(:home))
    assert_select "form[data-controller=auto-submit] select[name='membership[role]'][data-action='auto-submit#submit']"
    get account_path
    assert_select "form[data-controller=auto-submit][data-auto-submit-busy-value] label span[data-auto-submit-target=label]"
  end
end
