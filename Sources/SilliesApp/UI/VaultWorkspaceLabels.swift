import Foundation
import SilliesCore

extension VaultWorkspaceQuery.Ordering {
  var title: String {
    switch self {
    case .newest: String(localized: "Newest first")
    case .oldest: String(localized: "Oldest first")
    case .modified: String(localized: "Recently edited")
    case .relevance: String(localized: "Best match")
    }
  }
}

extension VaultWorkspaceQuery.Scope {
  var title: String {
    switch self {
    case .all: String(localized: "All items")
    case .starred: String(localized: "Starred")
    case .notes: String(localized: "Notes")
    case .meetings: String(localized: "Meetings")
    case .screenshots: String(localized: "Screenshots")
    case .links: String(localized: "Links & files")
    case .conversations: String(localized: "Conversations")
    case .trash: String(localized: "Trash")
    }
  }
  var symbol: String {
    switch self {
    case .all: "square.stack.3d.up"
    case .starred: "star"
    case .notes: "square.and.pencil"
    case .meetings: "waveform"
    case .screenshots: "photo"
    case .links: "link"
    case .conversations: "bubble.left.and.bubble.right"
    case .trash: "trash"
    }
  }
}

extension VaultDocumentSection {
  var title: String {
    switch self {
    case .notes: String(localized: "My notes")
    case .summary: String(localized: "Summary")
    case .transcript: String(localized: "Transcript")
    case .screenshotText: String(localized: "Screenshot text")
    case .explanation: String(localized: "Explanation")
    case .actions: String(localized: "Action items")
    case .suggestions: String(localized: "Meeting suggestions")
    case .stash: String(localized: "Saved text")
    case .linkText: String(localized: "Link")
    case .originalTranscript: String(localized: "Original transcript")
    case .title: String(localized: "Title")
    case .labels: String(localized: "Tags")
    case .files: String(localized: "File references")
    }
  }
}

extension VaultDocumentHeader {
  var symbol: String {
    switch metadata.kind {
    case .note: "square.and.pencil"
    case .link:
      metadata.link?.kind == .video
        ? "play.rectangle" : (metadata.link?.kind == .post ? "quote.bubble" : "link")
    case .capture: source.kind.symbolName
    }
  }
}
