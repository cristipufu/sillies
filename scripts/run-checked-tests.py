#!/usr/bin/env python3
"""Run built macOS test bundles with independent discovery and mandatory completion receipts."""
import argparse
import json
import os
import plistlib
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from checked_test_process import TestProcess
from test_presentation import TestPresentation
from test_suites import TestSuites, test_batches
from test_evidence import (IncompleteTestRun, selected_tests, swift_inventory, swift_test_name,
                           verify_swift_run, verify_xctest_run, xctest_inventory)


class NativeTestRunner:
    def __init__(self, options, results):
        self.options = options
        self.results = results
        self.suites = TestSuites()
        self.timings = []
        developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
        developer = Path(os.environ.get("DEVELOPER_DIR", developer))
        platform = developer / "Platforms/MacOSX.platform/Developer"
        toolchain = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip()).parents[1]
        self.helpers = toolchain / "libexec/swift/pm"
        self.xctest = subprocess.check_output(["xcrun", "--find", "xctest"], text=True).strip()
        environment = dict(os.environ)
        environment["SILLIES_TEST_PRESENTATION"] = options.presentation
        # Read the current build products, not stale resource copies embedded by an incremental
        # SwiftPM test-bundle build. This is SwiftPM's supported debug resource lookup override.
        environment["PACKAGE_RESOURCE_BUNDLE_PATH"] = str(options.bin_path)
        for key, location in [("DYLD_FRAMEWORK_PATH", platform / "Library/Frameworks"),
                              ("DYLD_LIBRARY_PATH", platform / "usr/lib")]:
            environment[key] = str(location) + (":" + environment[key] if environment.get(key) else "")
        if options.sanitizer == "thread":
            runtime_directory = subprocess.check_output(["xcrun", "clang", "--print-runtime-dir"], text=True).strip()
            runtime = Path(runtime_directory) / "libclang_rt.tsan_osx_dynamic.dylib"
            if not runtime.is_file():
                raise IncompleteTestRun("Thread Sanitizer runtime is unavailable")
            environment["DYLD_INSERT_LIBRARIES"] = str(runtime)
        started = time.monotonic()
        self.native_host = self.build_native_host(options.bin_path, platform, options.sanitizer)
        self.timings.append(dict(phase="native-host-build", seconds=time.monotonic() - started))
        self.environment = environment
        self.process = self.new_process_batch()
        self.receipts = []

    def new_process_batch(self):
        return TestProcess(self.options.timeout, self.environment, self.timings)

    @staticmethod
    def build_native_host(directory, platform, sanitizer):
        contents = directory / "SilliesNativeTestHost.app/Contents"
        executable = contents / "MacOS/SilliesNativeTestHost"
        executable.parent.mkdir(parents=True, exist_ok=True)
        info = dict(CFBundleIdentifier="app.sillies.native-tests", CFBundleName="Sillies Tests",
                    CFBundleExecutable=executable.name, CFBundlePackageType="APPL",
                    LSUIElement=True, NSHighResolutionCapable=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        instrumentation = ["-sanitize=" + sanitizer] if sanitizer else []
        subprocess.run(["swiftc", *instrumentation, "-swift-version", "6", "-parse-as-library",
                        "-F", str(platform / "Library/Frameworks"),
                        "-Xlinker", "-rpath", "-Xlinker", str(platform / "Library/Frameworks"),
                        "scripts/native-test-host.swift", "scripts/native-test-presentation.swift",
                        "-o", str(executable)], check=True)
        return executable

    def run(self):
        bundles = self.selected_bundles()
        if self.options.presentation == "headless":
            self.verify_presentation_boundary()
        targeted = self.options.filter or self.options.skip or self.options.bundle
        batches = [bundles] if targeted else test_batches(bundles)
        for batch in batches:
            self.process = self.new_process_batch()
            for bundle in batch:
                if self.options.framework in {"all", "swift-testing"}:
                    self.run_swift(bundle)
                if self.options.framework in {"all", "xctest"}:
                    self.run_xctest(bundle)
        if not self.receipts:
            raise IncompleteTestRun("No tests matched the selection; benchmarks require --suite performance")
        (self.results / "verified.json").write_text(json.dumps(self.receipts, indent=2) + "\n")
        count = sum(receipt["tests"] for receipt in self.receipts)
        print(f"Verified completion of {count} selected tests across {len(self.receipts)} runs.")

    def selected_bundles(self):
        bundles = sorted(self.options.bin_path.glob("*.xctest"))
        if not bundles:
            raise IncompleteTestRun("No built test bundles found")
        available = {bundle.stem for bundle in bundles}
        if missing := set(self.options.bundle) - available:
            raise IncompleteTestRun(f"Requested test bundles are not built: {sorted(missing)}")
        if not self.options.bundle:
            self.suites.validate_bundles(available)
        return [bundle for bundle in bundles
                if (not self.options.bundle or bundle.stem in self.options.bundle)
                and (self.options.presentation != "gui" or bundle.stem == "SilliesAppTests")
                # Do not load deliberately excluded GPU libraries in TSAN processes.
                and not any(re.fullmatch(pattern, bundle.stem) for pattern in self.options.skip)]

    def verify_presentation_boundary(self):
        for operation in ["front", "back", "key", "regardless", "relative", "activate",
                          "activateCurrent", "makeKey", "makeMain", "offscreen"]:
            expected = 0 if operation == "offscreen" else 86
            log = self.results / f"presentation-{operation}.log"
            self.process.run([str(self.native_host), "--presentation-probe", operation], log,
                             expected_exit_codes=(expected,))
            if expected and "Headless test rejected visible UI" not in log.read_text():
                raise IncompleteTestRun(f"Presentation boundary did not reject {operation}")

    def select(self, bundle, framework, tests, prefix):
        groups = self.suites.partition(bundle.stem, framework, tests)
        name = swift_test_name if framework == "swift-testing" else lambda value: value
        matching = selected_tests(tests, self.options.filter, self.options.skip, name)
        selected = matching & groups[self.options.suite]
        deferred = matching - selected
        prefix.with_suffix(".suite.json").write_text(json.dumps(
            dict(suite=self.options.suite, selected=sorted(selected), deferred=sorted(deferred)),
            indent=2) + "\n")
        if matching:
            print(f"{bundle.stem} {framework}: {len(selected)} {self.options.suite} tests; "
                  f"{len(deferred)} deferred by suite selection.", flush=True)
        return selected

    def run_swift(self, bundle):
        prefix = self.results / (bundle.stem + "-swift")
        inventory = prefix.with_suffix(".inventory.jsonl")
        events = prefix.with_suffix(".events.jsonl")
        command = [str(self.helpers / "swiftpm-testing-helper"), "--test-bundle-path",
                   str(bundle / "Contents/MacOS" / bundle.stem), "--testing-library", "swift-testing",
                   "--event-stream-version", "0"]
        # Swift Testing uses EXIT_NO_TESTS_FOUND (69) for an empty discovery inventory.
        # Only discovery accepts it; selected execution must produce success and every receipt.
        code = self.process.run(command + ["--list-tests", "--event-stream-output-path", str(inventory)],
                                prefix.with_suffix(".discovery.log"), expected_exit_codes=(0, 69))
        discovered = swift_inventory(inventory)
        if code == 69 and discovered:
            raise IncompleteTestRun("Empty-discovery exit code contradicts its inventory")
        expected = self.select(bundle, "swift-testing", discovered, prefix)
        if bundle.stem == "SilliesAppTests":
            groups = TestPresentation().partition(discovered)
            deferred = expected - groups[self.options.presentation]
            expected &= groups[self.options.presentation]
            prefix.with_suffix(".presentation.json").write_text(json.dumps(
                dict(mode=self.options.presentation, selected=sorted(expected),
                     deferred=sorted(deferred)), indent=2) + "\n")
            print(f"Native presentation: {len(expected)} {self.options.presentation} tests; "
                  f"{len(deferred)} tests reserved for the other presentation mode.", flush=True)
        if not expected:
            return
        # Runtime regexes also match source-file paths. Execute the discovered IDs exactly,
        # so e.g. "Playback" cannot accidentally include a timing test in PlaybackTests.swift.
        selection = ["--filter", "^(?:" + "|".join(re.escape(test) for test in sorted(expected)) + ")$"]
        log = prefix.with_suffix(".log")
        if bundle.stem == "SilliesAppTests":
            command[0] = str(self.native_host)
        self.execute(command + ["--no-parallel", "--event-stream-output-path", str(events)] + selection, log)
        count = verify_swift_run(events, expected)
        self.receipts.append(dict(bundle=bundle.stem, framework="swift-testing", tests=count,
                                  presentation=self.options.presentation, suite=self.options.suite,
                                  configuration=self.options.configuration))

    def run_xctest(self, bundle):
        prefix = self.results / (bundle.stem + "-xctest")
        inventory = prefix.with_suffix(".inventory.json")
        self.process.run([str(self.helpers / "swiftpm-xctest-helper"), str(bundle), str(inventory)],
                         prefix.with_suffix(".discovery.log"))
        expected = self.select(bundle, "xctest", xctest_inventory(json.loads(inventory.read_text())), prefix)
        if bundle.stem == "SilliesAppTests" and expected:
            raise IncompleteTestRun("Native AppKit tests must use Swift Testing presentation classification")
        if self.options.presentation == "gui":
            return
        if not expected:
            return
        log = prefix.with_suffix(".log")
        self.execute([self.xctest, "-XCTest", ",".join(sorted(expected)), str(bundle)], log)
        count = verify_xctest_run(log.read_text(), expected)
        self.receipts.append(dict(bundle=bundle.stem, framework="xctest", tests=count,
                                 suite=self.options.suite, configuration=self.options.configuration))

    def execute(self, command, log):
        try:
            self.process.run(command, log)
        finally:
            if log.exists():
                print(log.read_text(), end="", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-path", type=Path, required=True)
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug",
                        help="test build configuration selected by scripts/test.sh")
    parser.add_argument("--sanitizer", choices=["thread"])
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--filter", action="append", default=[])
    parser.add_argument("--skip", action="append", default=[])
    parser.add_argument("--framework", choices=["all", "swift-testing", "xctest"], default="all")
    parser.add_argument("--suite", choices=["standard", "performance", "all"], default="standard",
                        help="performance and scale measurements are opt-in")
    parser.add_argument("--bundle", action="append", default=[],
                        help="discover only this built test target; may be repeated")
    parser.add_argument("--presentation", choices=["headless", "gui"], default="headless",
                        help="headless by default; gui explicitly permits visible native tests")
    options = parser.parse_args()
    options.bin_path = options.bin_path.resolve()
    root = Path("build/test-results")
    root.mkdir(parents=True, exist_ok=True)
    results = Path(tempfile.mkdtemp(prefix="run-", dir=root)).resolve()
    print(f"Test receipts: {results}", flush=True)
    runner = None
    try:
        runner = NativeTestRunner(options, results)
        runner.run()
    except (IncompleteTestRun, OSError, ValueError, subprocess.CalledProcessError, TimeoutError) as error:
        print(f"Test verification failed: {error}. Receipts: {results}", file=sys.stderr)
        return 1
    finally:
        if runner is not None:
            (results / "timings.json").write_text(json.dumps(runner.timings, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
