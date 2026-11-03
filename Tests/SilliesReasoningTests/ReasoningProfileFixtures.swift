import SilliesCore

@testable import SilliesReasoning

func reasoningProfile(conversationTokens: Int, summaryTokens: Int) -> TextGenerationProfile {
  let base = AppleConversationPolicy.generation
  return .init(
    conversation: reserving(conversationTokens, in: base.conversation),
    summary: reserving(summaryTokens, in: base.summary),
    precise: base.precise)
}

private func reserving(_ tokens: Int, in task: TextGenerationProfile.Task)
  -> TextGenerationProfile.Task
{
  .init(
    outputTokens: task.outputTokens, reasoningTokens: tokens, sampling: task.sampling,
    repetitionContextTokens: task.repetitionContextTokens)
}
