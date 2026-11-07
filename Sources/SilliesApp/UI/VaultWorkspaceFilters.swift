import SilliesCore
import SwiftUI

struct VaultWorkspaceFilters: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: VaultWorkspaceModel
  var conversations: VaultConversationsModel?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 14) {
        Label("Filter", systemImage: "line.3.horizontal.decrease").foregroundStyle(theme.secondary)
        if model.scope != .conversations { dateAndTagFilters }
        Spacer(minLength: 0)
        Button("Clear filters", action: model.clearFilters).buttonStyle(.plain)
          .disabled(model.activeFilterCount == 0)
      }
      if model.scope != .conversations, model.dateFilter == .range {
        HStack(spacing: 16) {
          DatePicker(
            "From", selection: $model.fromDate, in: ...model.untilDate, displayedComponents: .date)
          DatePicker(
            "Until", selection: $model.untilDate, in: model.fromDate..., displayedComponents: .date)
          Spacer(minLength: 0)
        }
      }
      HStack(spacing: 20) {
        if model.scope != .conversations {
          VaultSourceFilterPicker(
            kind: .app, selection: $model.sourceFilter.appName, library: model.vault.library)
        }
        VaultSourceFilterPicker(
          kind: .companion, selection: $model.sourceFilter.companionID,
          library: model.vault.library,
          additionalChoices: { text in
            try await conversations?.companionChoices(matching: text) ?? []
          }
        )
        if model.scope != .conversations {
          VaultSourceFilterPicker(
            kind: .language, selection: $model.sourceFilter.languageIdentifier,
            library: model.vault.library)
          Spacer(minLength: 0)
          Picker("Skill", selection: $model.kindFilter) {
            Text("All types").tag(Optional<CompanionSkillKind>.none)
            ForEach(
              [CompanionSkillKind.listen, .participate, .record, .snap, .explain, .stash],
              id: \.self
            ) { kind in
              Text(kind.title).tag(Optional(kind))
            }
          }.labelsHidden().fixedSize()
        }
      }
    }.font(.system(size: 12)).padding(.horizontal, 18).padding(.vertical, 10).background(
      theme.soft.opacity(0.4))
  }
  private var dateAndTagFilters: some View {
    Group {
      TextField(
        "Tag", text: Binding(get: { model.tag ?? "" }, set: { model.tag = $0.isEmpty ? nil : $0 })
      )
      .textFieldStyle(.roundedBorder).frame(maxWidth: 140)
      Picker("Date", selection: $model.dateFilter) {
        Text("Any time").tag(VaultWorkspaceModel.DateFilter.any)
        Text("Past week").tag(VaultWorkspaceModel.DateFilter.week)
        Text("Past month").tag(VaultWorkspaceModel.DateFilter.month)
        Text("Date range").tag(VaultWorkspaceModel.DateFilter.range)
      }.labelsHidden().fixedSize()
    }
  }
}
