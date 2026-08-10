#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
require "tmpdir"
require "xcodeproj"

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

def write_project(signable_targets:, test_bundle_identifier: nil)
  project_dir = Dir.mktmpdir
  xcodeproj_path = File.join(project_dir, "DejaGroove.xcodeproj")
  project = Xcodeproj::Project.new(xcodeproj_path)
  signable_targets.each do |target_name, bundle_identifier|
    target = project.new_target(:application, target_name, :ios, "17.0")
    target.build_configurations.each do |configuration|
      configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_identifier
    end
  end

  unless test_bundle_identifier.nil?
    test_target = project.new_target(:unit_test_bundle, "DejaGrooveTests", :ios, "17.0")
    test_target.build_configurations.each do |configuration|
      configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = test_bundle_identifier
    end
  end

  project.save
  ENV["DEJA_GROOVE_XCODE_PROJECT"] = xcodeproj_path
end

def reset_signing_state
  Actions.lane_context.clear
  ENV.delete("sigh_com.dejagroove.app_appstore_profile-name")
end

write_project(
  signable_targets: { "DejaGroove" => "com.dejagroove.app" },
  test_bundle_identifier: "com.dejagroove.app.tests"
)

reset_signing_state
expected_mapping = {
  "com.dejagroove.app" => "match AppStore com.dejagroove.app 1786285596",
  "com.dejagroove.app.Widget" => "match AppStore com.dejagroove.app.Widget"
}
Actions.lane_context[SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING] = expected_mapping

export_options = appstore_export_options
raise "wrong signing style" unless export_options[:signingStyle] == "manual"
raise "wrong team" unless export_options[:teamID] == "TEAM123"
raise "wrong profile mapping" unless export_options[:provisioningProfiles] == expected_mapping

xcargs = appstore_xcargs
raise "missing manual signing override" unless xcargs.include?("CODE_SIGN_STYLE=Manual")
raise "missing team override" unless xcargs.include?("DEVELOPMENT_TEAM=TEAM123")
raise "missing archive profile override" unless xcargs.include?("PROVISIONING_PROFILE_SPECIFIER=match\\ AppStore\\ com.dejagroove.app\\ 1786285596")
raise "missing distribution identity" unless xcargs.include?("CODE_SIGN_IDENTITY=Apple\\ Distribution")
assert_single_appstore_archive_target!

reset_signing_state
ENV["sigh_com.dejagroove.app_appstore_profile-name"] = "match AppStore com.dejagroove.app env"
env_export_options = appstore_export_options
unless env_export_options[:provisioningProfiles] == { "com.dejagroove.app" => "match AppStore com.dejagroove.app env" }
  raise "wrong env fallback profile mapping"
end

reset_signing_state
default_export_options = appstore_export_options
unless default_export_options[:provisioningProfiles] == { "com.dejagroove.app" => "match AppStore com.dejagroove.app" }
  raise "wrong default fallback profile mapping"
end

reset_signing_state
Actions.lane_context[SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING] = {
  "com.dejagroove.other" => "match AppStore com.dejagroove.other"
}
begin
  appstore_export_options
  raise "missing app identifier should fail"
rescue RuntimeError => error
  raise error unless error.message.include?("does not include com.dejagroove.app")
end

write_project(
  signable_targets: {
    "DejaGroove" => "com.dejagroove.app",
    "DejaGrooveOther" => "com.dejagroove.other"
  },
  test_bundle_identifier: "com.dejagroove.app.tests"
)
begin
  assert_single_appstore_archive_target!
  raise "multi-target project should fail single-bundle validation"
rescue RuntimeError => error
  raise error unless error.message.include?("single bundle only")
end
RUBY

echo "Fastlane App Store signing tests passed."
