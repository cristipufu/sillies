import SwiftUI

struct ChatPageHeader: View {
  let title: String
  let back: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button("Back", systemImage: "chevron.left", action: back)
        .labelStyle(.iconOnly).buttonStyle(.plain).keyboardShortcut(.cancelAction)
      Text(title).font(.title2.bold())
      Spacer()
    }
  }
}
