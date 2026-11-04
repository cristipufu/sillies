/// App comparisons preserve every production tool. Restricted profiles are explicit ablations.
enum BenchmarkToolProfile: String, Codable, CaseIterable, Sendable {
  case none, search, personal, app, expanded8, expanded12

  func includes(_ name: String) -> Bool {
    switch self {
    case .none: false
    case .search: name == "search_vault"
    case .personal: ["search_vault", "search_memories", "save_memory"].contains(name)
    case .app, .expanded8, .expanded12: true
    }
  }

  func distractorCount(baseCount: Int) -> Int {
    switch self {
    case .expanded8: max(0, 8 - baseCount)
    case .expanded12: max(0, 12 - baseCount)
    default: 0
    }
  }
}
