/// The same predicate owns immediate visibility and eventual physical reclamation.
enum VaultCleanupSelection: String, CaseIterable {
  case all, retention, trash

  static let visibleSequenceBoundary =
    "coalesce((SELECT through_sequence FROM vault_cleanup WHERE kind='all'),0)"

  static var recordVisibility: String {
    """
    r.sequence>\(visibleSequenceBoundary)
      AND NOT EXISTS(SELECT 1 FROM pending_deletions WHERE record_id=r.id)
      AND \(retention.exclusion) AND \(trash.exclusion)
    """
  }

  var predicate: String {
    let sequence = "r.sequence<=j.through_sequence"
    switch self {
    case .all: return sequence
    case .retention:
      return """
        \(sequence) AND r.kind!='stash' AND r.protected=0
        AND (r.created<j.before_date OR (r.created=j.before_date AND r.id<=j.before_id))
        AND NOT EXISTS(SELECT 1 FROM workspace WHERE record_id=r.id AND starred=1)
        """
    case .trash:
      return
        "\(sequence) AND EXISTS(SELECT 1 FROM workspace WHERE record_id=r.id AND trashed<=j.before_date)"
    }
  }

  var exclusion: String {
    "NOT EXISTS(SELECT 1 FROM vault_cleanup j WHERE j.kind='\(rawValue)' AND \(predicate))"
  }
}
