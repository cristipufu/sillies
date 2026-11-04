enum FishProfileStage: String, Codable {
  case memoryBudgetInitialization
  case configuration, tokenizer, tokenizerValidation, speechWeights, generatorSetup, codecWeights
  case promptTokens, promptPrefill, semanticLogits, semanticSampling, semanticResampling
  case fastPrefill, fastForward, fastLogits, fastSampling, audioEmbedding, slowStep
  case slowGraph, slowEvaluation, fastEvaluation
  case codecTotal, codecCodebooks, codecAttention, codecUpsampleFirst, codecUpsampleSecond
  case codecInput, codecBlockFirst, codecBlockSecond, codecBlockThird, codecBlockFourth, codecOutput
  case codecHistoryEvaluation, codecAttentionHistoryEvaluation, codecKernelPreparation
  case pcmDelivery
}
