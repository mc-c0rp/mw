#!/usr/bin/env ruby
# Configures the mw.xcodeproj target: build settings, entitlements, and links +
# embeds the whisper.cpp xcframework. Idempotent.

require 'xcodeproj'

PROJECT = '/Users/m/Documents/mw_transcript/mw/mw.xcodeproj'
project = Xcodeproj::Project.open(PROJECT)
target = project.targets.find { |t| t.name == 'mw' }
raise 'target mw not found' unless target

MIC_DESC = 'mw записывает звук с микрофона, чтобы расшифровать вашу речь в текст.'

target.build_configurations.each do |config|
  bs = config.build_settings
  bs['SWIFT_VERSION'] = '6.0'
  bs['ENABLE_APP_SANDBOX'] = 'NO'
  bs['ENABLE_HARDENED_RUNTIME'] = 'YES'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'mw.entitlements'
  bs['INFOPLIST_KEY_LSUIElement'] = 'YES'
  bs['INFOPLIST_KEY_NSMicrophoneUsageDescription'] = MIC_DESC

  # Liquid Glass app icon (AppIcon.icon bundle in mw/).
  bs['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  bs['ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'] = 'YES'

  paths = bs['FRAMEWORK_SEARCH_PATHS']
  paths = [paths].compact unless paths.is_a?(Array)
  paths = ['$(inherited)'] if paths.empty?
  paths << '$(PROJECT_DIR)/Frameworks' unless paths.include?('$(PROJECT_DIR)/Frameworks')
  bs['FRAMEWORK_SEARCH_PATHS'] = paths
end

# --- whisper.xcframework: reference, link, embed ---
fw_group = project.main_group.find_subpath('Frameworks', true)

xcf_path = 'Frameworks/whisper.xcframework'
ref = fw_group.files.find { |f| f.path == xcf_path }
unless ref
  ref = fw_group.new_file(xcf_path)
end

# Link (Frameworks build phase)
unless target.frameworks_build_phase.files_references.include?(ref)
  target.frameworks_build_phase.add_file_reference(ref, true)
end

# Embed (Copy Files -> Frameworks, code sign on copy)
embed = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
unless embed
  embed = target.new_copy_files_build_phase('Embed Frameworks')
  embed.symbol_dst_subfolder_spec = :frameworks
end
unless embed.files_references.include?(ref)
  bf = embed.add_file_reference(ref, true)
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end

project.save
puts 'OK: project configured'
puts "build phases: #{target.build_phases.map { |p| p.display_name }.join(', ')}"
puts "frameworks linked: #{target.frameworks_build_phase.files_references.map(&:display_name).join(', ')}"
