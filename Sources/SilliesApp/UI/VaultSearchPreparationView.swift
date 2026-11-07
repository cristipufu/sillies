import SwiftUI

struct VaultSearchPreparationView: View {
  @Environment(\.silliesTheme) private var theme
  let model: VaultSearchPreparationModel
  let isPresented: Bool

  var body: some View {
    VaultNoticeArea {
      notices
    }.font(.caption).task(id: isPresented) {
      if isPresented { await model.observe() }
    }
  }

  private var notices: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let failure = model.cleanupFailure {
        HStack {
          Text("Storage cleanup paused. \(failure)").textSelection(.enabled)
          Button("Try again") { Task { await model.retryCleanup() } }
          Spacer()
        }.foregroundStyle(theme.warning).padding(10)
      } else if model.cleanup?.isPending == true {
        HStack(spacing: 10) {
          ProgressView().controlSize(.mini)
          Text("Removing deleted items in the background. You can keep using your Vault.")
          Spacer()
        }.foregroundStyle(theme.secondary).padding(10)
      }
      if let failure = model.failure {
        HStack {
          Image(systemName: "exclamationmark.triangle")
          Text(failure).textSelection(.enabled)
          Button("Try again") { Task { await model.retry() } }
          Spacer()
        }.foregroundStyle(theme.warning).padding(10)
      } else if model.isPreparing {
        HStack(spacing: 10) {
          ProgressView().controlSize(.mini)
          if let progress = model.progress {
            Text("Search passages prepared: \(progress.processed)")
          } else {
            Text("Preparing search…")
          }
          Spacer()
        }.foregroundStyle(theme.secondary).padding(10)
      }
    }
  }
}
