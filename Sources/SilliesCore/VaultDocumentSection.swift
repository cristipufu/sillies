import Foundation

public enum VaultDocumentSection: String, Codable, CaseIterable, Sendable {
  case notes, summary, transcript, screenshotText, explanation, actions, suggestions, stash,
    linkText, originalTranscript, title, labels, files
}
