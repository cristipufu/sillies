import SilliesCore
import SwiftUI

struct VaultDocumentPlaceholder: View {
  @Environment(\.silliesTheme) private var theme
  let scope: VaultWorkspaceQuery.Scope
  let createNote: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: scope == .trash ? "trash" : "sparkles").font(
        .system(size: 30, weight: .light)
      )
      .foregroundStyle(theme.accent.opacity(0.65))
      Text(
        scope == .trash ? String(localized: "Trash") : String(localized: "Room for your thoughts")
      )
      .font(.system(size: 20, weight: .semibold, design: .rounded))
      if scope == .trash {
        Text("Restore items or delete them permanently.")
          .font(.system(size: 13)).foregroundStyle(theme.secondary)
      } else {
        Text("Choose something from your Vault, or start a fresh note.")
          .font(.system(size: 13)).foregroundStyle(theme.secondary)
        Button("New note", systemImage: "square.and.pencil", action: createNote)
          .buttonStyle(SoftButtonStyle())
      }
    }.multilineTextAlignment(.center).padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
