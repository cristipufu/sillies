import SilliesCore
import SwiftUI

struct VaultDocumentNotices: View {
  @Environment(\.silliesTheme) private var theme
  let header: VaultDocumentHeader
  let model: VaultDocumentModel
  let workspace: VaultWorkspaceModel

  var body: some View {
    VaultNoticeArea {
      VStack(alignment: .leading, spacing: 10) {
        if let error = model.playback.error ?? model.recording.error {
          Text(error).font(.caption).foregroundStyle(theme.warning).textSelection(.enabled)
        }
        if let failure = header.source.failure { SessionFailureNotice(failure: failure) }
        if model.section == .summary {
          if let notice = header.source.notesNotice {
            Text(notice).font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
          }
          if header.source.notesSource == .extracted {
            Text(
              "Selected excerpts from the transcript, not an AI summary. Open the full transcript for context."
            )
            .font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
          }
        }
        if let error = model.error ?? model.editor.error ?? model.metadata.error {
          Text(error).font(.callout).foregroundStyle(theme.danger).textSelection(.enabled)
          HStack {
            if model.metadata.error != nil {
              Button("Try again") { Task { await model.metadata.retry() } }
            } else if !model.editor.isDirty {
              Button("Try again") { workspace.retrySelection() }
            }
            if model.editor.isDirty, !model.editor.recoverySaved {
              Button("Retry saving") { Task { await model.editor.retrySavingDraft() } }
              Button("Save as new note") { Task { await workspace.recoverDraftAsNote() } }
            }
          }.buttonStyle(SoftButtonStyle())
            .disabled(model.editor.isRecovering || model.editor.isSaving)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.horizontal, 24)
  }
}
