import SilliesChat
import SilliesCore
import SwiftUI

struct ChatPersonalFactsView: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: ChatPersonalFacts
  let companionName: String
  @State private var scope = PersonalFact.Scope.companion
  private enum Layout {
    static let gap: CGFloat = 12
    static let inset: CGFloat = 12
    static let corner: CGFloat = 12
    static let editorHeight: CGFloat = 90
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.gap) {
      if model.isEditing {
        editor
      } else {
        Text(
          "Facts you choose for replies, within the model’s context budget. Only you can change these."
        )
        .font(.caption).foregroundStyle(theme.secondary)
        Picker("Share with", selection: $scope) {
          Text("\(companionName) only").tag(PersonalFact.Scope.companion)
          Text("All companions").tag(PersonalFact.Scope.shared)
        }.pickerStyle(.segmented)
        ScrollView {
          VStack(alignment: .leading, spacing: Layout.gap) {
            ForEach(model.facts.filter { $0.scope == scope }) { fact in
              VStack(alignment: .leading, spacing: Layout.gap) {
                Label(fact.fact.key, systemImage: "pin.fill").font(.subheadline.bold())
                Text(fact.fact.value).textSelection(.enabled)
                HStack {
                  Button("Edit") { model.begin(fact) }
                  Spacer()
                  Button("Unpin", role: .destructive) { Task { await model.remove(fact) } }
                }.buttonStyle(SoftButtonStyle()).disabled(!model.canChange() || model.isSaving)
              }.padding(Layout.inset).background(
                theme.card, in: RoundedRectangle(cornerRadius: Layout.corner))
            }
            if !model.facts.contains(where: { $0.scope == scope }) {
              Text("Pin your preferred name or a useful preference.")
                .foregroundStyle(theme.secondary).padding(.vertical, Layout.inset)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        Button("Add pinned fact") {
          model.begin()
          model.scope = scope
        }
        .buttonStyle(AccentButtonStyle()).disabled(!model.canChange() || model.isSaving)
        Text(
          "Four shared facts, plus four for each companion. A fact for this companion takes priority over a shared fact with the same topic."
        )
        .font(.caption).foregroundStyle(theme.secondary)
      }
      if let failure = model.failure {
        Text(failure).font(.caption).foregroundStyle(theme.warning).textSelection(.enabled)
      }
      if model.isSaving { ProgressView().controlSize(.small) }
    }.task { await model.load() }.onDisappear { model.stop() }
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: Layout.gap) {
      TextField("Memory topic", text: $model.topic).textFieldStyle(.roundedBorder)
      Picker("Share with", selection: $model.scope) {
        Text("\(companionName) only").tag(PersonalFact.Scope.companion)
        Text("All companions").tag(PersonalFact.Scope.shared)
      }.disabled(!model.canChooseScope || model.isSaving)
      TextEditor(text: $model.value).scrollContentBackground(.hidden)
        .frame(height: Layout.editorHeight).padding(Layout.inset)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Layout.corner))
        .accessibilityLabel("Pinned fact")
      Text("\(model.value.count)/\(PersonalFact.maximumValueCharacters)")
        .font(.caption.monospacedDigit()).foregroundStyle(theme.secondary)
      Text("This describes you, not the companion. It stays until you edit or unpin it.")
        .font(.caption).foregroundStyle(theme.secondary)
      Spacer(minLength: 0)
      HStack {
        Button("Cancel") { model.cancelEditing() }.buttonStyle(SoftButtonStyle())
          .disabled(model.isSaving)
        Spacer()
        Button("Save memory") { Task { await model.save() } }
          .buttonStyle(AccentButtonStyle()).disabled(!model.canSave)
      }
    }.disabled(model.isSaving)
  }
}
