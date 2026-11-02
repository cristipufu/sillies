import Darwin
import Foundation
import MLX
import SilliesInference
import SilliesTextModels

@main enum TextInferenceMain {
  private static let responseTimeout: TimeInterval = 90
  static func main() async {
    let parentMonitor = InferenceParentMonitor.start()
    defer { parentMonitor.cancel() }
    if let library = Bundle.main.url(forResource: "mlx", withExtension: "metallib") {
      GPU.metallib = library
    }
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--inspect-tokenizer" {
      do {
        try await TextTokenizerInspection.run(
          requestURL: URL(fileURLWithPath: CommandLine.arguments[2]))
      } catch {
        fputs("Tokenizer inspection failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
      }
      return
    }
    if CommandLine.arguments.contains("--self-test") {
      let result = (MLXArray([1, 2, 3]) * 2).sum().item(Int.self)
      guard result == 12 else { exit(EXIT_FAILURE) }
      do {
        try TextConversationSelfCheck.run()
        try TextReasoningSelfCheck.run()
        try await TextGenerationFailureSelfCheck.run()
        try await TextInputSelfCheck.run()
      } catch {
        fputs("Native conversation check failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
      }
      print("Text inference GPU, native conversation protocol and bundled kernels: passed")
      return
    }
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--check-tokenizer" {
      do {
        let tokenizer = try await LocalTokenizerLoader().load(
          from: URL(fileURLWithPath: CommandLine.arguments[2]))
        let source = "Mâine, Ștefan trimite raportul la 14:30. English mixed with română."
        let tokens = try tokenizer.applyChatTemplate(
          messages: [
            ["role": "system", "content": "Summarize accurately."],
            ["role": "user", "content": source],
          ], tools: nil, additionalContext: ["enable_thinking": false])
        guard !tokens.isEmpty, tokenizer.decode(tokenIds: tokens).contains(source) else {
          exit(EXIT_FAILURE)
        }
        print("Local multilingual tokenizer and chat template: passed")
      } catch {
        fputs("Tokenizer check failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
      }
      return
    }
    _ = fcntl(STDOUT_FILENO, F_SETNOSIGPIPE, 1)
    _ = fcntl(STDOUT_FILENO, F_SETFL, O_NONBLOCK)
    let runtime = MLXTextRuntime()
    while true {
      let request: TextInferenceRequest
      do {
        request = try TextInferenceWire.read(
          TextInferenceRequest.self, from: .standardInput,
          // The registry owns idle retention. Parent death and explicit stop terminate the helper.
          deadline: .infinity)
      } catch { return }
      let response: TextInferenceResponse
      do {
        let result = try await runtime.generate(request) { delta in
          try TextInferenceWire.write(
            TextInferenceEvent.delta(delta), to: .standardOutput,
            deadline: ProcessInfo.processInfo.systemUptime + responseTimeout)
          _ = try TextInferenceWire.read(
            TextInferenceAcknowledgement.self, from: .standardInput,
            deadline: ProcessInfo.processInfo.systemUptime + responseTimeout)
        }
        response = TextInferenceResponse(output: result)
      } catch TextModelError.contextLimit {
        response = TextInferenceResponse(
          failure: TextModelError.contextLimit.localizedDescription, code: .contextLimit)
      } catch let failure as TextGenerationFailure {
        response = TextInferenceResponse(
          failure: failure.localizedDescription, generationFailure: failure)
      } catch {
        fputs("Local text inference failed: \(error.localizedDescription)\n", stderr)
        response = TextInferenceResponse(failure: error.localizedDescription)
      }
      do {
        try TextInferenceWire.write(
          TextInferenceEvent.finished(response), to: .standardOutput,
          deadline: ProcessInfo.processInfo.systemUptime + responseTimeout)
      } catch { return }
    }
  }
}
