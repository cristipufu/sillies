import SilliesChat
import SwiftUI

/// Brief recoveries wrap their content; longer diagnostics cannot displace the conversation.
struct ChatNoticeViewport: View {
  let model: ChatSession
  let openSettings: (ChatNotice.SettingsDestination) -> Void
  private static let maximumHeight: CGFloat = 96
  private static let horizontalInset: CGFloat = 16
  private static let verticalInset: CGFloat = 8

  var body: some View {
    NoticeViewport(maximumHeight: Self.maximumHeight) {
      ChatSessionNotices(model: model, openSettings: openSettings)
        .padding(.horizontal, Self.horizontalInset).padding(.vertical, Self.verticalInset)
    }
  }
}
