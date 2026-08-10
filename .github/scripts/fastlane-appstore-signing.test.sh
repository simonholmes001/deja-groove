#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
module UI
  def self.user_error!(message)
    raise message
  end
end

module SharedValues
  MATCH_PROVISIONING_PROFILE_MAPPING = :match_mapping
end

module Actions
  def self.lane_context
    @lane_context ||= {}
  end
end

def platform(*)
  yield
end

def desc(*); end
def lane(*); end

load "ios/fastlane/Fastfile"

ENV["DEJA_GROOVE_APP_IDENTIFIER"] = "com.dejagroove.app"
ENV["DEJA_GROOVE_TEAM_ID"] = "TEAM123"
ENV["DEJA_GROOVE_BUILD_NUMBER"] = "42"
Actions.lane_context[SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING] = {
  "com.dejagroove.app" => "match AppStore com.dejagroove.app 1786285596"
}

export_options = appstore_export_options
expected_profile = "match AppStore com.dejagroove.app 1786285596"

raise "wrong signing style" unless export_options[:signingStyle] == "manual"
raise "wrong team" unless export_options[:teamID] == "TEAM123"
raise "wrong profile mapping" unless export_options[:provisioningProfiles]["com.dejagroove.app"] == expected_profile

xcargs = appstore_xcargs
raise "missing manual signing override" unless xcargs.include?("CODE_SIGN_STYLE=Manual")
raise "missing team override" unless xcargs.include?("DEVELOPMENT_TEAM=TEAM123")
raise "missing profile override" unless xcargs.include?("PROVISIONING_PROFILE_SPECIFIER=match\\ AppStore\\ com.dejagroove.app\\ 1786285596")
raise "missing distribution identity" unless xcargs.include?("CODE_SIGN_IDENTITY=Apple\\ Distribution")
RUBY

echo "Fastlane App Store signing tests passed."
