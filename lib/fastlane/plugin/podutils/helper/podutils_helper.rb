require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class PodutilsHelper
      # class methods that you define here become available in your action
      # as `Helper::PodutilsHelper.your_method`
      #
      def self.show_message
        UI.message("Hello from the podutils plugin helper!")
      end
    end
  end
end
