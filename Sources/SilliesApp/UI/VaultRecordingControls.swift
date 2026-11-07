import SilliesCore
import SwiftUI

struct VaultRecordingControls: View {
  @Environment(\.silliesTheme) private var theme
  let document: VaultDocumentModel
  let recordID: UUID
  private struct FollowIdentity: Hashable {
    let seconds: Double
    let isFollowing: Bool
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 14) {
        Button {
          if document.recording.isFollowing {
            document.recording.pauseFollowing()
          } else {
            Task { await document.followAudio(recordID: recordID) }
          }
        } label: {
          Label(
            document.recording.isFollowing
              ? String(localized: "Following audio") : String(localized: "Follow audio"),
            systemImage: document.recording.isFollowing
              ? "text.line.first.and.arrowtriangle.forward" : "text.alignleft")
        }.disabled(!document.sections.contains(.transcript))
        Spacer()
        Menu {
          Button("Bookmark this moment") {
            let seconds = document.playback.position
            Task { await document.recording.addBookmark(seconds: seconds, recordID: recordID) }
          }
          .disabled(document.header?.metadata.trashedAt != nil)
          ForEach(document.recording.bookmarks) { bookmark in
            Menu(bookmarkTitle(bookmark)) {
              Button("Play from here") { document.playback.play(from: bookmark.seconds) }
              Button("Remove bookmark", role: .destructive) {
                Task { await document.recording.remove(bookmark) }
              }
            }
          }
        } label: {
          Label("Bookmarks", systemImage: "bookmark")
        }.menuStyle(.borderlessButton).fixedSize()
      }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.accent)
    }.padding(.horizontal, 16).padding(.top, 10)
      .task(
        id: FollowIdentity(
          seconds: document.playback.position, isFollowing: document.recording.isFollowing)
      ) {
        await document.recording.follow(seconds: document.playback.position)
      }
  }
  private func bookmarkTitle(_ bookmark: VaultRecordingBookmark) -> String {
    let time = SessionRecord.formatDuration(bookmark.seconds)
    return bookmark.label.isEmpty ? time : "\(time) · \(bookmark.label)"
  }
}
