import SwiftUI

struct VaultWorkspaceStatus: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  let model: SessionVaultModel

  var body: some View {
    if model.isExporting || model.feedback != nil || vault.persistenceError != nil
      || model.discussionFailure != nil
    {
      VStack(spacing: 0) {
        Divider().overlay(theme.border)
        VaultNoticeArea {
          VStack(alignment: .leading, spacing: 10) {
            if model.isExporting {
              HStack {
                ProgressView().controlSize(.small)
                Text(model.fileOperationTitle)
                Spacer()
                if model.canCancelFileOperation {
                  Button("Cancel", action: model.cancelFileOperation).buttonStyle(SoftButtonStyle())
                }
              }
            }
            if let message = vault.persistenceError ?? model.feedback {
              HStack(alignment: .top, spacing: 10) {
                Text(message).textSelection(.enabled)
                Spacer()
                if vault.persistenceError != nil {
                  Button("Try again") { vault.retrySaving() }.disabled(vault.isLoading)
                } else if model.keepsFeedbackVisible {
                  Button("Dismiss", action: model.dismissFeedback)
                }
              }
            }
            if let failure = model.discussionFailure {
              HStack(alignment: .top) {
                SessionFailureNotice(failure: failure)
                Button("Dismiss", action: model.dismissDiscussionFailure)
              }
            }
          }.font(.caption).padding(12)
        }
      }
    }
  }
}
