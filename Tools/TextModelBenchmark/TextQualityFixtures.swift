/// Acceptance cases are shared by every model. Their expected facts never enter production prompts.
/// These checks catch known errors; review printed output for omissions and unsupported claims too.
enum TextQualityFixtures {
  struct Fixture {
    let language: String
    let source: String
    let requiredFacts: [[String]]
  }
  static let cases = [
    Fixture(
      language: "Romanian",
      source:
        "Ștefan trimite raportul vineri la 14:30. Bugetul aprobat este 2.500 EUR. Nu s-a decis data lansării.",
      requiredFacts: [
        ["Ștefan"], ["vineri"], ["14:30"], ["2.500", "2,500"], ["nu", "neprecizat", "nestabilit"],
      ]),
    Fixture(
      language: "English",
      source:
        "Ana will send the report on Friday at 14:30. The approved budget is EUR 2,500. No launch date was agreed.",
      requiredFacts: [
        ["Ana"], ["Friday"], ["14:30"], ["2,500", "2.500"], ["no", "not", "undecided"],
      ]),
    Fixture(
      language: "Romanian",
      source:
        "Ștefan said: I will send the pull request Friday at 14:30. Bugetul aprobat este 2.500 EUR. Nu avem încă o dată pentru release.",
      requiredFacts: [
        ["Ștefan"], ["vineri"], ["14:30"], ["2.500", "2,500"],
        ["nu", "fără", "neprecizat", "nestabilit"],
      ]),
  ]
}
