#!/usr/bin/env python3
"""Export a qualified local tuning receipt; never modify the running app or upload evidence."""
import argparse
from pathlib import Path

from evaluation.calibration import qualify
from evaluation.storage import write_json

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("baseline", type=Path)
parser.add_argument("candidate", type=Path)
parser.add_argument("model")
parser.add_argument("output", type=Path)
options = parser.parse_args()
write_json(options.output, qualify(options.baseline, options.candidate, options.model))
print(f"Qualified receipt: {options.output}. No application settings were changed.")
