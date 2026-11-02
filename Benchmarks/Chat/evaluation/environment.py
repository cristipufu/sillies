"""Record execution conditions without collecting machine or user identifiers."""
from __future__ import annotations

import platform
import subprocess
from pathlib import Path

from .storage import file_hash


def command_value(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True, timeout=5).strip()


def capture() -> dict:
    return {
        "osVersion": platform.mac_ver()[0],
        "osBuild": command_value("/usr/bin/sw_vers", "-buildVersion"),
        "architecture": platform.machine(),
        "processor": command_value("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"),
        "memoryBytes": int(command_value("/usr/sbin/sysctl", "-n", "hw.memsize")),
        "logicalProcessors": int(command_value("/usr/sbin/sysctl", "-n", "hw.logicalcpu")),
    }


def runtime_resources(worker: Path, helper: Path) -> dict:
    helper_bundle = next((parent for parent in helper.parents if parent.suffix == ".app"), None)
    if helper_bundle is None:
        raise ValueError("Use the bundled inference helper so its kernels and resources can be frozen")
    catalog_bundle = worker.parent / "Sillies_SilliesModelStore.bundle"
    if not catalog_bundle.is_dir():
        raise ValueError("The benchmark worker is missing its bundled model catalog")
    roots = {"helperBundle": helper_bundle, "workerCatalogBundle": catalog_bundle}
    return {name: {str(path.relative_to(root)): file_hash(path)
                   for path in sorted(root.rglob("*")) if path.is_file()}
            for name, root in roots.items()}
