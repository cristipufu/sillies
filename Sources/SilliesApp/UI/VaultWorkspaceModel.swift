import Foundation
import Observation
import SilliesCore
import SilliesPersistence
import SilliesVault

/// Workspace navigation keeps only one bounded result page and one bounded editing surface.
@MainActor @Observable final class VaultWorkspaceModel {
  enum DateFilter: Hashable { case any, week, month, range }
  struct SearchIdentity: Hashable {
    let query: VaultWorkspaceQuery
    let revision: Int
  }
  let navigation = VaultNavigation()
  let vault: SessionVaultStore
  let search: VaultWorkspaceSearch
  let document: VaultDocumentModel
  let searchPreparation: VaultSearchPreparationModel
  let passageMatches: VaultPassageMatchesModel
  var scope = VaultWorkspaceQuery.Scope.all
  var searchText = "" {
    didSet { if searchText.isEmpty, ordering == .relevance { ordering = .newest } }
  }
  var ordering = VaultWorkspaceQuery.Ordering.newest
  var textMatching = VaultTextMatching.words
  var collectionID: UUID?
  var tag: String?
  var sourceFilter = VaultSourceFilter()
  var kindFilter: CompanionSkillKind?
  var showsFilters = false
  var dateFilter = DateFilter.any
  var fromDate = Date()
  var untilDate = Date()
  var selectedIDs: Set<UUID> = []
  var showsSidebar = true
  var composer: VaultNavigation.Composer? {
    if case .composer(let composer) = navigation.page { composer } else { nil }
  }
  var quotation: VaultQuotedPassage? {
    if case .quotation(let passage) = navigation.page { passage } else { nil }
  }
  var sidebarSelection: VaultNavigation.SidebarSelection? {
    switch navigation.page {
    case .storage: .storage
    case .library: collectionID.map { .collection($0) } ?? .scope(scope)
    case .composer, .quotation: nil
    }
  }
  var composeTitle = ""
  var composeLink = ""
  var composeNotes = ""
  var records: [VaultDocumentHeader] { search.records }
  var related: [VaultDocumentHeader] { search.related(to: query) }
  var isFindingRelated: Bool { search.isFindingRelated }
  var meaningAvailability: VaultRelatedSearchResult.Availability? { search.meaningAvailability }
  var showsPreviousResults: Bool { !records.isEmpty && search.appliedQuery != query }
  private(set) var collections: [VaultCollection] = []
  private(set) var savedSearches: [VaultSavedSearch] = []
  var isLoading: Bool { search.isLoading }
  private(set) var isOpening = false
  private(set) var isSaving = false
  private var actionError: String?
  var error: String? { actionError ?? search.error }
  private(set) var selectedID: UUID?
  var pageNumber: Int { search.pageNumber }
  var canReturnToPreviousPage: Bool { search.canRetreat }
  var hasMore: Bool { search.hasMore }
  private(set) var isPresented = false
  private var lifetime = UUID()
  private var openingRequest = UUID()
  private var currentCheckpoint: VaultNavigation.Checkpoint {
    .init(
      page: navigation.page, query: query,
      document: selectedID.map {
        .init(
          id: $0,
          pane: document.header?.id == $0 ? document.pane : nil,
          location: document.visibleTextLocation?.recordID == $0
            ? document.visibleTextLocation : nil)
      },
      composition: composer.map { _ in
        .init(title: composeTitle, link: composeLink, notes: composeNotes)
      })
  }
  @ObservationIgnored private var selectionTask: Task<Void, Never>?
  var canGoBack: Bool { navigation.canGoBack }
  var canGoForward: Bool { navigation.canGoForward }
  var query: VaultWorkspaceQuery {
    var value = VaultWorkspaceQuery(scope: scope, text: searchText, ordering: ordering)
    value.textMatching = textMatching == .words ? nil : textMatching
    value.collectionID = collectionID
    value.tag = tag
    value.source = sourceFilter.isEmpty ? nil : sourceFilter
    value.kind = kindFilter
    let calendar = Calendar.current
    switch dateFilter {
    case .any: break
    case .week:
      value.from = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date()))
    case .month:
      value.from = calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: Date()))
    case .range:
      value.from = calendar.startOfDay(for: fromDate)
      value.until = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: untilDate))
    }
    return value
  }
  var searchIdentity: SearchIdentity { .init(query: query, revision: vault.searchRevision) }
  var includesConversations: Bool {
    scope == .all && collectionID == nil && tag == nil && dateFilter == .any && !searchText.isEmpty
      && sourceFilter.appName == nil && sourceFilter.languageIdentifier == nil && kindFilter == nil
      && textMatching == .words
  }
  var activeFilterCount: Int {
    if scope == .conversations { return sourceFilter.companionID == nil ? 0 : 1 }
    return [
      tag != nil, dateFilter != .any, sourceFilter.appName != nil,
      sourceFilter.companionID != nil, sourceFilter.languageIdentifier != nil, kindFilter != nil,
    ].filter { $0 }.count
  }
  var canEditSelection: Bool {
    guard isPresented, navigation.page == .library, !isSaving, !isLoading,
      search.appliedQuery == query, !selectedIDs.isEmpty
    else { return false }
    return selectedIDs.isSubset(of: Set((records + related).map(\.id)))
  }
  var canSaveComposition: Bool {
    guard isPresented, !isSaving, let composer else { return false }
    switch composer {
    case .note: return true
    case .link: return !composeLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .collection, .savedSearch, .renameCollection, .renameSearch:
      return !composeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  func clearFilters() {
    tag = nil
    dateFilter = .any
    sourceFilter = .init()
    kindFilter = nil
  }

  init(vault: SessionVaultStore) {
    self.vault = vault
    search = VaultWorkspaceSearch(vault: vault)
    document = VaultDocumentModel(vault: vault)
    searchPreparation = VaultSearchPreparationModel(library: vault.library)
    passageMatches = VaultPassageMatchesModel(library: vault.library)
  }

  func resume() {
    guard !isPresented else { return }
    lifetime = UUID()
    isPresented = true
    search.resume()
    if navigation.page == .library, let selectedID { open(selectedID) }
  }

  func refresh() async {
    guard isPresented else { return }
    let token = lifetime
    let request = query
    if search.appliedQuery != request { selectedIDs = [] }
    passageMatches.stop()
    guard await search.refresh(request) else { return }
    guard lifetime == token, query == request, isPresented, !Task.isCancelled else { return }
    selectedIDs.formIntersection(Set((records + related).map(\.id)))
    do {
      let collections = try await vault.library.collections()
      let saved = try await vault.library.savedSearches()
      guard lifetime == token, query == request, isPresented, !Task.isCancelled else { return }
      self.collections = collections
      savedSearches = saved
      actionError = nil
      await document.refreshHeader()
    } catch { report(error, during: token) }
  }

  func selectScope(_ scope: VaultWorkspaceQuery.Scope) {
    if navigation.page == .library, self.scope == scope, collectionID == nil, tag == nil {
      navigation.reselectCurrentPage()
      return
    }
    navigation.visit(.library, leaving: currentCheckpoint)
    clearSelection()
    self.scope = scope
    if scope == .conversations { textMatching = .words }
    collectionID = nil
    tag = nil
  }

  func selectCollection(_ id: UUID) {
    if navigation.page == .library, collectionID == id, tag == nil {
      navigation.reselectCurrentPage()
      return
    }
    navigation.visit(.library, leaving: currentCheckpoint)
    clearSelection()
    scope = .all
    collectionID = id
    tag = nil
  }

  func apply(_ saved: VaultSavedSearch) {
    navigation.visit(.library, leaving: currentCheckpoint)
    clearSelection()
    applyQuery(saved.query)
  }

  private func applyQuery(_ query: VaultWorkspaceQuery) {
    scope = query.scope
    searchText = query.text
    ordering = query.ordering
    textMatching = scope == .conversations ? .words : query.textMatching ?? .words
    collectionID = query.collectionID
    tag = query.tag
    sourceFilter = query.source ?? .init()
    kindFilter = query.kind
    if let from = query.from {
      fromDate = from
      untilDate = query.until?.addingTimeInterval(-1) ?? Date()
      dateFilter = .range
      showsFilters = true
    } else {
      dateFilter = .any
    }
  }

  func select(_ id: UUID) {
    guard isPresented, id != selectedID else { return }
    navigation.visit(.library, leaving: currentCheckpoint)
    open(id)
  }

  func visit(_ location: VaultBlockLocation) {
    guard isPresented else { return }
    navigation.visit(.library, leaving: currentCheckpoint)
    open(location.recordID, at: location)
  }

  func openSource(_ reference: VaultSourceReference) async {
    let token = lifetime
    do {
      let location = try await vault.library.sourceLocation(reference)
      guard isPresented, lifetime == token, !Task.isCancelled else { return }
      guard let location else {
        actionError = String(
          localized:
            "The original passage was changed or removed. Your saved quotation is still available.")
        return
      }
      visit(location)
    } catch { report(error, during: token) }
  }

  func openEvidence(_ passage: VaultEvidencePassage, action: VaultEvidenceAction) async {
    guard isPresented else { return }
    let token = lifetime
    let request = UUID()
    suspendDocument()
    openingRequest = request
    document.clearEvidence()
    isOpening = true
    defer { if openingRequest == request { isOpening = false } }
    do {
      await document.flush()
      guard ownsEvidenceRequest(request, lifetime: token), document.canNavigate else { return }
      guard let location = try await vault.library.evidenceLocation(passage) else {
        guard ownsEvidenceRequest(request, lifetime: token) else { return }
        reportUnavailableEvidence()
        return
      }
      guard ownsEvidenceRequest(request, lifetime: token) else { return }
      navigation.visit(.library, leaving: currentCheckpoint)
      selectedID = location.recordID
      selectedIDs = [location.recordID]
      await document.open(location.recordID, match: location)
      guard ownsEvidenceRequest(request, lifetime: token) else { return }
      guard document.revealEvidence(passage, action: action) else {
        reportUnavailableEvidence()
        return
      }
      actionError = nil
    } catch { if ownsEvidenceRequest(request, lifetime: token) { report(error, during: token) } }
  }

  private func ownsEvidenceRequest(_ request: UUID, lifetime token: UUID) -> Bool {
    isPresented && lifetime == token && openingRequest == request && !Task.isCancelled
  }
  private func reportUnavailableEvidence() {
    actionError = String(
      localized:
        "This passage changed or is no longer available. The saved excerpt is still in Chat.")
  }

  func quoteSelection() async {
    let token = lifetime
    let source = document.editor.location
    await document.editor.flush()
    guard isPresented, lifetime == token, document.editor.location == source,
      !document.editor.isDirty, !Task.isCancelled
    else { return }
    do {
      guard let passage = try document.editor.quotedSelection(title: document.header?.title ?? "")
      else { return }
      navigation.visit(.quotation(passage), leaving: currentCheckpoint)
      document.playback.stop()
    } catch { report(error, during: lifetime) }
  }

  func reveal(_ id: UUID) {
    navigation.visit(.library, leaving: currentCheckpoint)
    scope = .all
    collectionID = nil
    tag = nil
    searchText = ""
    dateFilter = .any
    sourceFilter = .init()
    kindFilter = nil
    open(id)
  }

  private func open(
    _ id: UUID, at destination: VaultBlockLocation? = nil, restoring pane: VaultDocumentPane? = nil
  ) {
    let request = UUID()
    suspendDocument()
    openingRequest = request
    isOpening = true
    selectedID = id
    selectedIDs = [id]
    let match =
      destination ?? (records + related).first { $0.id == id }?.match
      ?? (document.header?.id == id ? document.visibleTextLocation : nil)
    let restoredPane =
      pane ?? (match == nil && document.header?.id == id ? document.pane : nil)
    selectionTask = Task { [weak self] in
      guard let self else { return }
      defer { if openingRequest == request { isOpening = false } }
      await document.open(id, match: match, restoring: restoredPane)
      guard !Task.isCancelled, selectedID == id else { return }
      if document.header?.id != id {
        // Keep a failed first selection available for Retry; no unrelated document replaced it.
        guard document.header != nil || document.error == nil else { return }
        selectedID = document.header?.id
        selectedIDs = Set(document.header.map { [$0.id] } ?? [])
      }
    }
  }

  func retrySelection() {
    guard isPresented, let selectedID else { return }
    open(selectedID)
  }

  func goBack() {
    guard isPresented, let destination = navigation.previous(leaving: currentCheckpoint) else {
      return
    }
    restore(destination)
  }
  func goForward() {
    guard isPresented, let destination = navigation.next(leaving: currentCheckpoint) else { return }
    restore(destination)
  }
  private func restore(_ destination: VaultNavigation.Checkpoint) {
    clearSelection()
    applyQuery(destination.query)
    if let composition = destination.composition {
      composeTitle = composition.title
      composeLink = composition.link
      composeNotes = composition.notes
    }
    if let selected = destination.document {
      selectedID = selected.id
      selectedIDs = [selected.id]
      if destination.page == .library {
        open(selected.id, at: selected.location, restoring: selected.pane)
      }
    }
  }

  func showLibrary() {
    guard navigation.page != .library else { return }
    navigation.visit(.library, leaving: currentCheckpoint)
    if let selectedID { open(selectedID) }
  }

  func updateSearchText(_ text: String) {
    showLibrary()
    searchText = text
  }

  func selectTextMatching(_ matching: VaultTextMatching) {
    showLibrary()
    textMatching = matching
  }

  func showStorage() {
    guard navigation.page != .storage else {
      navigation.reselectCurrentPage()
      return
    }
    navigation.visit(.storage, leaving: currentCheckpoint)
    suspendDocument()
  }

  private func clearSelection() {
    suspendDocument()
    selectedID = nil
    selectedIDs = []
    actionError = nil
  }

  private func suspendDocument() {
    openingRequest = UUID()
    selectionTask?.cancel()
    selectionTask = nil
    isOpening = false
    document.stop()
  }

  func nextPage() async {
    guard search.advance() else { return }
    await refresh()
  }
  func previousPage() async {
    guard search.retreat() else { return }
    await refresh()
  }

  func begin(_ composer: VaultNavigation.Composer) {
    guard isPresented, self.composer != composer else { return }
    navigation.visit(.composer(composer), leaving: currentCheckpoint)
    suspendDocument()
    composeTitle = ""
    composeLink = ""
    composeNotes = ""
    actionError = nil
    switch composer {
    case .renameCollection(let id): composeTitle = collections.first { $0.id == id }?.name ?? ""
    case .renameSearch(let id): composeTitle = savedSearches.first { $0.id == id }?.name ?? ""
    default: break
    }
  }

  func newNote() async {
    guard isPresented, !isSaving else { return }
    let token = lifetime
    let page = navigation.transitionID
    isSaving = true
    defer { isSaving = false }
    await document.flush()
    guard document.canNavigate, isPresented, lifetime == token, navigation.transitionID == page,
      !Task.isCancelled
    else { return }
    do {
      var metadata = VaultDocumentMetadata(
        kind: .note, title: String(localized: "Untitled note"), modifiedAt: Date())
      if let collectionID { metadata.collectionIDs = [collectionID] }
      let header = try await vault.createDocument(metadata: metadata)
      guard isPresented, lifetime == token, navigation.transitionID == page, !Task.isCancelled
      else { return }
      showCreatedDocument(header)
      await refresh()
    } catch { report(error, during: token) }
  }

  func saveComposedItem() async {
    guard canSaveComposition, let composer else { return }
    let token = lifetime
    let page = navigation.transitionID
    isSaving = true
    defer { isSaving = false }
    do {
      let header = try await persistComposition(composer)
      guard isPresented, lifetime == token, navigation.transitionID == page, !Task.isCancelled
      else { return }
      if let header { showCreatedDocument(header) } else { showLibrary() }
      await refresh()
    } catch { report(error, during: token) }
  }

  private func persistComposition(_ composer: VaultNavigation.Composer) async throws
    -> VaultDocumentHeader?
  {
    switch composer {
    case .collection:
      try await vault.library.saveCollection(.init(name: composeTitle))
    case .savedSearch:
      try await vault.library.saveSearch(.init(name: composeTitle, query: query))
    case .renameCollection(let id):
      try await vault.library.saveCollection(.init(id: id, name: composeTitle))
    case .renameSearch(let id):
      guard let search = savedSearches.first(where: { $0.id == id }) else { return nil }
      try await vault.library.saveSearch(.init(id: id, name: composeTitle, query: search.query))
    case .note, .link:
      return try await vault.createDocument(
        metadata: composedMetadata(composer), notes: composeNotes)
    }
    return nil
  }

  private func composedMetadata(_ composer: VaultNavigation.Composer) throws
    -> VaultDocumentMetadata
  {
    var metadata = VaultDocumentMetadata(
      kind: composer == .link ? .link : .note, modifiedAt: Date())
    metadata.title = composeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if composer == .link {
      guard let url = URL(string: composeLink.trimmingCharacters(in: .whitespacesAndNewlines))
      else {
        throw VaultLinkError.invalidURL
      }
      metadata.link = try VaultLink(url: url)
      if metadata.title.isEmpty { metadata.title = metadata.link?.title ?? "" }
    } else if metadata.title.isEmpty {
      metadata.title = String(localized: "Untitled note")
    }
    if let collectionID { metadata.collectionIDs = [collectionID] }
    return metadata
  }

  private func showCreatedDocument(_ header: VaultDocumentHeader) {
    navigation.visit(.library, leaving: currentCheckpoint)
    scope = collectionID == nil ? (header.metadata.kind == .link ? .links : .notes) : .all
    searchText = ""
    tag = nil
    dateFilter = .any
    sourceFilter = .init()
    kindFilter = nil
    open(header.id)
  }

  func editSelection(_ edit: VaultDocumentEdit) async {
    guard canEditSelection else { return }
    let token = lifetime
    let page = navigation.transitionID
    let request = query
    let ids = selectedIDs
    isSaving = true
    defer { isSaving = false }
    do {
      await document.flush()
      guard document.canNavigate, isPresented, lifetime == token,
        navigation.transitionID == page, query == request, selectedIDs == ids, !Task.isCancelled
      else { return }
      try await vault.editWorkspace(ids: ids, edit)
      guard isPresented, lifetime == token, navigation.transitionID == page, query == request,
        !Task.isCancelled
      else { return }
      if let selectedID { await document.open(selectedID) }
      await refresh()
    } catch { report(error, during: token) }
  }

  func removeCollection(_ id: UUID) async {
    guard isPresented else { return }
    let token = lifetime
    do {
      try await vault.library.removeCollection(id: id)
      guard isPresented, lifetime == token, !Task.isCancelled else { return }
      if collectionID == id { selectScope(.all) }
      await refresh()
    } catch { report(error, during: token) }
  }

  func removeSearch(_ id: UUID) async {
    guard isPresented else { return }
    let token = lifetime
    do {
      try await vault.library.removeSavedSearch(id: id)
      guard isPresented, lifetime == token, !Task.isCancelled else { return }
      await refresh()
    } catch { report(error, during: token) }
  }

  func emptyTrash() async {
    guard isPresented, !isSaving else { return }
    isSaving = true
    let token = lifetime
    defer { isSaving = false }
    do {
      try await vault.emptyTrash()
      await refresh()
    } catch { report(error, during: token) }
  }
  func recoverDraftAsNote() async {
    guard isPresented else { return }
    let token = lifetime
    let page = navigation.transitionID
    do {
      guard let id = try await document.editor.recoverAsNote() else { return }
      guard isPresented, lifetime == token, navigation.transitionID == page, !Task.isCancelled
      else { return }
      selectScope(.notes)
      searchText = ""
      dateFilter = .any
      sourceFilter = .init()
      kindFilter = nil
      select(id)
      await refresh()
    } catch { report(error, during: token) }
  }

  private func report(_ failure: Error, during token: UUID) {
    guard !(failure is CancellationError) else { return }
    fputs("Vault workspace action failed: \(failure)\n", stderr)
    guard isPresented, lifetime == token else { return }
    actionError = failure.localizedDescription
  }

  func stop() {
    isPresented = false
    lifetime = UUID()
    suspendDocument()
    search.stop()
    passageMatches.stop()
  }
}
