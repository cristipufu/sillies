"""Run a limited number of resumable native retrieval slices with immutable input receipts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def run(args):
    receipt = args.directory.with_name(args.directory.name + "-run.json")
    signature = {
        "binarySHA256": digest(args.binary), "helperSHA256": digest(args.helper),
        "inputSHA256": digest(args.inputs), "provider": args.provider, "identity": args.identity,
        "model": str(args.model.resolve()) if args.model else None,
    }
    if receipt.exists() and json.loads(receipt.read_text()) != signature:
        raise ValueError("Run inputs or native executables changed; use a new disposable directory")
    receipt.parent.mkdir(parents=True, exist_ok=True)
    receipt.write_text(json.dumps(signature, indent=2) + "\n")
    for iteration in range(args.slices):
        command = [str(args.binary.resolve()), "--vault-workspace", args.stage,
                   str(args.inputs.resolve()), str(args.directory.resolve()), str(args.helper.resolve()),
                   args.provider, args.identity]
        if args.model:
            command.append(str(args.model.resolve()))
        started = time.monotonic()
        completed = subprocess.run(command, capture_output=True, text=True, timeout=90)
        with args.directory.with_name(args.directory.name + "-stderr.log").open("a") as log:
            log.write(completed.stderr)
        if completed.returncode:
            raise RuntimeError(f"Native slice failed ({completed.returncode}): {completed.stderr[-2000:]}")
        result = json.loads(completed.stdout.strip().splitlines()[-1])
        print(json.dumps({**result, "seconds": time.monotonic() - started}), flush=True)
        if result["complete"]:
            return


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for name in ("binary", "inputs", "directory", "helper"):
        parser.add_argument(name, type=Path)
    parser.add_argument("provider", choices=["keywords", "apple", "e5"])
    parser.add_argument("identity")
    parser.add_argument("--model", type=Path)
    parser.add_argument("--stage", required=True, choices=["seed", "index", "query"])
    parser.add_argument("--slices", type=int, choices=range(1, 11), default=1)
    run(parser.parse_args())
