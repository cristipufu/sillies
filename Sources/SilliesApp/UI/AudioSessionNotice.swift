import AppKit
import SwiftUI

struct AudioSessionNotice: View {
  let message: String
  let opensPrivacy: Bool
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 8) {
        Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        if opensPrivacy {
          Button("Open privacy settings") {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")
            else { return }
            NSWorkspace.shared.open(url)
          }.buttonStyle(.link)
        }
      }
      Spacer(minLength: 0)
    }.font(.callout).padding(12)
      .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }
}
