"""Record execution conditions without collecting machine or user identifiers."""
from __future__ import annotations

import platform
import subprocess


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
