import CoreGraphics
import Foundation

/// Productivity skills that a companion can perform when dropped onto a window or given content.
public enum CompanionSkillKind: String, Codable, CaseIterable, Sendable, Identifiable {
  case snap
  case listen
  case participate
  case explain
  case record
  // Retained for decoding existing Vault records.
  case watch
  case focus
  case stash

  public var isAudioSession: Bool { self == .listen || self == .participate || self == .record }
  public var isMeetingSession: Bool { self == .listen || self == .participate }
  public var requiresWindow: Bool { self != .record && self != .stash }

  public var id: Self { self }

  public static let radialSkills: [Self] = [.listen, .participate, .snap, .explain, .record]

  public var title: String {
    switch self {
    case .snap: "Snap"
    case .participate: "Participate"
    case .explain: "Explain"
    case .record: "Record"
    case .listen: "Listen"
    case .watch: "Watch Window"
    case .focus: "Focus Sprint"
    case .stash: "Pocket Stash"
    }
  }

  public var shortTitle: String {
    switch self {
    case .snap: "Snap"
    case .participate: "Participate"
    case .explain: "Explain"
    case .record: "Record"
    case .listen: "Listen"
    case .watch: "Watch"
    case .focus: "Focus"
    case .stash: "Stash"
    }
  }

  public var symbolName: String {
    switch self {
    case .snap: "camera.viewfinder"
    case .participate: "person.wave.2.fill"
    case .explain: "text.viewfinder"
    case .record: "mic.fill"
    case .listen: "waveform.badge.mic"
    case .watch: "eye.circle.fill"
    case .focus: "timer"
    case .stash: "tray.and.arrow.down.fill"
    }
  }

  public var activeVerb: String {
    switch self {
    case .snap: "Capturing"
    case .participate: "Participating"
    case .explain: "Explaining"
    case .record: "Recording"
    case .listen: "Transcribing"
    case .watch: "Watching"
    case .focus: "Focusing"
    case .stash: "Stashed"
    }
  }

  public var eventKind: EventKind {
    switch self {
    case .snap: .skillSnap
    case .participate: .skillParticipate
    case .explain: .skillExplain
    case .record: .skillRecord
    case .listen: .skillListen
    case .watch: .skillWatch
    case .focus: .skillFocus
    case .stash: .stashReceived
    }
  }

  public var completionHeadline: String {
    switch self {
    case .snap: "Snapshot Saved"
    case .participate: "Meeting Transcript Ready"
    case .explain: "Explain"
    case .record: "Recording Ready"
    case .listen: "Transcript Ready"
    case .watch: "Window Activity Detected"
    case .focus: "Focus Sprint Logged"
    case .stash: "Saved to Pocket Stash"
    }
  }

  public var stopActionTitle: String? {
    switch self {
    case .listen, .participate, .record: "Finish"
    case .watch, .focus: "Done"
    case .snap, .explain, .stash: nil
    }
  }

  public var offersTargetActivationOnCompletion: Bool {
    self == .watch
  }

  public var savesPartialOnCancel: Bool {
    isAudioSession || self == .focus
  }
}
