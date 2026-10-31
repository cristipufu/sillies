import Foundation
import SilliesReasoning

/// Writing observes a companion's presentation without owning its controller or capture lifetime.
@MainActor protocol WritingCompanionHost: AnyObject {
  var hasAvailableWritingCompanion: Bool { get }
  var shouldRun: Bool { get }
  var onOpenWritingSession: (() -> Void)? { get set }
  var onWritingAnchorChanged: ((WritingCompanionAnchor?) -> Void)? { get set }
  func beginWritingIndicator() -> WritingCompanionAnchor?
  func finishWritingIndicator()
  func endWritingIndicator()
}

@MainActor protocol RecordingActivity: AnyObject {
  var hasActiveRecording: Bool { get }
  var canStartAudio: () -> Bool { get set }
}

extension CompanionController: WritingCompanionHost {}
extension SkillCoordinator: RecordingActivity {
  var hasActiveRecording: Bool { activeAudioSession != nil }
}

@MainActor struct WritingServices {
  let vault: SessionVaultStore
  let recording: any RecordingActivity
  let commands: CommandDispatcher
  let reasoning: any LocalReasoning
}
