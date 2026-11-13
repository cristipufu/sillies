import Foundation
import NaturalLanguage

/// A semantic match needs a shared content term before it may reuse an existing identity.
struct MeetingTopicIdentity: Sendable {
  private let terms: Set<String>
  init(_ title: String) {
    let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
    tagger.string = title
    var terms: Set<String> = []
    tagger.enumerateTags(
      in: title.startIndex..<title.endIndex, unit: .word, scheme: .lexicalClass,
      options: [.omitWhitespace, .omitPunctuation]
    ) { tag, range in
      guard
        tag == .noun || tag == .verb || tag == .adjective || tag == .adverb
          || tag == .interjection || tag == .otherWord
      else {
        return true
      }
      let (lemmaTag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
      let lemma = lemmaTag?.rawValue
      for word in [String(title[range]), lemma].compactMap({ $0 }) {
        terms.insert(word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
      }
      return true
    }
    self.terms = terms
  }
  func sharesAnchor(with other: Self) -> Bool { !terms.isDisjoint(with: other.terms) }
}
