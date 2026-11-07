import SwiftUI

struct VaultQueryProgress: View {
  @Environment(\.silliesTheme) private var theme
  let model: VaultWorkspaceModel
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if model.isLoading, !model.searchText.isEmpty {
        HStack(spacing: 6) {
          ProgressView().controlSize(.mini)
          if model.ordering == .relevance {
            Text("Ranking matching items…")
          } else {
            Text("Searching saved text…")
          }
        }
      }
      if model.textMatching != .words, !model.searchText.isEmpty {
        Text(
          "Exact matching searches saved notes and captures. Choose Words & meaning to include conversations and related passages."
        )
      }
      if model.showsPreviousResults {
        Text("Showing the previous results while this search runs.")
      }
      if model.isFindingRelated {
        HStack(spacing: 6) {
          ProgressView().controlSize(.mini)
          Text("Finding related passages…")
        }
      } else if let availability = model.meaningAvailability {
        switch availability {
        case .ready: EmptyView()
        case .preparing: Text("Text search ready; meaning search is still preparing.")
        case .unavailable: Text("Meaning search is unavailable. Text search still works.")
        case .timedOut: Text("Meaning search took too long. Try again or narrow this search.")
        case .changed:
          Text("Saved items changed during this search. Refresh to see the latest matches.")
        case .failed(let message): Text(message).textSelection(.enabled)
        }
      }
    }.font(.caption).foregroundStyle(theme.secondary).padding(.horizontal, 16)
  }
}
