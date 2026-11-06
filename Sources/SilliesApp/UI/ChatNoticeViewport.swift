import SilliesChat
import SwiftUI

/// Brief recoveries wrap their content; longer diagnostics cannot displace the conversation.
struct ChatNoticeViewport: View {
  let model: ChatSession
  let openSettings: (ChatNotice.SettingsDestination) -> Void
  private static let maximumHeight: CGFloat = 96
  private static let initialHeight: CGFloat = 44
  private static let horizontalInset: CGFloat = 16
  private static let verticalInset: CGFloat = 8
  @State private var contentHeight = Self.initialHeight

  var body: some View {
    ScrollView {
      ChatSessionNotices(model: model, openSettings: openSettings)
        .padding(.horizontal, Self.horizontalInset).padding(.vertical, Self.verticalInset)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          contentHeight = $0
        }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(height: min(Self.maximumHeight, contentHeight))
  }
}
