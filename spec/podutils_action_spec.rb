describe Fastlane::Actions::PodutilsAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The podutils plugin is working!")

      Fastlane::Actions::PodutilsAction.run(nil)
    end
  end
end
