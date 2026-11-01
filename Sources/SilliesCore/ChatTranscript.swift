import Foundation

public enum ChatTranscript {
  public static func render(
    _ messages: [ChatMessage], companionName: String, userName: String = "You"
  ) -> String {
    messages.map { "\($0.role == .user ? userName : companionName)\n\($0.text)" }.joined(
      separator: "\n\n")
  }
}
