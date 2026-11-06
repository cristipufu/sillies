import Foundation
import SilliesCore

extension ConversationDatabase {
  private static let maximumPersonalFactBytes = 4_096

  func preparePersonalFacts() throws {
    try sql.transaction {
      try sql.execute(
        "CREATE TABLE personal_facts(id TEXT NOT NULL UNIQUE,owner TEXT NOT NULL,key TEXT NOT NULL,body BLOB NOT NULL,PRIMARY KEY(owner,key))"
      )
      try sql.execute(
        "CREATE TABLE personal_fact_state(id INTEGER PRIMARY KEY CHECK(id=1),revision TEXT NOT NULL)"
      )
      try sql.execute(
        "INSERT INTO personal_fact_state(id,revision) VALUES(1,?)", [.text(UUID().uuidString)])
      try sql.execute("PRAGMA user_version=6")
    }
  }

  public func personalFacts(_ handle: ConversationHandle) throws -> PersonalFactsSnapshot {
    try validate(handle)
    var facts: [PersonalFact] = []
    try sql.rows(
      "SELECT body,owner FROM personal_facts WHERE owner IN ('',?) ORDER BY owner,key LIMIT ?",
      [.text(handle.companionID), .integer(Int64(PersonalFact.maximumPerScope * 2))]
    ) { row in
      let fact = try decoder.decode(
        PersonalFact.self,
        from: VaultSQLConnection.data(row, maximumBytes: Self.maximumPersonalFactBytes))
      let storedOwner = try VaultSQLConnection.text(row, column: 1)
      guard fact.isValid, storedOwner == owner(for: fact.scope, handle: handle) else {
        throw ConversationStorageError.invalidData
      }
      facts.append(fact)
    }
    var revision: UUID?
    try sql.rows("SELECT revision FROM personal_fact_state WHERE id=1") { row in
      revision = UUID(uuidString: try VaultSQLConnection.text(row))
    }
    guard let revision else { throw ConversationStorageError.invalidData }
    return .init(revision: revision, facts: facts)
  }

  public func savePersonalFact(_ request: PersonalFactWrite) throws -> PersonalFactsSnapshot {
    try sql.transaction {
      try validate(request.handle)
      let owner = owner(for: request.scope, handle: request.handle)
      let fact = MemoryFact(
        key: request.fact.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        value: request.fact.value.trimmingCharacters(in: .whitespacesAndNewlines))
      let saved = PersonalFact(
        id: request.replacing?.id ?? UUID(), scope: request.scope, fact: fact)
      guard saved.isValid else { throw PersonalFactError.invalid }
      if let previous = request.replacing {
        guard previous.scope == request.scope else { throw PersonalFactError.changed }
        try validatePersonalFact(previous, owner: owner)
      } else {
        let count = try sql.integer(
          "SELECT COUNT(*) FROM personal_facts WHERE owner=?", [.text(owner)])
        guard count < PersonalFact.maximumPerScope else { throw PersonalFactError.limit }
      }
      guard
        try sql.integer(
          "SELECT COUNT(*) FROM personal_facts WHERE owner=? AND key=? AND id!=?",
          [.text(owner), .text(fact.key), .text(saved.id.uuidString)]) == 0
      else { throw PersonalFactError.duplicate }
      let data = try encoder.encode(saved)
      guard data.count <= Self.maximumPersonalFactBytes else { throw PersonalFactError.invalid }
      try sql.execute(
        "INSERT INTO personal_facts(id,owner,key,body) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET key=excluded.key,body=excluded.body",
        [.text(saved.id.uuidString), .text(owner), .text(fact.key), .data(data)])
      try advancePersonalFacts()
      return try personalFacts(request.handle)
    }
  }

  public func removePersonalFact(_ fact: PersonalFact, handle: ConversationHandle) throws
    -> PersonalFactsSnapshot
  {
    try sql.transaction {
      try validate(handle)
      let owner = owner(for: fact.scope, handle: handle)
      try validatePersonalFact(fact, owner: owner)
      try sql.execute(
        "DELETE FROM personal_facts WHERE owner=? AND id=?",
        [.text(owner), .text(fact.id.uuidString)])
      try advancePersonalFacts()
      return try personalFacts(handle)
    }
  }

  private func validatePersonalFact(_ fact: PersonalFact, owner: String) throws {
    var current: PersonalFact?
    try sql.rows(
      "SELECT body FROM personal_facts WHERE owner=? AND id=?",
      [.text(owner), .text(fact.id.uuidString)]
    ) { row in
      current = try decoder.decode(
        PersonalFact.self,
        from: VaultSQLConnection.data(row, maximumBytes: Self.maximumPersonalFactBytes))
    }
    guard current?.revision == fact.revision else { throw PersonalFactError.changed }
  }

  private func advancePersonalFacts() throws {
    try sql.execute(
      "UPDATE personal_fact_state SET revision=? WHERE id=1", [.text(UUID().uuidString)])
  }

  private func owner(for scope: PersonalFact.Scope, handle: ConversationHandle) -> String {
    scope == .shared ? "" : handle.companionID
  }
}
