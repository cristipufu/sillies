import SilliesCore
import Testing

@Test func personalDictionaryPreservesRomanianBoundariesAndDoesNotCascade() {
  let dictionary = PersonalDictionary(entries: [
    .init(phrase: "Ștefănescu", heardAs: "Stefan escu"),
    .init(phrase: "Sillies", heardAs: "silly"),
    .init(phrase: "wrong", heardAs: "Sillies"),
    .init(phrase: "API_v2", heardAs: "api version two"),
  ])
  #expect(
    dictionary.replacing(in: "Salut Stefan escu, ship api version two with silly tomorrow.")
      == "Salut Ștefănescu, ship API_v2 with Sillies tomorrow.")
  #expect(
    dictionary.replacing(in: "sillyness and silly_code stay") == "sillyness and silly_code stay")
  #expect(dictionary.replacing(in: "STEFAN ESCU, mulțumesc!") == "Ștefănescu, mulțumesc!")
}

@Test func cleanupRejectsChangedNumbersNamesAndIdentifiers() {
  let source = "Um, Ștefănescu ships API_v2 at 16:30 on 12/11."
  #expect(
    TextCleanupGuard.accepts(
      "Ștefănescu ships API_v2 at 16:30 on 12/11.", source: source, vocabulary: ["Ștefănescu"]))
  #expect(
    !TextCleanupGuard.accepts(
      "Ștefănescu ships API_v2 at 17:30 on 12/11.", source: source, vocabulary: []))
  #expect(
    !TextCleanupGuard.accepts(
      "Alex ships API_v2 at 16:30 on 12/11.", source: source, vocabulary: ["Ștefănescu"]))
}

@Test func shorteningCanDropOrdinarySentenceOpenersButPreservesNamedEntities() {
  let source = "Please ask Ștefan to review API_v2 at 16:30."
  #expect(
    TextCleanupGuard.accepts(
      "Ștefan: review API_v2 at 16:30.", source: source,
      vocabulary: ["Ștefan"], operation: .rewriting))
  #expect(
    !TextCleanupGuard.accepts(
      "Review API_v2 at 16:30.", source: source,
      vocabulary: ["Ștefan"], operation: .rewriting))
}
