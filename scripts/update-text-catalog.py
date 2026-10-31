#!/usr/bin/env python3
"""Regenerate pinned text model manifests without downloading model weights.

Add a reviewed model row here; only metadata and small support files are fetched.
The inference provider interprets the model's own config and chat template.
"""
from dataclasses import dataclass
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


MODELS = [
    ModelEntry(
        identifier="qwen-3.5-4b", name="Qwen3.5 4B",
        repository="mlx-community/Qwen3.5-4B-MLX-4bit",
        revision="32f3e8ecf65426fc3306969496342d504bfa13f3", memory_gb=16,
        detail="Compact multilingual notes and writing.",
        languages="201 languages and dialects; includes English and Romanian."),
    ModelEntry(
        identifier="qwen-3.5-9b", name="Qwen3.5 9B",
        repository="mlx-community/Qwen3.5-9B-MLX-4bit",
        revision="938d8919941c6e7efd3c7150eff7fe9d12afa631", memory_gb=24,
        detail="Larger multilingual model for more demanding summaries.",
        languages="201 languages and dialects; includes English and Romanian."),
    ModelEntry(
        identifier="gemma-4-e4b", name="Gemma 4 E4B",
        repository="mlx-community/gemma-4-E4B-it-4bit",
        revision="475b9088d29754a3379866cf5aeb6b41acd313c2", memory_gb=16,
        detail="Google’s compact model for local notes and writing.",
        languages="Over 140 languages. Quality varies by language."),
    ModelEntry(
        identifier="ministral-3-8b", name="Ministral 3 8B",
        repository="mlx-community/Ministral-3-8B-Instruct-2512-4bit",
        revision="182f003f01daa75f9de0f2c4d379722fd0bc1c61", memory_gb=24,
        detail="Mistral’s multilingual model for local notes and writing.",
        languages="Dozens of languages. Romanian quality requires evaluation."),
]
SUPPORT_FILES = {"config.json", "tokenizer.json", "tokenizer_config.json", "chat_template.jinja", "generation_config.json", "model.safetensors.index.json", "special_tokens_map.json"}

def read(url, maximum_bytes=10 * 1024 * 1024):
    with urlopen(url, timeout=30) as response:
        data = response.read(maximum_bytes + 1)
    if len(data) > maximum_bytes:
        raise ValueError(f"Metadata response exceeds {maximum_bytes} bytes")
    return data

def manifest(model):
    repository, revision = model.repository, model.revision
    metadata = json.loads(read(f"https://huggingface.co/api/models/{repository}/revision/{revision}?blobs=true"))
    if metadata["sha"] != revision:
        raise ValueError("Revision mismatch")
    artifacts = []
    for entry in metadata["siblings"]:
        path = entry["rfilename"]
        if path not in SUPPORT_FILES and not path.endswith(".safetensors"):
            continue
        url = f"https://huggingface.co/{repository}/resolve/{revision}/{path}"
        digest = entry.get("lfs", {}).get("sha256")
        if not digest:
            if entry["size"] > 1_048_576:
                raise ValueError(f"Missing hash for large file {path}")
            digest = hashlib.sha256(read(url)).hexdigest()
        artifacts.append(dict(path=path, url=url, byteCount=entry["size"], sha256=digest))
    return dict(model=dict(id=model.identifier, providerID="mlx", name=model.name, detail=model.detail, revision=revision, license="Apache 2.0", sourceURL=f"https://huggingface.co/{repository}", minimumMemoryGB=model.memory_gb, contextTokens=4096, languagesDescription=model.languages), artifacts=artifacts)

if __name__ == "__main__":
    result = {"manifests": [manifest(row) for row in MODELS]}
    destination = Path(__file__).resolve().parents[1] / "Sources/SilliesModelStore/Resources/text-models.json"
    destination.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(result['manifests'])} pinned model manifests")
