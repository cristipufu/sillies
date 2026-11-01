import SilliesChat
import SwiftUI

/// Voice stays compact; the full transcript remains available in Chat.
struct TalkCaptionsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let user = model.messages.last(where: { $0.role == .user }) {
          Text(user.text).font(.callout).foregroundStyle(theme.secondary).textSelection(.enabled)
        }
        if let reply = model.messages.last(where: { $0.role == .companion }) {
          Text(model.presentedMessage(reply).text)
            .font(.system(.body, design: .rounded)).textSelection(.enabled)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }.defaultScrollAnchor(.bottom).frame(maxHeight: .infinity)
  }
}
