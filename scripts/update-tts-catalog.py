#!/usr/bin/env python3
"""Pin complete offline TTS installations, including codecs, voices and text frontends.

Only metadata and small unhashed support files are fetched; model weights are not.
Runtime layouts intentionally match the pinned FluidAudio and TTSKit versions.
"""
import concurrent.futures
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
MAX_METADATA_BYTES = 24 * 1024 * 1024
KOKORO_REPO = "FluidInference/kokoro-82m-coreml"
KOKORO_V3 = "6c0750dd02ef9d981fb82f147d784a3f171755ee"
KOKORO_BASE = "006395f65025af251858b1ab0a7178a6a1e73f9f"
KOKORO_FRONTEND = "2568276a60ff6e7f312afce3dc9e3f07521cb48d"
POCKET_REPO = "FluidInference/pocket-tts-coreml"
POCKET_REVISION = "b51c4854305532b182026259092cc53e4b600f49"
QWEN_REPO = "argmaxinc/ttskit-coreml"
QWEN_REVISION = "065712357592bc0d194cf7cd91852c5cde3eb1b8"
TOKENIZER_REVISION = "c1899de289a04d12100db370d81485cdf75e47ca"
KOKORO_VOICES = ["af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "af_alloy", "af_aoede", "am_adam", "am_michael", "am_puck", "am_fenrir", "am_echo"]
POCKET_VOICES = ["alba", "marius", "javert", "jean", "fantine", "cosette", "eponine", "azelma"]
QWEN_VOICES = ["ryan", "aiden", "ono-anna", "sohee", "eric", "dylan", "serena", "vivian", "uncle-fu"]
QWEN_LANGUAGES = ["en", "zh", "ja", "ko", "de", "fr", "ru", "pt", "es", "it"]
FISH_REPO = "mlx-community/fish-audio-s2-pro-8bit"
FISH_REVISION = "c8d4481b3f7cbfe64d855c8b7cda7739502fc3ff"
FISH_LANGUAGES = ["en", "ro", "ja", "zh", "ko", "es", "pt", "ar", "ru", "fr", "de", "sv", "it", "tr", "no", "nl", "cy", "eu", "ca", "da", "gl", "ta", "hu", "fi", "pl", "et", "hi", "la", "ur", "th", "vi", "jv", "bn", "yo", "cs", "sw", "nn", "he", "ms", "uk", "id", "kk", "bg", "lv", "my", "tl", "sk", "ne", "fa", "af", "el", "bo", "hr", "sn", "mi", "yi", "am", "be", "km", "is", "az", "sd", "br", "sq", "ps", "mn", "ht", "ml", "sr", "sa", "te", "ka", "bs", "pa", "lt", "kn", "si", "hy", "mr", "as", "gu", "fo"]


def read(url):
    with urlopen(url, timeout=60) as response:
        data = response.read(MAX_METADATA_BYTES + 1)
    if len(data) > MAX_METADATA_BYTES:
        raise ValueError("Model metadata exceeds the size limit")
    return data


def metadata(repository, revision):
    data = json.loads(read(f"https://huggingface.co/api/models/{repository}/revision/{revision}?blobs=true"))
    if data["sha"] != revision:
        raise ValueError("Model revision mismatch")
    return data["siblings"]


def component(repository, revision, source, directory, select):
    def artifact(entry):
        remote = entry["rfilename"]
        relative = remote[len(source) + 1:] if source else remote
        path = f"{directory}/{relative}" if directory else relative
        url = f"https://huggingface.co/{repository}/resolve/{revision}/{remote}"
        digest = entry.get("lfs", {}).get("sha256")
        if not digest:
            if entry["size"] > MAX_METADATA_BYTES:
                raise ValueError(f"Missing hash for large asset {remote}")
            digest = hashlib.sha256(read(url)).hexdigest()
        return dict(path=path, url=url, byteCount=entry["size"], sha256=digest)
    entries = [e for e in metadata(repository, revision) if select(e["rfilename"])]
    if not entries:
        raise ValueError(f"Empty component: {repository}/{source}")
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        artifacts = list(pool.map(artifact, entries))
    return dict(directory=directory, repository=repository, revision=revision, sourceDirectory=source), artifacts


def voices(identifiers, languages):
    return [dict(id=identifier, name=identifier.removeprefix("af_").removeprefix("am_").replace("_", " ").title(), languages=languages) for identifier in identifiers]


def manifest(model, components):
    artifacts = [a for _, items in components for a in items]
    paths = [a["path"] for a in artifacts]
    if len(paths) != len(set(paths)):
        raise ValueError("Duplicate artifact destination")
    return dict(model=model, components=[c for c, _ in components], artifacts=sorted(artifacts, key=lambda a: a["path"]))


def kokoro():
    runtime = f"kokoro-82m-coreml/ANE-v3/{KOKORO_V3}/en"
    base_models = ["KokoroAlbert.mlpackage", "KokoroPostAlbert.mlpackage", "KokoroAlignment.mlpackage", "KokoroProsody_v2.mlmodelc", "KokoroNoise_v2.mlpackage", "KokoroVocoder.mlpackage", "KokoroTail_v2.mlmodelc"]
    parts = [
        component(KOKORO_REPO, KOKORO_V3, "ANE-v3", runtime,
                  lambda p: p == "ANE-v3/manifest.json" or p == "ANE-v3/fast/native-source.json" or ((p.startswith("ANE-v3/fast/") or p.startswith("ANE-v3/decoder/")) and ".mlpackage/" in p)),
        component(KOKORO_REPO, KOKORO_BASE, "ANE", runtime + "/base",
                  lambda p: any(p.startswith("ANE/" + name + "/") for name in base_models)),
        component(KOKORO_REPO, KOKORO_BASE, "ANE", runtime,
                  lambda p: p in {"ANE/vocab.json", "ANE/af_heart.bin"}),
        component(KOKORO_REPO, KOKORO_FRONTEND, "", "kokoro",
                  lambda p: p.startswith(("G2PEncoder.mlmodelc/", "G2PDecoder.mlmodelc/")) or p in {"g2p_vocab.json", "us_lexicon_cache.json"}),
        component(KOKORO_REPO, KOKORO_BASE, "voices", runtime + "/voice-sources",
                  lambda p: p in {f"voices/{v}.json" for v in KOKORO_VOICES if v != "af_heart"}),
    ]
    return manifest(dict(id="kokoro-82m-en", providerID="kokoro", runtimeVariant="english", name="Kokoro", detail="Quick, lightweight English speech with twelve voices. Core ML with FluidAudio.", revision=KOKORO_V3, license="Apache 2.0", sourceURL=f"https://huggingface.co/{KOKORO_REPO}", minimumMemoryGB=8, languages=["en"], voices=voices(KOKORO_VOICES, ["en"]), streamsAudio=False), parts)


def pocket():
    required = ["cond_prefill.mlmodelc/", "flowlm_step.mlmodelc/", "flow_decoder_fused.mlmodelc/", "mimi_decoder.mlmodelc/", "constants_bin/"]
    parts = [component(POCKET_REPO, POCKET_REVISION, "", "Models/pocket-tts",
                       lambda p: any(p.startswith("v2.1/english/" + name) for name in required))]
    return manifest(dict(id="pocket-tts-en", providerID="pocket-tts", runtimeVariant="english", name="Pocket TTS", detail="Streaming English speech with eight voices. Core ML with FluidAudio.", revision=POCKET_REVISION, license="CC BY 4.0 (weights); voice terms apply", sourceURL=f"https://huggingface.co/{POCKET_REPO}", minimumMemoryGB=8, languages=["en"], voices=voices(POCKET_VOICES, ["en"]), streamsAudio=True), parts)


def qwen(variant):
    parts = [
        component(QWEN_REPO, QWEN_REVISION, "", "", lambda p: f"/12hz-{variant}-customvoice/" in p and ".mlmodelc/" in p),
        component("Qwen/Qwen3-0.6B", TOKENIZER_REVISION, "", "tokenizer", lambda p: p in {"config.json", "tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt"}),
    ]
    return manifest(dict(id="qwen3-tts-" + variant, providerID="qwen3-tts", runtimeVariant=variant, name="Qwen3-TTS " + variant.upper(), detail="Nine voices across ten languages. Core ML with Argmax TTSKit.", revision=QWEN_REVISION, license="Apache 2.0", sourceURL=f"https://huggingface.co/{QWEN_REPO}", minimumMemoryGB=8 if variant == "0.6b" else 16, languages=QWEN_LANGUAGES, voices=voices(QWEN_VOICES, QWEN_LANGUAGES), streamsAudio=True), parts)


def fish():
    required = {"config.json", "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json", "model.safetensors", "codec.safetensors"}
    parts = [component(FISH_REPO, FISH_REVISION, "", "", lambda p: p in required)]
    return manifest(dict(id="fish-s2-pro-8bit", providerID="fish-speech", runtimeVariant="s2-pro-8bit", name="Fish S2 Pro", detail="Multilingual speech with an automatic voice that can vary between replies. Slower first audio; requires more memory.", revision=FISH_REVISION, license="Fish Audio Research License (non-commercial)", sourceURL="https://huggingface.co/fishaudio/s2-pro", minimumMemoryGB=24, languages=FISH_LANGUAGES, voices=[dict(id="automatic", name="Automatic voice", languages=FISH_LANGUAGES)], streamsAudio=False), parts)


if __name__ == "__main__":
    models = [kokoro(), pocket(), qwen("0.6b"), qwen("1.7b"), fish()]
    destination = ROOT / "Sources/SilliesModelStore/Resources/tts-models.json"
    destination.write_text(json.dumps(dict(manifests=models), ensure_ascii=False, indent=2) + "\n")
    for item in models:
        print(item["model"]["id"], len(item["artifacts"]), sum(a["byteCount"] for a in item["artifacts"]))
