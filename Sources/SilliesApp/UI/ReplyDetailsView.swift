import SilliesCore
import SwiftUI

/// Explicit inspection stays separate from the chat's message and scrolling surfaces.
struct ReplyDetailsView: View {
  private enum Layout {
    static let width: CGFloat = 360
    static let height: CGFloat = 420
    static let inset: CGFloat = 20
    static let gap: CGFloat = 14
    static let cardInset: CGFloat = 12
    static let corner: CGFloat = 14
  }
  @Environment(\.silliesTheme) private var theme
  @Environment(\.dismiss) private var dismiss
  let message: ChatMessage

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.gap) {
      HStack {
        Label("Reply details", systemImage: "sparkle.magnifyingglass").font(.headline)
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle())
      }
      Text(
        "Context prepared for this reply, with the results returned by its tools. This does not reveal the model’s internal reasoning."
      )
      .font(.caption).foregroundStyle(theme.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: Layout.gap) {
          contextCard
          sources
          toolEvidence
          if let context = message.contextInspection {
            DisclosureGroup("Technical details") {
              VStack(alignment: .leading) {
                Text("Earlier tool results: \(context.previousToolResults)")
                Text("Available tools: \(context.availableTools)")
                Text("Working context: \(context.workingContextTokens) tokens")
              }.font(.caption).foregroundStyle(theme.secondary)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.font(.callout).padding(Layout.inset).frame(width: Layout.width, height: Layout.height)
      .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
  }

  @ViewBuilder private var contextCard: some View {
    if let context = message.contextInspection {
      VStack(alignment: .leading, spacing: Layout.gap) {
        Label(
          "Recent messages: \(context.recentMessages)", systemImage: "bubble.left.and.bubble.right")
        if !context.notes.summary.isEmpty {
          DisclosureGroup("Conversation notes") {
            VStack(alignment: .leading, spacing: Layout.gap) {
              Text(context.notes.summary).textSelection(.enabled)
              Text("Generated notes can be incomplete or mistaken.")
                .font(.caption).foregroundStyle(theme.secondary)
            }
          }
        }
      }.padding(Layout.cardInset).background(
        theme.card, in: RoundedRectangle(cornerRadius: Layout.corner))
    }
  }

  @ViewBuilder private var sources: some View {
    if !message.sources.isEmpty {
      Text("Returned sources").font(.subheadline.bold())
      ForEach(message.sources) { source in
        VStack(alignment: .leading, spacing: Layout.gap) {
          Text(source.title).fontWeight(.medium)
          if source.retrieval == .semantic {
            Label("Related by meaning", systemImage: "sparkles").font(.caption).foregroundStyle(
              theme.accent)
          }
          Text(source.excerpt).foregroundStyle(theme.secondary).textSelection(.enabled)
        }.padding(Layout.cardInset).background(
          theme.card, in: RoundedRectangle(cornerRadius: Layout.corner))
      }
    }
  }

  @ViewBuilder private var toolEvidence: some View {
    if message.exchanges.isEmpty {
      Text("No tools were called for this reply.").foregroundStyle(theme.secondary)
    } else {
      Text("Tool evidence").font(.subheadline.bold())
      ForEach(Array(message.exchanges.enumerated()), id: \.offset) { _, exchange in
        DisclosureGroup {
          Text(exchange.result).font(.system(.caption, design: .monospaced))
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        } label: {
          Text(exchange.call.name).font(.caption.monospaced())
        }
      }
    }
  }
}
