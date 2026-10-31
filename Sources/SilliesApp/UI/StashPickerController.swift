import AppKit
import SilliesCore
import SwiftUI

struct StashPickerView: View {
  let vault: SessionVaultStore
  let paste: PasteBackCoordinator
  let choose: (SessionRecord) -> Void
  let close: () -> Void
  @State private var model: SessionVaultModel
  @State private var selected: UUID?
  @FocusState private var searchFocused: Bool
  init(
    vault: SessionVaultStore, paste: PasteBackCoordinator,
    choose: @escaping (SessionRecord) -> Void,
    close: @escaping () -> Void
  ) {
    self.vault = vault
    self.paste = paste
    self.choose = choose
    self.close = close
    let model = SessionVaultModel(vault: vault)
    model.selectedFilter = .stash
    _model = State(initialValue: model)
  }
  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: 14) {
      SessionIdentityHeader(title: "Pocket Stash", symbol: "tray.full.fill") {
        Text(paste.actionTitle).lineLimit(1)
      } accessory: {
        EmptyView()
      }
      TextField("Search Pocket Stash…", text: $model.searchQuery).textFieldStyle(.roundedBorder)
        .focused($searchFocused).onSubmit { activateSelection() }
        .onKeyPress(.downArrow) {
          moveSelection(by: 1)
          return .handled
        }
        .onKeyPress(.upArrow) {
          moveSelection(by: -1)
          return .handled
        }
      if let notice = paste.notice {
        Text(notice).font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      if model.isSearching { ProgressView().controlSize(.small) }
      if let error = model.searchError { Text(error).foregroundStyle(.red) }
      List(model.filteredRecords, selection: $selected) { record in
        VStack(alignment: .leading, spacing: 4) {
          Text(record.primaryText).lineLimit(3)
          Text(record.createdAt, style: .date).font(.caption).foregroundStyle(
            SilliesTheme.secondary)
        }.padding(.vertical, 4).tag(record.id)
          .listRowBackground(SilliesTheme.card)
          .onTapGesture(count: 2) { choose(record) }
      }.scrollContentBackground(.hidden)
        .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SilliesTheme.border))
        .overlay {
          if model.filteredRecords.isEmpty, !model.isSearching {
            ContentUnavailableView(
              model.searchQuery.isEmpty ? "Your stash is empty" : "No matching stashes",
              systemImage: "tray",
              description: Text("Save text or a link from the clipboard to find it here."))
          }
        }
      if model.hasMoreResults { Button("Show more") { model.showMore() } }
      HStack {
        Text("Return to choose · Escape to close").font(.caption).foregroundStyle(
          SilliesTheme.secondary)
        Spacer()
        Button(paste.actionTitle) { activateSelection() }
          .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(
            model.filteredRecords.isEmpty || paste.isPasting)
      }
    }.padding(24).frame(minWidth: 560, minHeight: 440)
      .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink).tint(SilliesTheme.accent)
      .task(id: model.searchIdentity) { await model.refreshSearch() }
      .onAppear { searchFocused = true }
      .onExitCommand(perform: close)
  }
  private func moveSelection(by offset: Int) {
    let records = model.filteredRecords
    guard !records.isEmpty else { return }
    let current = records.firstIndex { $0.id == selected } ?? (offset > 0 ? -1 : records.count)
    selected = records[min(max(current + offset, 0), records.count - 1)].id
  }
  private func activateSelection() {
    if let record = model.filteredRecords.first(where: { $0.id == selected })
      ?? model.filteredRecords.first
    {
      choose(record)
    }
  }
}

@MainActor final class StashPickerController {
  let paste = PasteBackCoordinator()
  private let vault: SessionVaultStore
  private var window: NSWindow?
  private var opening: Task<Void, Never>?
  private var insertion: Task<Void, Never>?
  init(vault: SessionVaultStore) { self.vault = vault }
  func show() {
    opening?.cancel()
    opening = Task { [weak self] in
      guard let self else { return }
      await self.paste.captureDestination()
      guard !Task.isCancelled else { return }
      self.present()
    }
  }
  private func present() {
    if window == nil {
      let window = NSPanel(
        contentRect: CGRect(x: 0, y: 0, width: 600, height: 500),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.title = "Sillies · Pocket Stash"
      AppContentWindowStacking.shared.register(window)
      window.isReleasedWhenClosed = false
      window.contentMinSize = CGSize(width: 560, height: 440)
      window.contentViewController = NSHostingController(
        rootView: StashPickerView(
          vault: vault, paste: paste,
          choose: { [weak self] in self?.choose($0) }, close: { [weak self] in self?.stop() }))
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
  private func choose(_ record: SessionRecord) {
    window?.orderOut(nil)
    guard paste.destination != nil else {
      vault.copyText(record.primaryText)
      return
    }
    insertion = Task { [weak self] in
      guard let self else { return }
      do { try await paste.paste(record.primaryText) } catch {
        if !Task.isCancelled { present() }
        fputs("Stash insertion failed: \(error.localizedDescription)\n", stderr)
      }
    }
  }
  func stop() {
    opening?.cancel()
    insertion?.cancel()
    paste.release()
    window?.orderOut(nil)
  }
}
