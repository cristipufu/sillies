#!/usr/bin/env python3
"""Render the shipped notices from resolved local sources; never fetch dependencies or weights."""

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import sys
import tempfile


@dataclass(frozen=True)
class PackageNotices:
    directory: str
    purpose: str
    files: tuple[str, ...]


PACKAGES = {
    "argmax-oss-swift": PackageNotices("argmax-oss-swift", "WhisperKit speech recognition", ("LICENSE", "NOTICES")),
    "eventsource": PackageNotices("EventSource", "Transitive Hugging Face dependency; no cloud inference is enabled", ("LICENSE.md",)),
    "fluidaudio": PackageNotices("FluidAudio", "Parakeet recognition and speaker detection", ("LICENSE", "ThirdPartyLicenses/fastcluster-LICENSE.md", "ThirdPartyLicenses/vbx-LICENSE.md")),
    "mlx-swift": PackageNotices("mlx-swift", "Native text inference and Metal kernels", (
        "LICENSE", "ACKNOWLEDGMENTS.md", "Source/Cmlx/mlx/LICENSE", "Source/Cmlx/mlx/ACKNOWLEDGMENTS.md",
        "Source/Cmlx/mlx-c/LICENSE", "Source/Cmlx/mlx-c/ACKNOWLEDGMENTS.md", "Source/Cmlx/metal-cpp/LICENSE.txt",
        "Source/Cmlx/fmt/LICENSE", "Source/Cmlx/json/LICENSE.MIT")),
    "mlx-swift-lm": PackageNotices("mlx-swift-lm", "Text model loading and generation", ("LICENSE", "ACKNOWLEDGMENTS.md")),
    "sparkle": PackageNotices("Sparkle", "App updates; includes Sparkle's embedded third-party notices", ("LICENSE",)),
    "swift-argument-parser": PackageNotices("swift-argument-parser", "Command-line and dependency tooling", ("LICENSE.txt",)),
    "swift-asn1": PackageNotices("swift-asn1", "Transitive cryptography support", ("LICENSE.txt", "NOTICE.txt")),
    "swift-collections": PackageNotices("swift-collections", "Collection types used by dependencies", ("LICENSE.txt",)),
    "swift-crypto": PackageNotices("swift-crypto", "Transitive cryptography support; uses CryptoKit on this macOS build", ("LICENSE.txt", "NOTICE.txt")),
    "swift-huggingface": PackageNotices("swift-huggingface", "Transitive model/tokenizer support", ("LICENSE",)),
    "swift-jinja": PackageNotices("swift-jinja", "Local model chat templates", ("LICENSE",)),
    "swift-numerics": PackageNotices("swift-numerics", "Numerical support", ("LICENSE.txt",)),
    "swift-syntax": PackageNotices("swift-syntax", "Build-time syntax and macro support", ("LICENSE.txt",)),
    "swift-transformers": PackageNotices("swift-transformers", "Offline tokenizers", ("LICENSE",)),
    "yyjson": PackageNotices("yyjson", "Transitive JSON parsing", ("LICENSE",)),
}

AUDIO_FILES = (
    "README.md", "WEBRTC-LICENSE", "WEBRTC-PATENTS", "ABSEIL-LICENSE", "webrtc/LICENSE",
    "webrtc/third_party/pffft/LICENSE", "webrtc/third_party/rnnoise/COPYING",
    "webrtc/common_audio/third_party/ooura/LICENSE",
    "webrtc/common_audio/third_party/spl_sqrt_floor/LICENSE", "webrtc/modules/third_party/fft/LICENSE",
)

INTRODUCTION = """# Third-party notices

Sillies' original code, documentation, and artwork are covered by its [MIT License](LICENSE).
Third-party software and downloaded model weights keep their respective licenses and notices.
This document ships as `Sillies.app/Contents/Resources/THIRD_PARTY_NOTICES.md`, alongside Sillies'
`LICENSE` and `PRIVACY.md`.

## Scope

The inventory below follows `Package.resolved`, including transitive and build-time dependencies.
It is not a claim that every feature in each upstream package is enabled. Sillies uses FluidAudio's
Diarizer trait without TTS or NeMo text processing, and does not enable MLX guided generation.
Apple's AppKit, SwiftUI, Core ML, Metal, Speech, Vision, Foundation Models, and other system frameworks
are supplied by macOS under Apple's terms, not relicensed by Sillies.

The full upstream license and notice texts are retained below, including Sparkle's embedded notices,
Argmax's derived-code notices, FluidAudio's clustering code, MLX's nested native dependencies, and
WebRTC AudioProcessing's embedded DSP components. Original copyright statements remain unchanged.

## Downloadable models

Weights are optional downloads from the upstream hosts. They are not bundled in Sillies.app and are
not covered by Sillies' MIT license. The catalogs pin individual artifact revisions and hashes;
installed updates may use newer revisions. The links below identify the model publishers and the
converted artifacts used by this catalog. Sillies loads the supplied conversions without changing the
weights and does not claim authorship of them.

- **Whisper:** OpenAI; compiled/compressed Core ML distribution by Argmax. The tokenizer is pinned
  separately in the speech catalog. [Whisper's MIT license](https://github.com/openai/whisper/blob/main/LICENSE).
- **Parakeet Ultra:** NVIDIA's Parakeet, post-trained by Moondream and converted to Core ML by Fluid
  Inference. These are upstream modifications, not work by Sillies. [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode.en).
- **Nemotron 3 speaker detection:** NVIDIA, with Core ML conversion/quantization by Fluid Inference.
  [Upstream attribution and OpenMDW 1.1 license](https://huggingface.co/FluidInference/nemotron-3-diarization-coreml#attribution--license).
- **Qwen3.5:** Qwen/Alibaba, with MLX quantization by MLX Community; Apache 2.0.
- **Gemma 4 E4B:** Google DeepMind, with MLX quantization by MLX Community. Google's
  [Gemma 4 license is Apache 2.0](https://ai.google.dev/gemma/docs/gemma_4_license).
  The pinned community conversion's model-card metadata says `gemma`; the base model's official
  license is linked here to make that metadata discrepancy explicit.
- **Ministral 3 8B:** Mistral AI, with MLX quantization by MLX Community; Apache 2.0.

Apple Speech and Apple Intelligence assets are managed by macOS and remain subject to Apple's terms.
Review the upstream model cards and applicable license before redistributing weights or conversions.

"""

MAINTENANCE = """
## Updating these notices

After resolving a dependency or catalog change, run `python3 scripts/third-party-notices.py` and review
this file. `python3 scripts/third-party-notices.py --check` verifies it against the local resolved
sources and model catalogs; the app build runs that check before packaging. Neither command downloads
weights or makes network requests. A newly resolved package must have an explicit notice entry in the
script. Review nested native libraries and enabled traits too; a top-level license alone may be incomplete.

The full notices below are displayed in collapsible sections for readability. Their upstream text is
preserved, including embedded disclaimers and notices that refer to other upstream package features.

"""


def read_notice(path):
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        raise ValueError(f"Empty third-party notice: {path}")
    return text


def notice_section(title, path):
    text = read_notice(path)
    fence = "`" * max(4, max((len(run) for run in text.split() if set(run) == {"`"}), default=0) + 1)
    return f"<details>\n<summary>{title}</summary>\n\n{fence}text\n{text.rstrip()}\n{fence}\n\n</details>\n\n"


def resolved_packages(root):
    pins = json.loads((root / "Package.resolved").read_text())["pins"]
    identities = {pin["identity"] for pin in pins}
    if len(identities) != len(pins):
        raise ValueError("Duplicate resolved package identity")
    unknown = identities - PACKAGES.keys()
    stale = PACKAGES.keys() - identities
    if unknown or stale:
        raise ValueError(f"Notice inventory differs from Package.resolved: add {sorted(unknown)}, remove {sorted(stale)}")
    return sorted(pins, key=lambda pin: pin["identity"])


def model_inventory(root):
    folder = root / "Sources/SilliesModelStore/Resources"
    speech = json.loads((folder / "speech-models.json").read_text())
    text = json.loads((folder / "text-models.json").read_text())["manifests"]
    lines = ["| Model | License in catalog | Publisher | Pinned artifacts |", "| --- | --- | --- | --- |"]
    for manifest in speech + text:
        model = manifest["model"]
        repository = manifest["artifacts"][0]["url"].split("/resolve/")[0]
        revision = model["revision"]
        lines.append(f'| {model["name"]} | {model["license"]} | [Model card]({model["sourceURL"]}) | [{revision[:12]}]({repository}/tree/{revision}) |')
    return "\n".join(lines) + "\n\n"


def package_inventory(pins):
    lines = ["## Resolved software", "", "| Package | Version | Use |", "| --- | --- | --- |"]
    for pin in pins:
        info = PACKAGES[pin["identity"]]
        location = pin["location"].removesuffix(".git")
        source = f'{location}/tree/{pin["state"]["revision"]}'
        lines.append(f'| [{info.directory}]({source}) | {pin["state"]["version"]} | {info.purpose} |')
    return "\n".join(lines) + "\n\n"


def package_licenses(root, pins):
    sections = ["## Software license texts\n\n"]
    for pin in pins:
        info = PACKAGES[pin["identity"]]
        sections.append(f'### {info.directory} {pin["state"]["version"]}\n\n')
        directory = root / ".build/checkouts" / info.directory
        for filename in info.files:
            sections.append(notice_section(f"{info.directory} — {filename}", directory / filename))
    return "".join(sections)


def audio_licenses(root):
    sections = ["## Vendored echo cancellation\n\nWebRTC AudioProcessing 2.1 and Abseil 20240722.0 are built from the vendored source subset.\nArchive hashes, scope, licenses, and patent grant follow. Embedded DSP notices are included separately.\n\n"]
    for filename in AUDIO_FILES:
        sections.append(notice_section(f"AudioProcessing — {filename}", root / "Vendor/AudioProcessing" / filename))
    return "".join(sections)


def render(root):
    pins = resolved_packages(root)
    return INTRODUCTION + model_inventory(root) + package_inventory(pins) + MAINTENANCE + package_licenses(root, pins) + audio_licenses(root)


def write_atomic(destination, content):
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(content)
            stream.flush()
            temporary.chmod(0o644)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the committed notice document is stale")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    destination = root / "THIRD_PARTY_NOTICES.md"
    content = render(root)
    if arguments.check:
        if not destination.exists() or destination.read_text() != content:
            raise ValueError("THIRD_PARTY_NOTICES.md is stale; run python3 scripts/third-party-notices.py")
        print("Third-party notices match all resolved packages and model catalogs.")
    else:
        write_atomic(destination, content)
        print(f"Wrote {destination.name} with full upstream notices.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"Third-party notices: {error}", file=sys.stderr)
        sys.exit(1)
