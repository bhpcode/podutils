require 'fastlane/action'
require_relative '../helper/podutils_helper'
require_relative 'podutils_imp'

module Fastlane
  module Actions
    class PodutilsAction < Action
      def self.run(params)
        pu = Fastlane::Pod::Podutils.new(params)
        pu.run()
      end

      def self.description
        "cocoapod release utilities"
      end

      def self.authors
        ["ybs"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "cocoapod release, linting and versioning"
      end

      def self.available_options
        [
       
          FastlaneCore::ConfigItem.new(key: :podspec,
                                   env_name: "PODUTILS_PODSPEC",
                                description: "podspec file",
                                   optional: false,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :podrepo,
                                   env_name: "PODUTILS_PODREPO",
                                description: "path to pod repo (optional only if lib lint only set)",
                                   optional: true,
                              default_value: nil,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :verbose,
                                   env_name: "PODUTILS_VERBOSE",
                                description: "verbose mode",
                                   optional: true,
                              default_value: false,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :bumpMethod,
                                   env_name: "PODUTILS_BUMP_METHOD",
                                description: "how to bump version (BUMP_BUILD=0, BUMP_MINOR=1, BUMP_MAJOR=2) default is BUMP_BUILD",
                                   optional: true,
                              default_value: Fastlane::Pod::Podutils::BUMP_BUILD,
                                       type: Integer),
          FastlaneCore::ConfigItem.new(key: :skipLibLint,
                                   env_name: "PODUTILS_SKIP_LIB_LINT",
                                description: "skip lib lint step",
                                   optional: true,
                              default_value: false,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :noClean,
                                   env_name: "PODUTILS_NO_CLEAN",
                                description: "don't clean any intermediate files or restore repository if failure",
                                   optional: true,
                              default_value: false,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :libLintOnly,
                                   env_name: "PODUTILS_LIB_LINT_ONLY",
                                description: "lib lint only",
                                   optional: true,
                              default_value: false,
                                       type: Boolean)
        ]
      end

      def self.is_supported?(platform)
        return [:ios, :mac].include?(platform)
      end
    end
  end
end
