import SilliesChat
import SilliesCore
import SwiftUI

struct ChatClarificationView: View {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.chatReadingSize) private var readingSize
  let question: ChatClarification
  let model: ChatSession
  private enum Layout {
    static let spacing: CGFloat = 10
    static let minimumGap: CGFloat = 4
    static let choiceInset: CGFloat = 10
    static let choiceCornerRadius: CGFloat = 8
    static let cardInset: CGFloat = 12
    static let cardCornerRadius: CGFloat = 12
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.spacing) {
      Label("Your choice", systemImage: "bubble.left.and.text.bubble.right")
        .font(.caption.weight(.semibold)).foregroundStyle(theme.secondary)
      ForEach(question.choices, id: \.self) { choice in
        Button {
          model.answerClarification(question.id, choice: choice)
        } label: {
          HStack {
            Text(choice).font(.system(size: readingSize.points))
              .multilineTextAlignment(.leading).fixedSize(
                horizontal: false, vertical: true)
            Spacer(minLength: Layout.minimumGap)
            Image(systemName: "arrow.up.left").accessibilityHidden(true)
          }.padding(Layout.choiceInset).contentShape(Rectangle())
        }.buttonStyle(.plain).background(
          theme.paper, in: RoundedRectangle(cornerRadius: Layout.choiceCornerRadius)
        )
        .disabled(!model.canAnswerClarification)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(
          model.mode == .talk
            ? String(localized: "Or say your answer.")
            : String(localized: "Or type your own answer below.")
        )
        .font(.caption).foregroundStyle(theme.secondary)
        Spacer(minLength: Layout.minimumGap)
        Button("Dismiss") { model.dismissClarification(question.id) }.buttonStyle(.plain).font(
          .caption)
      }
    }.padding(Layout.cardInset).background(
      theme.card, in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
    )
    .accessibilityElement(children: .contain).accessibilityLabel(question.question)
  }
}
