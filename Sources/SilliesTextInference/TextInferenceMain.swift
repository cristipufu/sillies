import Darwin
import Foundation
import MLX
import SilliesTextModels

@main enum TextInferenceMain {
  private static let idleTimeout: TimeInterval = 90
  static func main() async {
    if let library = Bundle.main.url(forResource: "mlx", withExtension: "metallib") {
      GPU.metallib = library
    }
    if CommandLine.arguments.contains("--self-test") {
      let result = (MLXArray([1, 2, 3]) * 2).sum().item(Int.self)
      guard result == 12 else { exit(EXIT_FAILURE) }
      print("Text inference GPU and bundled kernels: passed")
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
          deadline: ProcessInfo.processInfo.systemUptime + idleTimeout)
      } catch { return }
      let response: TextInferenceResponse
      do { response = TextInferenceResponse(text: try await runtime.generate(request)) } catch {
        fputs("Local text inference failed: \(error.localizedDescription)\n", stderr)
        response = TextInferenceResponse(failure: error.localizedDescription)
      }
      do {
        try TextInferenceWire.write(
          response, to: .standardOutput,
          deadline: ProcessInfo.processInfo.systemUptime + idleTimeout)
      } catch { return }
    }
  }
}
