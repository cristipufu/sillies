import CoreGraphics
import Foundation

/// Productivity skills that a companion can perform when dropped onto a window or given content.
public enum CompanionSkillKind: String, Codable, CaseIterable, Sendable, Identifiable {
  case snap
  case listen
  case participate
  case explain
  case record
  case chat
  // Retained for decoding existing Vault records.
  case watch
  case focus
  case stash

  public var isAudioSession: Bool { self == .listen || self == .participate || self == .record }
  public var keepsCompanionStill: Bool { isAudioSession || self == .chat }
  public var isMeetingSession: Bool { self == .listen || self == .participate }
  public var requiresWindow: Bool { self != .record && self != .stash && self != .chat }

  public var id: Self { self }

  public static let radialSkills: [Self] = [.listen, .participate, .snap, .explain]

  public var title: String {
    switch self {
    case .chat: String(localized: "Chat")
    case .snap: String(localized: "Snap")
    case .participate: String(localized: "Participate")
    case .explain: String(localized: "Explain")
    case .record: String(localized: "Record")
    case .listen: String(localized: "Listen")
    case .watch: String(localized: "Watch Window")
    case .focus: String(localized: "Focus Sprint")
    case .stash: String(localized: "Pocket Stash")
    }
  }

  public var shortTitle: String {
    switch self {
    case .chat: String(localized: "Chat")
    case .snap: String(localized: "Snap")
    case .participate: String(localized: "Participate")
    case .explain: String(localized: "Explain")
    case .record: String(localized: "Record")
    case .listen: String(localized: "Listen")
    case .watch: String(localized: "Watch")
    case .focus: String(localized: "Focus")
    case .stash: String(localized: "Stash")
    }
  }

  public var symbolName: String {
    switch self {
    case .chat: "bubble.left.and.bubble.right.fill"
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
    case .chat: "Chatting"
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
    case .chat: .skillChat
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
    case .chat: String(localized: "Chat Saved")
    case .snap: String(localized: "Snapshot Saved")
    case .participate: String(localized: "Meeting Transcript Ready")
    case .explain: String(localized: "Explain")
    case .record: String(localized: "Recording Ready")
    case .listen: String(localized: "Transcript Ready")
    case .watch: String(localized: "Window Activity Detected")
    case .focus: String(localized: "Focus Sprint Logged")
    case .stash: String(localized: "Saved to Pocket Stash")
    }
  }

  public var stopActionTitle: String? {
    switch self {
    case .chat: String(localized: "Close conversation")
    case .listen, .participate, .record: String(localized: "Finish")
    case .watch, .focus: String(localized: "Done")
    case .snap, .explain, .stash: nil
    }
  }

  public var offersTargetActivationOnCompletion: Bool {
    self == .watch
  }

  public var savesPartialOnCancel: Bool {
    isAudioSession || self == .focus || self == .chat
  }
}
