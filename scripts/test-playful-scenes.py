#!/usr/bin/env python3
"""Play every bundled scene sequentially in real native windows, with bounded execution."""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenes", nargs="*", help="Optional scene IDs, in playback order")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    app = root / "build/Sillies.app/Contents"
    binary = app / "MacOS/Sillies"
    catalog = app / "Resources/Scenes/playful-scenes.json"
    if not binary.is_file() or not catalog.is_file():
        raise SystemExit("Build Sillies first with make debug or make build.")
    scenes = json.loads(catalog.read_text())
    if arguments.scenes:
        catalog_by_id = {scene["id"]: scene for scene in scenes}
        missing = set(arguments.scenes) - catalog_by_id.keys()
        if missing:
            parser.error(f"Unknown scenes: {', '.join(sorted(missing))}")
        scenes = [catalog_by_id[identifier] for identifier in arguments.scenes]
    for index, scene in enumerate(scenes, start=1):
        print(f"GUI SCENE {index}/{len(scenes)}: {scene['title']}", flush=True)
        subprocess.run(
            [str(binary), "--playful-scene", scene["id"], "--without-accessibility"],
            check=True,
            timeout=45,
        )
    print(f"PLAYFUL GUI CHECK OK: all {len(scenes)} scenes completed.", flush=True)


if __name__ == "__main__":
    main()
