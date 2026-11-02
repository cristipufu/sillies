#!/usr/bin/env python3
"""Regenerate pinned text model manifests without downloading model weights.

Add a reviewed model row here; only metadata and small support files are fetched.
The inference provider interprets the model's own config and chat template.
"""
from dataclasses import dataclass
from datetime import date
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

@dataclass(frozen=True)
class ModelEntry:
    identifier: str
    name: str
    repository: str
    revision: str
    memory_gb: int
    detail: str
    languages: str
    release_date: str
    release_source: str
    license: str = "Apache 2.0"
    reasoning: str | None = None


MODELS = [
    ModelEntry(
        identifier="qwen-3.5-2b", name="Qwen3.5 2B",
        repository="mlx-community/Qwen3.5-2B-4bit",
        revision="674aaa7240b91e8012fcad5d791b7dfe5ba90207", memory_gb=8,
        detail="Lightweight multilingual chat and short writing tasks.",
        languages="201 languages and dialects.",
        release_date="2026-03-02", release_source="https://github.com/QwenLM/Qwen3.8#news"),
    ModelEntry(
        identifier="qwen-3.5-4b", name="Qwen3.5 4B",
        repository="mlx-community/Qwen3.5-4B-MLX-4bit",
        revision="32f3e8ecf65426fc3306969496342d504bfa13f3", memory_gb=16,
        detail="Compact multilingual notes and writing.",
        languages="201 languages and dialects.",
        release_date="2026-03-02", release_source="https://github.com/QwenLM/Qwen3.8#news"),
    ModelEntry(
        identifier="qwen-3.5-9b", name="Qwen3.5 9B",
        repository="mlx-community/Qwen3.5-9B-MLX-4bit",
        revision="938d8919941c6e7efd3c7150eff7fe9d12afa631", memory_gb=24,
        detail="Larger multilingual model for more demanding summaries.",
        languages="201 languages and dialects.",
        release_date="2026-03-02", release_source="https://github.com/QwenLM/Qwen3.8#news"),
    ModelEntry(
        identifier="gemma-4-e4b", name="Gemma 4 E4B",
        repository="mlx-community/gemma-4-E4B-it-4bit",
        revision="475b9088d29754a3379866cf5aeb6b41acd313c2", memory_gb=16,
        detail="Google’s compact model for local notes and writing.",
        languages="Over 140 languages. Quality varies by language.",
        release_date="2026-04-02", release_source="https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/"),
    ModelEntry(
        identifier="gemma-4-26b-a4b", name="Gemma 4 26B A4B",
        repository="mlx-community/gemma-4-26B-A4B-it-4bit",
        revision="0d77464eeb233a2da68ebf9d7dc4edaac7db956d", memory_gb=32,
        detail="Larger model for conversations and summaries. Requires more available memory.",
        languages="Over 140 languages. Quality varies by language.",
        release_date="2026-04-02", release_source="https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/"),
    ModelEntry(
        identifier="ministral-3-8b", name="Ministral 3 8B",
        repository="mlx-community/Ministral-3-8B-Instruct-2512-4bit",
        revision="182f003f01daa75f9de0f2c4d379722fd0bc1c61", memory_gb=24,
        detail="Mistral’s multilingual model for local notes and writing.",
        languages="Dozens of languages; quality varies by language.",
        release_date="2025-12-02", release_source="https://mistral.ai/news/mistral-3"),
    ModelEntry(
        identifier="nemotron-3.5-bolt-e4b", name="Nemotron 3.5 Bolt E4B",
        repository="mlx-community/NVIDIA-Nemotron-3.5-Bolt-E4B-OptiQ-4bit",
        revision="0c204a16b6b186d1434e70f5fc2ca2e30984a006", memory_gb=24,
        detail="Compact multilingual notes and writing.",
        languages="35 languages. Quality varies by language.",
        release_date="2026-10-23", release_source="https://research.nvidia.com/labs/nemotron/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB/",
        license="OpenMDW 1.1"),
    ModelEntry(
        identifier="lfm-2.5-2.6b", name="LFM2.5 2.6B",
        repository="LiquidAI/LFM2.5-2.6B-MLX-4bit",
        revision="04efa23776ce61ec34ec95ec34c859854c89542b", memory_gb=8,
        detail="Compact multilingual notes and writing.",
        languages="16 languages. Quality varies by language.",
        release_date="2026-08-04", release_source="https://www.liquid.ai/blog/lfm2-5-2-6b",
        license="LFM Open License 1.0", reasoning="alwaysOnThinkTags"),
    ModelEntry(
        identifier="gemma-4-12b", name="Gemma 4 12B",
        repository="mlx-community/gemma-4-12B-it-4bit",
        revision="73bcf09092aa277861d5a191b989b666f7f32e8f", memory_gb=24,
        detail="Larger multilingual model for more demanding summaries.",
        languages="Over 140 languages. Quality varies by language.",
        release_date="2026-06-03", release_source="https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemma-4-12b/",
        license="Apache 2.0"),
    ModelEntry(
        identifier="granite-4.2-3b", name="Granite 4.2 3B",
        repository="ibm-granite/granite-4.2-3b-q4-mlx",
        revision="0c6f39b1827afd5eb2c1c3b13751929857434953", memory_gb=8,
        detail="Compact multilingual notes and writing.",
        languages="12 languages. Quality varies by language.",
        release_date="2026-08-25", release_source="https://research.ibm.com/blog/introducing-granite-4-2",
        license="Apache 2.0", reasoning="switchableThinkTags"),
    ModelEntry(
        identifier="granite-4.2-8b", name="Granite 4.2 8B",
        repository="ibm-granite/granite-4.2-8b-q4-mlx",
        revision="9047f073e46c527f70dade07bb55b1700d728e36", memory_gb=16,
        detail="Larger multilingual model for more demanding summaries.",
        languages="12 languages. Quality varies by language.",
        release_date="2026-08-25", release_source="https://research.ibm.com/blog/introducing-granite-4-2",
        license="Apache 2.0", reasoning="switchableThinkTags"),
    ModelEntry(
        identifier="lfm-2.5-24b-a2b", name="LFM2.5 24B A2B",
        repository="LiquidAI/LFM2.5-24B-A2B-MLX-4bit",
        revision="667408d494bde191c2cb9dd4f4549827816b9275", memory_gb=32,
        detail="Larger model for conversations and summaries. Requires more available memory.",
        languages="16 languages. Quality varies by language.",
        release_date="2026-10-13", release_source="https://www.liquid.ai/blog/lfm2-5-24b-a2b",
        license="LFM Open License 1.0", reasoning="alwaysOnThinkTags"),
]
SUPPORT_FILES = {"config.json", "tokenizer.json", "tokenizer_config.json", "chat_template.jinja", "generation_config.json", "model.safetensors.index.json", "special_tokens_map.json"}
MAXIMUM_SUPPORT_BYTES = 32 * 1024 * 1024

def read(url, maximum_bytes=10 * 1024 * 1024):
    with urlopen(url, timeout=30) as response:
        data = response.read(maximum_bytes + 1)
    if len(data) > maximum_bytes:
        raise ValueError(f"Metadata response exceeds {maximum_bytes} bytes")
    return data

def descriptor(model):
    date.fromisoformat(model.release_date)
    if not model.release_source.startswith("https://"):
        raise ValueError("Release provenance requires HTTPS")
    return dict(
        id=model.identifier, providerID="mlx", name=model.name, detail=model.detail,
        revision=model.revision, license=model.license, reasoning=model.reasoning,
        release=dict(date=model.release_date, sourceURL=model.release_source),
        sourceURL=f"https://huggingface.co/{model.repository}",
        minimumMemoryGB=model.memory_gb, contextTokens=4096,
        languagesDescription=model.languages)


def artifact(model, entry):
    path = entry["rfilename"]
    url = f"https://huggingface.co/{model.repository}/resolve/{model.revision}/{path}"
    digest = entry.get("lfs", {}).get("sha256")
    if not digest:
        if path not in SUPPORT_FILES or entry["size"] > MAXIMUM_SUPPORT_BYTES:
            raise ValueError(f"Missing hash for large or weight file {path}")
        contents = read(url, maximum_bytes=MAXIMUM_SUPPORT_BYTES)
        if len(contents) != entry["size"]:
            raise ValueError(f"Metadata length mismatch: {path}")
        digest = hashlib.sha256(contents).hexdigest()
    return dict(path=path, url=url, byteCount=entry["size"], sha256=digest)


def manifest(model):
    description = descriptor(model)
    repository, revision = model.repository, model.revision
    metadata = json.loads(read(f"https://huggingface.co/api/models/{repository}/revision/{revision}?blobs=true"))
    if metadata["sha"] != revision:
        raise ValueError("Revision mismatch")
    artifacts = []
    for entry in metadata["siblings"]:
        path = entry["rfilename"]
        if path not in SUPPORT_FILES and not path.endswith(".safetensors"):
            continue
        artifacts.append(artifact(model, entry))
    return dict(model=description, artifacts=artifacts)

if __name__ == "__main__":
    result = {"manifests": [manifest(row) for row in MODELS]}
    destination = Path(__file__).resolve().parents[1] / "Sources/SilliesModelStore/Resources/text-models.json"
    destination.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(result['manifests'])} pinned model manifests")
