import SilliesCore
import Testing

@Test func spokenRecoveryStartsAfterConfirmedPlaybackNotSubmittedAudio() {
  var progress = SpokenReplyProgress()
  let phrases = ["Heat the water.", "Adaugă frunzele.", "Leave it for three minutes."]
  for phrase in phrases { progress.append(phrase) }
  progress.completed(phrases[0])
  #expect(progress.completedText == phrases[0])
  #expect(progress.remainingPhrases == Array(phrases.dropFirst()))
  progress.completed(phrases[1])
  #expect(progress.remainingPhrases == [phrases[2]])
}

@Test func inconsistentPlaybackCannotGuessARecoveryPosition() {
  for completion in ["unplanned words", "Second phrase."] {
    var progress = SpokenReplyProgress()
    progress.append("First phrase.")
    progress.append("Second phrase.")
    progress.completed(completion)
    #expect(progress.remainingPhrases.isEmpty)
    #expect(progress.completedText.isEmpty)
  }
  var progress = SpokenReplyProgress()
  progress.append("First phrase.")
  progress.append("Second phrase.")
  progress.completed("First phrase.")
  progress.completed("First phrase.")
  #expect(progress.remainingPhrases.isEmpty)
  #expect(progress.completedText == "First phrase.")
}

@Test func speechRecoveryStorageCannotGrowPastTheReplyLimit() {
  var progress = SpokenReplyProgress()
  progress.append("A confirmed phrase.")
  progress.completed("A confirmed phrase.")
  progress.append(String(repeating: "a", count: ChatContext.maximumMessageCharacters))
  progress.append("More words")
  #expect(progress.remainingPhrases.isEmpty)
  #expect(progress.completedText == "A confirmed phrase.")
}

@Test func speechRecoveryBudgetsJoinedSeparatorsAndMultibyteCharacters() {
  var progress = SpokenReplyProgress()
  let prefix = String(repeating: "a", count: ChatContext.maximumMessageCharacters - 2)
  progress.append(prefix)
  progress.append("b")
  progress.completed(prefix)
  progress.completed("b")
  #expect(progress.completedText.count == ChatContext.maximumMessageCharacters)
  progress.append("c")
  #expect(progress.remainingPhrases.isEmpty)

  var unicode = SpokenReplyProgress()
  let large = String(repeating: "👨‍👩‍👧‍👦", count: 1_000)
  #expect(large.count < ChatContext.maximumMessageCharacters)
  #expect(large.utf8.count > ChatContext.maximumMessageBytes)
  unicode.append(large)
  #expect(unicode.remainingPhrases.isEmpty)
}
