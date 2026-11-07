"""Prepare the frozen BEIR SciFact test split; no labels enter native worker input."""
import csv
import hashlib
import io
import json
from pathlib import Path
import uuid
import zipfile

ARCHIVE_SHA256 = "536e14446a0ba56ed1398ab1055f39fe852686ecad24a6306c80c490fa8e0165"
SOURCE = "https://public.ukp.informatik.tu-darmstadt.de/thakur/BEIR/datasets/scifact.zip"


def identity(key):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "sillies-vault-qualification/scifact/" + key)).upper()


def prepare(archive, output):
    raw = archive.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ARCHIVE_SHA256:
        raise ValueError("The source archive differs from the frozen benchmark")
    with zipfile.ZipFile(io.BytesIO(raw)) as source:
        documents = [json.loads(line) for line in source.read("scifact/corpus.jsonl").splitlines()]
        queries = {item["_id"]: item for item in
                   (json.loads(line) for line in source.read("scifact/queries.jsonl").splitlines())}
        labels = list(csv.DictReader(io.StringIO(source.read("scifact/qrels/test.tsv").decode()), delimiter="\t"))
    expected = {}
    for label in labels:
        key = label["query-id"]
        gold = expected.setdefault("scifact-" + key, {"group": "scifact", "relevant": {}})
        grade = int(label["score"])
        if grade > 0:
            gold["relevant"][identity(label["corpus-id"])] = grade
    inputs = {
        "documents": [{"id": identity(item["_id"]), "title": item["title"], "text": item["text"], "tag": "research"}
                      for item in documents],
        "queries": [{"id": key, "text": queries[key.removeprefix("scifact-")]["text"]} for key in sorted(expected)],
    }
    if len(inputs["documents"]) != 5183 or len(inputs["queries"]) != 300:
        raise ValueError("Unexpected SciFact test split")
    local = Path(__file__).with_name("everyday.json")
    everyday = json.loads(local.read_text())
    inputs["documents"].extend(everyday["documents"])
    for query in everyday["queries"]:
        inputs["queries"].append({key: value for key, value in query.items() if key not in {"group", "relevant"}})
        expected[query["id"]] = {"group": query["group"], "relevant": query["relevant"]}
    output.mkdir(parents=True, exist_ok=False)
    for name, value in [("inputs.json", inputs), ("expected.json", expected)]:
        (output / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    manifest = {
        "source": SOURCE, "archiveSHA256": ARCHIVE_SHA256,
        "corpusLicense": "ODC-By 1.0", "claimsLicense": "CC BY 4.0",
        "attribution": "Wadden et al., Fact or Fiction: Verifying Scientific Claims, EMNLP 2020; BEIR test-split distribution",
        "inputsSHA256": hashlib.sha256((output / "inputs.json").read_bytes()).hexdigest(),
        "expectedSHA256": hashlib.sha256((output / "expected.json").read_bytes()).hexdigest(),
        "documents": len(inputs["documents"]), "queries": len(inputs["queries"]),
        "queriesBeyondSemanticCharacterLimit": sum(len(item["text"]) > 200 for item in inputs["queries"]),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest))


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    prepare(args.archive, args.output)
