import Foundation
import Observation
import SilliesCore

/// One visible workspace page, with bounded history of the query and document it replaced.
@MainActor @Observable final class VaultNavigation {
  enum Composer: Equatable {
    case note, link, collection, savedSearch
    case renameCollection(UUID)
    case renameSearch(UUID)
  }
  enum Page: Equatable {
    case library, storage
    case composer(Composer)
    case quotation(VaultQuotedPassage)
  }
  enum SidebarSelection: Equatable {
    case scope(VaultWorkspaceQuery.Scope)
    case collection(UUID)
    case storage
  }
  struct ReadingDestination: Equatable {
    let id: UUID
    let pane: VaultDocumentPane?
    let location: VaultBlockLocation?
  }
  struct Checkpoint: Equatable {
    let page: Page
    let query: VaultWorkspaceQuery
    let document: ReadingDestination?
    var composition: Composition?
  }
  struct Composition: Equatable {
    let title: String
    let link: String
    let notes: String
  }
  private static let maximumHistory = 100
  private(set) var page = Page.library
  private(set) var transitionID = UUID()
  private var back: [Checkpoint] = []
  private var forward: [Checkpoint] = []
  var canGoBack: Bool { !back.isEmpty }
  var canGoForward: Bool { !forward.isEmpty }

  func reselectCurrentPage() { transitionID = UUID() }

  func visit(_ page: Page, leaving checkpoint: Checkpoint) {
    if back.last != checkpoint {
      back.append(checkpoint)
      back = Array(back.suffix(Self.maximumHistory))
    }
    forward.removeAll()
    show(page)
  }

  func previous(leaving checkpoint: Checkpoint) -> Checkpoint? {
    guard let destination = back.popLast() else { return nil }
    forward.append(checkpoint)
    show(destination.page)
    return destination
  }

  func next(leaving checkpoint: Checkpoint) -> Checkpoint? {
    guard let destination = forward.popLast() else { return nil }
    back.append(checkpoint)
    show(destination.page)
    return destination
  }

  private func show(_ page: Page) {
    self.page = page
    transitionID = UUID()
  }
}
