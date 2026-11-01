#!/usr/bin/env python3
"""Exercise native Settings, Vault and Chat in every packaged interface language."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Built Sillies.app bundle")
    parser.add_argument("--snapshots", type=Path, help="Save fixture-window previews for visual review")
    options = parser.parse_args()
    app = options.app.resolve()
    executable = app / "Contents/MacOS/Sillies"
    languages = json.loads((app / "Contents/Resources/Languages.json").read_text())
    environment = os.environ.copy()
    if options.snapshots:
        environment["SILLIES_WINDOW_SNAPSHOTS"] = str(options.snapshots.resolve())
    for language in languages:
        code = language["code"]
        print(f"Checking native windows: {code}", flush=True)
        result = subprocess.run(
            [str(executable), "-AppleLanguages", f"({code})", "--app-window-test", "--without-accessibility"],
            env=environment, capture_output=True, text=True, timeout=45)
        print(result.stdout, end="", flush=True)
        if result.returncode != 0 or "APP WINDOW CHECK PASSED:" not in result.stdout:
            sys.exit(result.stderr or f"Native window check failed: {code}")
        if options.snapshots and f"NATIVE LOCALIZATION SNAPSHOT: {code} ·" not in result.stdout:
            sys.exit(f"The bundle did not select the requested interface language: {code}")
    print(f"Native window checks passed for {len(languages)} languages.")


if __name__ == "__main__":
    main()
