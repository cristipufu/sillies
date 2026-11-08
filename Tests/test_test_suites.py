"""Routine runs must not quietly include benchmarks or lose functional test coverage."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from test_evidence import IncompleteTestRun
from test_suites import TestSuites

spec = importlib.util.spec_from_file_location("checked_runner", ROOT / "scripts/run-checked-tests.py")
runner_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner_module)


class TestSuiteTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.path = self.directory / "performance.json"
        self.path.write_text(json.dumps({"swift-testing": {"ExampleTests": {
            "ExampleTests.largeQuery(_:)": "Large synthetic search fixture."}}, "xctest": {}}))
        self.fast = "ExampleTests.cancellation()/PerformanceTests.swift:1:2"
        self.slow = "ExampleTests.largeQuery(_:)/Queries.swift:8:2"
        self.discovered = {self.fast, self.slow}

    def test_partition_is_complete_disjoint_and_uses_names_not_source_paths(self):
        groups = TestSuites(self.path).partition("ExampleTests", "swift-testing", self.discovered)
        self.assertEqual(groups["standard"], {self.fast})
        self.assertEqual(groups["performance"], {self.slow})
        self.assertEqual(groups["all"], groups["standard"] | groups["performance"])
        self.assertFalse(groups["standard"] & groups["performance"])

    def test_new_tests_are_standard_and_stale_rules_fail_even_in_filtered_runs(self):
        suites = TestSuites(self.path)
        groups = suites.partition("NewTests", "swift-testing", {"NewTests.example()/A.swift:1:2"})
        self.assertEqual(groups["standard"], groups["all"])
        self.assertFalse(groups["performance"])
        with self.assertRaisesRegex(IncompleteTestRun, "Stale performance tests"):
            suites.partition("ExampleTests", "swift-testing", {self.fast})
        with self.assertRaisesRegex(IncompleteTestRun, "Stale performance bundles"):
            suites.validate_bundles({"NewTests"})

    def test_xctest_uses_the_same_opt_in_boundary(self):
        self.path.write_text(json.dumps({"swift-testing": {}, "xctest": {
            "ExampleTests": {"ExampleTests.Suite/testLarge": "Large fixture."}}}))
        groups = TestSuites(self.path).partition("ExampleTests", "xctest", {
            "ExampleTests.Suite/testLarge", "ExampleTests.Suite/testFailure"})
        self.assertEqual(groups["standard"], {"ExampleTests.Suite/testFailure"})
        self.assertEqual(groups["performance"], {"ExampleTests.Suite/testLarge"})

    def test_invalid_or_duplicated_classifications_fail(self):
        for content in ['{"swift-testing": {}, "swift-testing": {}, "xctest": {}}',
                        '{"swift-testing": {"ExampleTests": {"ExampleTests.bad()": ""}}, "xctest": {}}',
                        '{"swift-testing": {"ExampleTests": {"OtherTests.bad()": "reason"}}, "xctest": {}}',
                        '{"swift-testing": [], "xctest": {}}']:
            with self.subTest(content=content):
                self.path.write_text(content)
                with self.assertRaises(IncompleteTestRun):
                    TestSuites(self.path)

    def test_filter_cannot_opt_in_performance_and_receipt_explains_deferral(self):
        runner = runner_module.NativeTestRunner.__new__(runner_module.NativeTestRunner)
        runner.suites = TestSuites(self.path)
        runner.options = SimpleNamespace(suite="standard", filter=["largeQuery"], skip=[])
        prefix = self.directory / "selection"
        self.assertEqual(runner.select(Path("ExampleTests.xctest"), "swift-testing",
                                       self.discovered, prefix), set())
        evidence = json.loads(prefix.with_suffix(".suite.json").read_text())
        self.assertEqual(evidence["deferred"], [self.slow])
        runner.options.suite = "performance"
        self.assertEqual(runner.select(Path("ExampleTests.xctest"), "swift-testing",
                                       self.discovered, prefix), {self.slow})
        runner.options.skip = ["largeQuery"]
        self.assertEqual(runner.select(Path("ExampleTests.xctest"), "swift-testing",
                                       self.discovered, prefix), set())


class TestBuildSelectionTests(unittest.TestCase):
    def run_script(self, arguments):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        log = directory / "commands.jsonl"
        for name in ["swift", "python3"]:
            executable = directory / name
            executable.write_text(f"#!{sys.executable}\n" + "\n".join([
                "import json, os, sys",
                "from pathlib import Path",
                "with open(os.environ['TEST_COMMAND_LOG'], 'a') as output:",
                "    output.write(json.dumps([Path(sys.argv[0]).name, *sys.argv[1:]]) + '\\n')",
                "if '--show-bin-path' in sys.argv: print('/tmp/sillies-test-products')",
            ]) + "\n")
            executable.chmod(0o755)
        environment = dict(os.environ, PATH=str(directory) + ":" + os.environ["PATH"],
                           DEVELOPER_DIR="test-toolchain", TEST_COMMAND_LOG=str(log))
        result = subprocess.run(["/bin/bash", "scripts/test.sh", *arguments], cwd=ROOT,
                                env=environment, capture_output=True, text=True, timeout=10)
        commands = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result, commands

    def test_default_builds_all_once_and_runner_owns_batching(self):
        result, commands = self.run_script([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["swift", "build", "--configuration", "debug", "--build-tests"], commands)
        self.assertEqual(sum(command[0] == "python3" for command in commands), 1)

    def test_targeted_builds_only_requested_bundle_and_native_helper(self):
        result, commands = self.run_script(["--bundle", "SilliesAppTests", "--filter", "modelCatalog"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["swift", "build", "--configuration", "debug", "--target", "SilliesAppTests"], commands)
        self.assertIn(["swift", "build", "--configuration", "debug", "--product", "SilliesWindowMetadata"], commands)
        self.assertFalse(any("--build-tests" in command for command in commands))
        self.assertEqual(commands[-1][-4:], ["--bundle", "SilliesAppTests", "--filter", "modelCatalog"])

    def test_release_selection_applies_to_every_build_and_binary_lookup(self):
        result, commands = self.run_script(["--configuration", "release", "--suite", "performance",
                                           "--bundle=SilliesAppTests"])
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [command for command in commands if command[0] == "swift"]
        self.assertEqual(len(builds), 3)
        for command in builds:
            self.assertEqual(command[2:4], ["--configuration", "release"])
            self.assertEqual(command[4:8], ["--scratch-path", ".build/performance", "-Xswiftc", "-enable-testing"])
        self.assertIn("--show-bin-path", builds[-1])

    def test_invalid_target_fails_before_any_build(self):
        for arguments in [["--bundle"], ["--bundle", "MissingTests"], ["--bundle=../SilliesAppTests"]]:
            with self.subTest(arguments=arguments):
                result, commands = self.run_script(arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(commands, [])

    def test_invalid_configuration_fails_before_any_build(self):
        for arguments in [["--configuration"], ["--configuration=fast"]]:
            with self.subTest(arguments=arguments):
                result, commands = self.run_script(arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(commands, [])


if __name__ == "__main__":
    unittest.main()
