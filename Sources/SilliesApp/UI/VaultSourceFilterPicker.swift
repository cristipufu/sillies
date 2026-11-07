import SilliesCore
import SilliesVault
import SwiftUI

struct VaultSourceFilterPicker: View {
  @Environment(\.silliesTheme) private var theme
  @Binding var selection: String?
  @State private var model: VaultSourceFacetModel
  @State private var query = ""
  @State private var isPresented = false
  @State private var selectedTitle: String?
  private static let popoverSize = CGSize(width: 280, height: 320)

  init(
    kind: VaultSourceFacet.Kind, selection: Binding<String?>, library: VaultLibrary,
    additionalChoices: ((String) async throws -> [VaultSourceFacet])? = nil
  ) {
    _selection = selection
    _model = State(
      initialValue: VaultSourceFacetModel(
        library: library, kind: kind,
        additionalChoices: additionalChoices))
  }
  private var title: String {
    switch model.kind {
    case .app: String(localized: "App")
    case .companion: String(localized: "Companion")
    case .language: String(localized: "Language")
    }
  }
  var body: some View {
    Button {
      query = ""
      isPresented.toggle()
    } label: {
      HStack(spacing: 6) {
        Text(selection == nil ? title : selectedTitle ?? selection ?? title).lineLimit(1)
        Image(systemName: "chevron.down").font(.caption2)
      }.foregroundStyle(selection == nil ? theme.secondary : theme.accent)
    }.buttonStyle(.plain)
      .popover(isPresented: $isPresented) {
        VStack(alignment: .leading, spacing: 12) {
          Text(title).font(.headline)
          TextField("Filter", text: $query).textFieldStyle(.roundedBorder)
          Button("Clear filter") {
            selection = nil
            isPresented = false
          }
          if model.isLoading { ProgressView().controlSize(.small) }
          if let error = model.error {
            VaultNoticeArea { Text(error).font(.caption).textSelection(.enabled) }
          }
          List(model.choices) { choice in
            Button {
              selectedTitle = displayTitle(choice)
              selection = choice.id
              isPresented = false
            } label: {
              HStack {
                Text(displayTitle(choice)).lineLimit(2)
                Spacer()
                if selection == choice.id { Image(systemName: "checkmark") }
              }.contentShape(Rectangle())
            }.buttonStyle(.plain)
          }.listStyle(.plain).scrollContentBackground(.hidden)
          if model.choices.count == VaultSourceFacet.maximumChoices {
            Text("Type to narrow these choices.").font(.caption).foregroundStyle(theme.secondary)
          }
        }.padding(16).frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
          .background(theme.paper).foregroundStyle(theme.ink)
          .task(id: query) { await model.search(query) }
      }
      .onChange(of: selection) { _, value in
        selectedTitle = model.choices.first { $0.id == value }.map(displayTitle)
      }
  }
  private func displayTitle(_ facet: VaultSourceFacet) -> String {
    if model.kind == .language {
      return Locale.current.localizedString(forIdentifier: facet.id) ?? facet.title
    }
    return facet.title
  }
}
