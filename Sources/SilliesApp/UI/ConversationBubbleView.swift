import SilliesCore
import SwiftUI

@MainActor @Observable
final class ConversationBubblePresentation {
  var tail = ConversationBubbleLayout.Tail.top {
    didSet { if tail != oldValue { onTailChanged?(tail, tailOffset) } }
  }
  @ObservationIgnored var tailOffset: CGFloat = 200 {
    didSet { if tailOffset != oldValue { onTailChanged?(tail, tailOffset) } }
  }
  @ObservationIgnored var onTailChanged: ((ConversationBubbleLayout.Tail, CGFloat) -> Void)?
}

struct ConversationBubbleView<Content: View>: View {
  let presentation: ConversationBubblePresentation
  let content: Content
  var body: some View {
    content.clipShape(
      RoundedRectangle(
        cornerRadius: ConversationBubbleOutline.cornerRadius - ConversationBubbleChrome.borderWidth)
    )
    .padding(ConversationBubbleChrome.borderWidth)
    .padding(contentInsets)
    .background(ConversationBubbleChrome(presentation: presentation))
  }
  private var contentInsets: EdgeInsets {
    let height = ConversationBubbleLayout.tailHeight
    return EdgeInsets(
      top: presentation.tail == .top ? height : 0,
      leading: presentation.tail == .left ? height : 0,
      bottom: presentation.tail == .bottom ? height : 0,
      trailing: presentation.tail == .right ? height : 0)
  }

}
