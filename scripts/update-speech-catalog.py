#!/usr/bin/env python3
"""Maintainer-only catalog generation. Never invoked by the application or tests.

Pins artifact revisions and records SHA-256 for every file. Downloads only small
metadata files; model weights use the Hub's LFS content hash.
"""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent


def read_json(url):
    with urlopen(url, timeout=30) as response:
        return json.load(response)


def artifacts(repository, revision, folder="", names=None):
    prefix = folder + "/" if folder else ""
    entries = read_json(
        f"https://huggingface.co/api/models/{repository}/tree/{revision}/{folder}?recursive=true&limit=1000"
    )
    result = []
    for entry in entries:
        if entry["type"] != "file" or entry["path"].endswith(".gitattributes"):
            continue
        path = entry["path"].removeprefix(prefix)
        if names is not None and path not in names:
            continue
        url = f"https://huggingface.co/{repository}/resolve/{revision}/{entry['path']}"
        digest = entry.get("lfs", {}).get("oid")
        if digest is None:
            if entry["size"] > 8_000_000:
                raise ValueError("Unexpected large non-LFS file: " + path)
            with urlopen(url, timeout=30) as response:
                data = response.read()
            if len(data) != entry["size"]:
                raise ValueError("File size changed: " + path)
            digest = hashlib.sha256(data).hexdigest()
        result.append(dict(path=path, url=url, byteCount=entry["size"], sha256=digest))
    return sorted(result, key=lambda item: item["path"])


def main():
    whisper_revision = "0f63a7800b00dd0226abd051b906c246e1907482"
    parakeet_revision = "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
    diarization_revision = "25a90f97f254428d4b30374b76af9c74fdee8327"
    diarization_repository = "FluidInference/nemotron-3-diarization-coreml"
    diarization_bundle = "Nemotron3Diarizer_s32_split_w8a8.mlmodelc"
    diarization_files = artifacts(diarization_repository, diarization_revision, "split/" + diarization_bundle)
    for artifact in diarization_files:
        artifact["path"] = diarization_bundle + "/" + artifact["path"]
    diarization_files += artifacts(diarization_repository, diarization_revision, names={"learnable_sil_emb.bin", "pre_encode_proj_t.bin"})
    # Pin the tokenizer separately, then write its exact revision into artifact URLs.
    tokenizer_revision = '06f233fe06e710322aca913c1bc4249a0d71fce1'
    whisper_files = artifacts("argmaxinc/whisperkit-coreml", whisper_revision, "openai_whisper-large-v3-v20240930_626MB")
    whisper_files += artifacts("openai/whisper-large-v3", tokenizer_revision, names={"tokenizer.json", "tokenizer_config.json", "special_tokens_map.json", "added_tokens.json"})
    whisper_languages = "en zh de es ru ko fr ja pt tr pl ca nl ar sv it id hi fi vi he uk el ms cs ro da hu ta no th ur hr bg lt la mi ml cy sk te fa lv bn sr az sl kn et mk br eu is hy ne mn bs kk sq sw gl mr pa si km sn yo so af oc ka be tg sd gu am yi lo uz fo ht ps tk nn mt sa lb my bo tl mg as tt haw ln ha ba jw su yue".split()
    manifests = [
        dict(model=dict(id="whisper-turbo", providerID="whisperkit", name="Whisper Turbo", detail="Broad multilingual recognition. Choose a language or detect it automatically.", revision=whisper_revision, capabilities=dict(languageControl="selectable", languages=whisper_languages, supportsAutomaticDetection=True, requiresAppleSilicon=True), license="MIT · OpenAI / Argmax", sourceURL="https://huggingface.co/argmaxinc/whisperkit-coreml"), artifacts=whisper_files),
        dict(model=dict(id="parakeet-ultra", providerID="fluidaudio", name="Parakeet Ultra", detail="Automatic recognition in 25 European languages, including English and Romanian.", revision=parakeet_revision, capabilities=dict(languageControl="automatic", languages="bg hr cs da nl en et fi fr de el hu it lv lt mt pl pt ro sk sl es sv ru uk".split(), supportsAutomaticDetection=True, requiresAppleSilicon=True), license="CC BY 4.0 · NVIDIA / Moondream / Fluid Inference", sourceURL="https://huggingface.co/moondream/parakeet-ultra"), artifacts=artifacts("FluidInference/parakeet-ultra-coreml", parakeet_revision)),
        dict(model=dict(id="nemotron-speakers", providerID="nemotron-diarization", name="Speaker detection", detail="Labels up to eight speakers per audio source. Labels appear after a short delay and may need correction. Works alongside any transcription model.", revision=diarization_revision, purpose="speakerDiarization", capabilities=dict(languageControl="automatic", languages=[], supportsAutomaticDetection=False, requiresAppleSilicon=True, maximumSpeakers=8), license="OpenMDW 1.1 · NVIDIA / Fluid Inference", sourceURL="https://huggingface.co/FluidInference/nemotron-3-diarization-coreml"), artifacts=diarization_files),
    ]
    output = ROOT / "Sources/SilliesModelStore/Resources/speech-models.json"
    output.write_text(json.dumps(manifests, indent=2, ensure_ascii=False) + "\n")
    for manifest in manifests:
        print(manifest["model"]["id"], len(manifest["artifacts"]), sum(item["byteCount"] for item in manifest["artifacts"]))


if __name__ == "__main__":
    main()
