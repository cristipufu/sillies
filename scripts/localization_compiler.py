#!/usr/bin/env python3
"""Keep compiler-extracted strings in module namespaces, including dependency builds."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


def extraction_arguments(arguments):
    arguments = list(arguments)
    path_flag = "-emit-localized-strings-path"
    if path_flag not in arguments or "-module-name" not in arguments:
        return arguments
    module = arguments[arguments.index("-module-name") + 1]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", module):
        raise ValueError("Invalid compiler module name")
    index = arguments.index(path_flag) + 1
    arguments[index] = str(Path(arguments[index]) / module)
    return arguments


def prepare_frontend(directory):
    """Pass the selected compiler explicitly; build systems sanitize custom environment variables."""
    compiler = subprocess.check_output(["xcrun", "--find", "swift-frontend"], text=True).strip()
    launcher = directory / "swift-frontend"
    command = shlex.join([sys.executable, "-B", str(Path(__file__).resolve()), compiler])
    content = '#!/bin/sh\nexec ' + command + ' "$@"\n'
    if not launcher.exists() or launcher.read_text() != content:
        launcher.write_text(content)
        launcher.chmod(0o755)
    return launcher


def compile_strings(root, directory):
    output = directory / "module-strings"
    output.mkdir(exist_ok=True)
    frontend = prepare_frontend(directory)
    # Dependency scanning must use toolchain headers, not the wrapper's directory.
    clang_resources = subprocess.check_output(["xcrun", "clang", "--print-resource-dir"], text=True).strip()
    # Extraction changes every Swift compiler invocation. Keep its build graph separate so
    # normal test/app builds do not invalidate these artifacts, or vice versa.
    # Swift Build 6.4.2 fails a cold extraction build while copying the ABI descriptor of
    # FluidAudio's resource module. Use SwiftPM's supported native backend for this check.
    command = ["swift", "build", "--build-system", "native",
               "--scratch-path", str(directory / "build"),
               "--product", "Sillies", "-Xswiftc", "-emit-localized-strings",
               "-Xswiftc", "-emit-localized-strings-path", "-Xswiftc", str(output),
               "-Xswiftc", "-driver-use-frontend-path", "-Xswiftc", str(frontend),
               "-Xswiftc", "-Xcc", "-Xswiftc", "-resource-dir",
               "-Xswiftc", "-Xcc", "-Xswiftc", clang_resources]
    log = directory / "build.log"
    started = time.monotonic()
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT)
    print(f"Localization build: {time.monotonic() - started:.1f} seconds. Log: {log}", file=sys.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"The build failed (full output: {log}):\n" + log.read_text()[-4000:])
    paths = sorted(output.glob("*/*.stringsdata"))
    if not paths or any(output.glob("*.stringsdata")):
        raise RuntimeError("The compiler did not emit module-scoped localization files.")
    return paths


def main():
    compiler = sys.argv[1]
    arguments = extraction_arguments(sys.argv[2:])
    if "-emit-localized-strings-path" in arguments:
        Path(arguments[arguments.index("-emit-localized-strings-path") + 1]).mkdir(parents=True, exist_ok=True)
    os.execv(compiler, [compiler, *arguments])


if __name__ == "__main__":
    main()
