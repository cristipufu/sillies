import SilliesCore
import SwiftUI

/// Keep status visible without letting long diagnostics displace the live content.
struct AudioSessionNotices: View {
  @Environment(\.silliesTheme) private var theme
  private static let detailsWidth: CGFloat = 360
  private static let maximumDetailsHeight: CGFloat = 300
  let model: AudioSessionPresentation
  @State private var showsDetails = false

  var body: some View {
    if let message = statusMessage {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: hasWarning ? "exclamationmark.triangle.fill" : "person.2.wave.2")
          .foregroundStyle(hasWarning ? theme.warning : theme.secondary)
        Text(message).font(.caption).foregroundStyle(theme.secondary)
          .lineLimit(2).textSelection(.enabled)
        Spacer(minLength: 0)
        if hasWarning {
          Button("Show details") { showsDetails.toggle() }
            .buttonStyle(.link).font(.caption)
            .popover(isPresented: $showsDetails) { details }
        }
      }
    }
  }

  private var statusMessage: String? {
    failure?.message ?? model.speakerDetectionNotice ?? model.reasoningNotice
      ?? (model.diarizationModel == nil
        ? nil : String(localized: "Speaker labels enabled · Labels may take a few seconds"))
  }

  private var failure: SessionFailure? {
    if case .failed(let failure) = model.phase { return failure }
    return model.transcriptionFailure
  }

  private var hasWarning: Bool {
    failure != nil || model.speakerDetectionNotice != nil || model.reasoningNotice != nil
  }

  private var details: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if case .failed(let failure) = model.phase {
          SessionFailureNotice(failure: failure)
        }
        if let failure = model.transcriptionFailure {
          SessionFailureNotice(failure: failure)
        }
        if let notice = model.reasoningNotice {
          SessionWarningNotice(message: notice) { EmptyView() }
        }
        if model.diarizationModel != nil, let message = model.speakerDetectionNotice {
          Text(message).font(.callout).textSelection(.enabled)
        } else if model.diarizationModel != nil {
          Text("Speaker labels enabled · Labels may take a few seconds")
            .font(.callout).textSelection(.enabled)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(width: Self.detailsWidth)
    .frame(maxHeight: Self.maximumDetailsHeight)
  }
}
