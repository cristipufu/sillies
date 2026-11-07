import SilliesCore

package struct VaultRelatedSearchResult: Sendable {
  package enum Availability: Equatable, Sendable {
    case ready, preparing, unavailable, timedOut, changed
    case failed(String)
  }
  package let matches: [VaultSearchMatch]
  package let availability: Availability
}
