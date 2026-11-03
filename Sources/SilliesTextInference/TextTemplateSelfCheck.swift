import Foundation
import MLXLMCommon
import SilliesTextModels

/// Exercises the shipped publisher template with a tiny byte tokenizer. No model weights or network.
enum TextTemplateSelfCheck {
  static func run() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      do { try FileManager.default.removeItem(at: directory) } catch {
        fputs("Template check cleanup failed: \(error)\n", stderr)
      }
    }
    try writeTokenizer(to: directory)
    let tokenizer = try await LocalTokenizerLoader(
      policy: .init(conversationCache: .disabled, chatTemplate: .mistral3)
    ).load(from: directory)
    let first = "My name is Ștefan."
    let latest = "What is my name?"
    for history: [[String: any Sendable]] in [
      [["role": "user", "content": first], ["role": "user", "content": latest]],
      [
        ["role": "user", "content": first], ["role": "assistant", "content": ""],
        ["role": "user", "content": latest],
      ],
    ] {
      let text = try render(history, with: tokenizer)
      guard text.contains("[INST]\(first)\n\n\(latest)[/INST]"),
        !text.contains("</s>")
      else { throw TextModelError.invalidResponse }
    }
    let call: [String: any Sendable] = [
      "id": "lookup", "type": "function",
      "function": ["name": "search", "arguments": ["query": "notes"]] as [String: any Sendable],
    ]
    let toolHistory: [[String: any Sendable]] = [
      ["role": "user", "content": "Find the notes"],
      ["role": "assistant", "content": "", "tool_calls": [call]],
      ["role": "tool", "content": "First result", "tool_call_id": "lookup"],
      ["role": "tool", "content": "Second result", "tool_call_id": "another"],
      ["role": "user", "content": "Continue after interruption"],
    ]
    let rendered = try render(toolHistory, with: tokenizer)
    guard rendered.contains("[TOOL_CALLS]search"),
      rendered.contains("[TOOL_RESULTS]First result[/TOOL_RESULTS]"),
      rendered.contains("[TOOL_RESULTS]Second result[/TOOL_RESULTS]"),
      rendered.contains("[INST]Continue after interruption[/INST]")
    else { throw TextModelError.invalidResponse }
    let partial = try render(
      [
        ["role": "user", "content": first], ["role": "assistant", "content": "You told me"],
        ["role": "user", "content": latest],
      ], with: tokenizer)
    guard partial.contains("You told me</s>[INST]\(latest)[/INST]") else {
      throw TextModelError.invalidResponse
    }
  }

  private static func render(_ messages: [[String: any Sendable]], with tokenizer: any Tokenizer)
    throws -> String
  {
    let tokens = try tokenizer.applyChatTemplate(
      messages: [["role": "system", "content": "You are Pogo."]] + messages)
    return tokenizer.decode(tokenIds: tokens)
  }

  private static func writeTokenizer(to directory: URL) throws {
    let directBytes = Set(Array(33...126) + Array(161...172) + Array(174...255))
    var vocabulary = ["<unk>": 256, "<s>": 257, "</s>": 258]
    var escaped = 0
    for byte in 0..<256 {
      let scalar = directBytes.contains(byte) ? byte : 256 + escaped
      if !directBytes.contains(byte) { escaped += 1 }
      guard let character = UnicodeScalar(scalar) else { throw TextModelError.invalidResponse }
      vocabulary[String(character)] = byte
    }
    let files: [String: [String: Any]] = [
      "tokenizer_config.json": [
        "tokenizer_class": "PreTrainedTokenizer", "bos_token": "<s>", "eos_token": "</s>",
        "unk_token": "<unk>",
      ],
      "tokenizer.json": [
        "version": "1.0",
        "model": ["type": "BPE", "vocab": vocabulary, "merges": [], "unk_token": "<unk>"],
        "pre_tokenizer": ["type": "ByteLevel", "add_prefix_space": false, "use_regex": true],
        "decoder": ["type": "ByteLevel"],
        "added_tokens": ["<unk>", "<s>", "</s>"].enumerated().map { index, token in
          [
            "id": 256 + index, "content": token, "special": true, "single_word": false,
            "lstrip": false, "rstrip": false, "normalized": false,
          ] as [String: Any]
        },
      ],
    ]
    for (name, object) in files {
      try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        .write(to: directory.appendingPathComponent(name), options: .atomic)
    }
  }
}
