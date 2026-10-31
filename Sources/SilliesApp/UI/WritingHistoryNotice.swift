import SilliesWriting
import SwiftUI

struct WritingHistoryNotice: View {
  let failure: WritingHistoryFailure
  let retry: () -> Void

  var body: some View {
    SessionWarningNotice(message: failure.message) {
      Button("Retry", action: retry).buttonStyle(SoftButtonStyle())
    }.help(failure.detail)
  }
}
