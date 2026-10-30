import Foundation

func run() throws -> Bool {
  guard ArchitectureFixtures.verify() else { return false }
  let manifest = URL(fileURLWithPath: "Tools/ArchitectureCheck/UncheckedOwners.json")
  let owners = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifest))
  let policy = ArchitecturePolicy(uncheckedOwners: owners)
  guard let files = FileManager.default.enumerator(atPath: "Sources") else {
    fputs("Cannot enumerate Sources.\n", stderr)
    return false
  }
  var diagnostics: [ArchitectureDiagnostic] = []
  for case let relative as String in files where relative.hasSuffix(".swift") {
    let path = "Sources/" + relative
    let source = try String(contentsOfFile: path, encoding: .utf8)
    diagnostics += ArchitectureVisitor.check(source: source, path: path, policy: policy)
  }
  for diagnostic in diagnostics.sorted(by: { $0.description < $1.description }) {
    fputs("\(diagnostic)\n", stderr)
  }
  return diagnostics.isEmpty
}

do { exit(try run() ? 0 : 1) } catch {
  fputs("Architecture check failed: \(error.localizedDescription)\n", stderr)
  exit(1)
}
