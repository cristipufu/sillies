import Foundation

func run() throws -> Bool {
  guard ArchitectureFixtures.verify() else { return false }
  guard LocalizationFixtures.verify() else { return false }
  guard ThemeFixtures.verify() else { return false }
  let package = try String(contentsOfFile: "Package.swift", encoding: .utf8)
  let dependencyFailures = PackageBoundaryCheck.check(package)
  for failure in dependencyFailures {
    fputs("Package.swift: [package-boundary] \(failure)\n", stderr)
  }
  let manifest = URL(fileURLWithPath: "Tools/ArchitectureCheck/UncheckedOwners.json")
  let owners = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifest))
  let policy = ArchitecturePolicy(uncheckedOwners: owners)
  var diagnostics: [ArchitectureDiagnostic] = []
  for root in ["Sources", "Tools/ChatModelBenchmark"] {
    guard let files = FileManager.default.enumerator(atPath: root) else {
      fputs("Cannot enumerate \(root).\n", stderr)
      return false
    }
    for case let relative as String in files where relative.hasSuffix(".swift") {
      let path = root + "/" + relative
      let source = try String(contentsOfFile: path, encoding: .utf8)
      diagnostics += ArchitectureVisitor.check(source: source, path: path, policy: policy)
      diagnostics += LocalizationVisitor.check(source: source, path: path)
      diagnostics += ThemeVisitor.check(source: source, path: path)
    }
  }
  for diagnostic in diagnostics.sorted(by: { $0.description < $1.description }) {
    fputs("\(diagnostic)\n", stderr)
  }
  return diagnostics.isEmpty && dependencyFailures.isEmpty
}

do { exit(try run() ? 0 : 1) } catch {
  fputs("Architecture check failed: \(error.localizedDescription)\n", stderr)
  exit(1)
}
