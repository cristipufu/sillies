#!/usr/bin/env python3
"""Sillies's translations: one JSON file per language in Localization/, nothing else to edit.

  scripts/localize.py extract          Update Localization/en.json from the code (builds with Swift to find every string).
  scripts/localize.py check xx|--all   Report problems: unknown keys, placeholders that don't match, plural forms the
                                       language doesn't use, structure. Exits 1 when something must be fixed.
                                       Add --complete to also reject missing or blank translations and plural forms.
  scripts/localize.py stats            How complete each language is.
  scripts/localize.py new xx           Start a language: Localization/xx.json with every string to translate.
  scripts/localize.py build OUT        Write OUT/<code>.lproj/Localizable.strings and .stringsdict for every language
                                       (untranslated strings fall back to English) and print the language codes.

Adapted from Strata Files’ JSON catalog tooling (MIT); see THIRD_PARTY_NOTICES.md.

A language file:
  {
    "language": "Deutsch", "english": "German", "code": "de", "maintainers": ["Your Name"],
    "strings": {
      "Move to Trash": "In den Papierkorb legen",
      "Rename %lld Items…": {"one": "%lld Objekt umbenennen…", "other": "%lld Objekte umbenennen…"}
    }
  }
Keys are the English text as written in the code, with placeholders (%@ text, %lld whole number, %lf number). Strings
that change with a number are objects with one form per plural category the language uses (CLDR).
"""
import contextlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FOLDER = ROOT / "Localization"
SOURCE = FOLDER / "en.json"

# Languages Sillies knows the names and plural rules of. Another language works too: `new` asks for its names, and
# its plural categories default to one/other (pass --plurals one,few,other to change them).
LANGUAGES = {
    "en": ("English", "English", ["one", "other"], []),
    "de": ("Deutsch", "German", ["one", "other"], []),
    "fr": ("Français", "French", ["one", "other"], ["many"]),
    "es": ("Español", "Spanish", ["one", "other"], ["many"]),
    "it": ("Italiano", "Italian", ["one", "other"], ["many"]),
    "pt-BR": ("Português (Brasil)", "Portuguese (Brazil)", ["one", "other"], ["many"]),
    "pt-PT": ("Português (Portugal)", "Portuguese (Portugal)", ["one", "other"], ["many"]),
    "nl": ("Nederlands", "Dutch", ["one", "other"], []),
    "sv": ("Svenska", "Swedish", ["one", "other"], []),
    "da": ("Dansk", "Danish", ["one", "other"], []),
    "nb": ("Norsk bokmål", "Norwegian Bokmål", ["one", "other"], []),
    "pl": ("Polski", "Polish", ["one", "few", "many", "other"], []),
    "cs": ("Čeština", "Czech", ["one", "few", "other"], ["many"]),
    "hu": ("Magyar", "Hungarian", ["one", "other"], []),
    "ro": ("Română", "Romanian", ["one", "few", "other"], []),
    "uk": ("Українська", "Ukrainian", ["one", "few", "many", "other"], []),
    "ru": ("Русский", "Russian", ["one", "few", "many", "other"], []),
    "tr": ("Türkçe", "Turkish", ["one", "other"], []),
    "ja": ("日本語", "Japanese", ["other"], []),
    "ko": ("한국어", "Korean", ["other"], []),
    "zh-Hans": ("简体中文", "Chinese (Simplified)", ["other"], []),
    "zh-Hant": ("繁體中文", "Chinese (Traditional)", ["other"], []),
}

from localization_formats import SPEC, specifiers, placeholder_problem


def english_text(key, source):
    """The English a key stands for: the key itself, or for a named key ("git.status.added") its value in en.json."""
    if isinstance(source, dict):
        other = source.get("other")
        return other if has_text(other) else key
    return source if has_text(source) else key


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def metadata_problems(data, code):
    problems = []
    if not re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*", code) or len(code) > 35:
        problems.append("invalid language code")
    for field in ("language", "english"):
        value = data.get(field)
        if not has_text(value) or len(value) > 80 or any(ord(c) < 32 for c in value):
            problems.append(f"{field} must be a short, nonblank language name")
    maintainers = data.get("maintainers", [])
    if not isinstance(maintainers, list) or any(not has_text(name) for name in maintainers):
        problems.append("maintainers must be a list of nonblank names")
    required, optional = plural_rules(code, data)
    if not isinstance(required, list) or not required or "other" not in required:
        problems.append("plural categories must include other")
    elif set(required + optional) - {"zero", "one", "two", "few", "many", "other"}:
        problems.append("unknown plural category")
    return problems


def load(path):
    with open(path, encoding="utf-8") as file:
        return json.load(file, object_pairs_hook=unique_keys)


def save(path, data):
    data = dict(data)
    data["strings"] = dict(sorted(data.get("strings", {}).items(), key=lambda item: item[0].lower()))
    if "notes" in data:
        data["notes"] = dict(sorted(data["notes"].items(), key=lambda item: item[0].lower()))
    with open(path, "w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2)
        file.write("\n")


def plural_rules(code, data=None):
    if code in LANGUAGES:
        return LANGUAGES[code][2], LANGUAGES[code][3]
    required = (data or {}).get("plurals") or ["one", "other"]
    return required, []


# macOS's permission prompts are the Info.plist's *UsageDescription texts: they're in en.json under named keys
# ("infoplist.NSDesktopFolderUsageDescription"), translated like any string, and built into InfoPlist.strings.
INFO_PLIST = ROOT / "Info.plist"
PLIST_PREFIX = "infoplist."


def info_plist_strings():
    import plistlib
    if not INFO_PLIST.exists():
        return {}
    with open(INFO_PLIST, "rb") as file:
        info = plistlib.load(file)
    return {name: text for name, text in info.items() if name.endswith("UsageDescription") and isinstance(text, str)}


def language_files():
    return sorted(path for path in FOLDER.glob("*.json") if path.name != "en.json")


# MARK: - extract

def catalog_strings():
    """Explicit display fields only. Never collect character prompts, runtime IDs, or licenses."""
    found = {}
    def add(text, path):
        if has_text(text):
            found.setdefault(text, {"comments": {"Bundled catalog display text"}, "places": [], "value": None})["places"].append(str(path.relative_to(ROOT)))
    for path in (ROOT / "Sources/SilliesApp/Resources/Characters").glob("*.json"):
        character = load(path)
        for key in ("subtitle", "bio"):
            add(character.get(key), path)
    path = ROOT / "Sources/SilliesApp/Resources/Scenes/playful-scenes.json"
    for scene in load(path):
        for text in scene.get("messages", []):
            add(text, path)
    for path in (ROOT / "Sources/SilliesModelStore/Resources").glob("*-models.json"):
        data = load(path)
        for manifest in (data if isinstance(data, list) else data.get("manifests", [])):
            for key in ("detail", "languagesDescription"):
                add(manifest["model"].get(key), path)
    return found


@contextlib.contextmanager
def extraction_workspace():
    # Keep the path stable so SwiftPM can reuse compiler output on subsequent extractions.
    directory = ROOT / ".build" / "localization-extraction"
    directory.mkdir(parents=True, exist_ok=True)
    yield directory


def extract(mode="update"):
    """Builds the app with the compiler's string extraction on, then rewrites en.json: new strings added (as their own
    English), gone ones removed, plural forms and translators' notes kept."""
    with extraction_workspace() as scratch:
        out = Path(scratch) / "strings"
        out.mkdir(exist_ok=True)
        command = ["swift", "build", "--product", "Sillies", "-Xswiftc", "-emit-localized-strings", "-Xswiftc", "-emit-localized-strings-path", "-Xswiftc", str(out)]
        print("Building to find every string (a minute or two)…", file=sys.stderr)
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit("The build failed:\n" + result.stderr[-4000:] + result.stdout[-4000:])
        found = {}
        for path in sorted(out.rglob("*.stringsdata")):
            data = load(path)
            source_path = Path(data.get("source", ""))
            if not source_path.is_absolute():
                source_path = ROOT / source_path
            if not source_path.is_relative_to(ROOT / "Sources") or not source_path.exists():
                continue
            source = str(source_path.relative_to(ROOT))
            for entry in data.get("tables", {}).get("Localizable", []):
                key = entry["key"]
                where = source
                comment = entry.get("comment", "")
                note = found.setdefault(key, {"comments": set(), "places": [], "value": None})
                if comment:
                    note["comments"].add(comment)
                # A named key (String(localized: "git.status.added", defaultValue: "Added")) carries its English.
                if entry.get("value"):
                    note["value"] = entry["value"]
                note["places"].append(where)
    for name, info in catalog_strings().items():
        note = found.setdefault(name, {"comments": set(), "places": [], "value": None})
        note["comments"].update(info["comments"])
        note["places"].extend(info["places"])
    for name, text in info_plist_strings().items():
        found[PLIST_PREFIX + name] = {"comments": {"macOS permission prompt (Info.plist), shown the first time Sillies opens that place"},
                                      "places": [f"Info.plist {name}"], "value": text}
    old = load(SOURCE) if SOURCE.exists() else {"language": "English", "english": "English", "code": "en", "maintainers": []}
    strings = {}
    notes = {}
    for key, info in found.items():
        previous = old.get("strings", {}).get(key)
        english = info["value"] or key
        wants_plural = any(c.lower().startswith("plural") for c in info["comments"])
        if isinstance(previous, dict):
            strings[key] = previous
        elif wants_plural:
            # The English singular is written by hand ("Rename %lld Item…"); check reports it until it is.
            strings[key] = {"one": "", "other": english}
        else:
            strings[key] = english
        comments = sorted(c for c in info["comments"] if c.lower() != "plural")
        notes[key] = " · ".join(comments + [", ".join(sorted(set(info["places"]))[:3])])
    added = set(strings) - set(old.get("strings", {}))
    removed = set(old.get("strings", {})) - set(strings)
    if mode == "check":
        if strings != old.get("strings"):
            sys.exit(f"English catalog is stale: {len(added)} new, {len(removed)} removed keys. Run scripts/localize.py extract.")
        print(f"English catalog matches {len(strings)} source strings.")
        return
    old["strings"] = strings
    old["notes"] = notes
    save(SOURCE, old)
    print(f"en.json: {len(strings)} strings ({len(added)} new, {len(removed)} gone).")


# MARK: - check

def has_text(value):
    return isinstance(value, str) and bool(value.strip())


def check(code_or_all, complete=False):
    english = load(SOURCE)["strings"]
    problems = 0
    for key, value in english.items():
        if isinstance(value, dict):
            ints = [kind for _, kind, _ in specifiers(english_text(key, value)) if kind == "int"]
            if not ints:
                print(f"en: “{key}” has plural forms but no whole-number placeholder")
                problems += 1
            for category in ("one", "other"):
                if not has_text(value.get(category)):
                    print(f"en: “{key}” needs its English “{category}” form")
                    problems += 1
            for category, form in value.items():
                if not isinstance(form, str):
                    print(f"en: “{key}” [{category}] must be text")
                    problems += 1
                elif form and (problem := placeholder_problem(english_text(key, value), form)):
                    print(f"en: “{key}” [{category}] {problem}")
                    problems += 1
        elif not has_text(value):
            print(f"en: “{key}” needs its English text")
            problems += 1
    paths = [SOURCE] + language_files() if code_or_all == "--all" else [FOLDER / f"{code_or_all}.json"]
    for path in paths:
        if not path.exists():
            sys.exit(f"No {path.name}; start one with: scripts/localize.py new {path.stem}")
        try:
            data = load(path)
        except (ValueError, OSError) as error:
            print(f"{path.name}: not valid JSON ({error})")
            problems += 1
            continue
        code = path.stem
        if not isinstance(data, dict):
            print(f"{code}: the language file must be an object")
            problems += 1
            continue
        for field in ("language", "english", "code", "strings"):
            if field not in data:
                print(f"{code}: missing “{field}”")
                problems += 1
        if data.get("code") != code:
            print(f"{code}: “code” is {data.get('code')!r}; it must match the file name")
            problems += 1
        for problem in metadata_problems(data, code):
            print(f"{code}: {problem}")
            problems += 1
        required, optional = plural_rules(code, data)
        strings = data.get("strings", {})
        if not isinstance(strings, dict):
            print(f"{code}: “strings” must be an object")
            problems += 1
            continue
        if complete:
            for key in sorted(english.keys() - strings.keys()):
                print(f"{code}: “{key}” is missing its translation")
                problems += 1
        for key, value in strings.items():
            if key not in english:
                print(f"{code}: “{key}” isn't in the app (anymore); remove it")
                problems += 1
                continue
            source = english[key]
            if (not isinstance(value, (str, dict)) or
                    isinstance(source, dict) != isinstance(value, dict)):
                kind = "plural forms (an object)" if isinstance(source, dict) else "a plain string"
                print(f"{code}: “{key}” should be {kind}")
                problems += 1
                continue
            if isinstance(value, dict):
                extra = set(value) - set(required) - set(optional)
                if extra:
                    print(f"{code}: “{key}” has forms {sorted(extra)} that {code} doesn't use (it uses {required + optional})")
                    problems += 1
                filled = [category for category in required if has_text(value.get(category))]
                if (complete or filled) and len(filled) != len(required):
                    missing = [category for category in required if category not in filled]
                    print(f"{code}: “{key}” needs translated plural forms: {missing}")
                    problems += 1
                for category, form in value.items():
                    if not isinstance(form, str):
                        print(f"{code}: “{key}” [{category}] must be text")
                        problems += 1
                    elif complete and not has_text(form) and category not in required:
                        print(f"{code}: “{key}” [{category}] needs a nonblank translation")
                        problems += 1
                    elif has_text(form) and (problem := placeholder_problem(english_text(key, source), form)):
                        print(f"{code}: “{key}” [{category}] {problem}")
                        problems += 1
            elif complete and not has_text(value):
                print(f"{code}: “{key}” needs a nonblank translation")
                problems += 1
            elif has_text(value) and (problem := placeholder_problem(english_text(key, source), value)):
                print(f"{code}: “{key}” {problem}")
                problems += 1
    if problems:
        print(f"{problems} problem{'s' if problems != 1 else ''}.")
        sys.exit(1)
    print("No problems.")


# MARK: - stats

def sync():
    """Update catalog shapes without inventing translations or replacing completed work."""
    english = load(SOURCE)["strings"]
    for path in language_files():
        data = load(path)
        previous = data.get("strings", {})
        required, _ = plural_rules(path.stem, data)
        strings = {}
        for key, source in english.items():
            value = previous.get(key)
            if isinstance(source, dict):
                strings[key] = {category: value.get(category, "") if isinstance(value, dict) else "" for category in required}
            else:
                strings[key] = value if isinstance(value, str) else ""
        data["strings"] = strings
        save(path, data)
        print(f"{path.stem}: {len(set(english) - set(previous))} added, {len(set(previous) - set(english))} removed; new values await translation.")

def is_translated(value):
    if isinstance(value, dict):
        return bool(value) and all(has_text(form) for form in value.values())
    return has_text(value)


def stats():
    english = load(SOURCE)["strings"]
    total = len(english)
    print(f"{'Language':<28} {'Code':<8} {'Done':>11}")
    for path in language_files():
        data = load(path)
        done = sum(1 for key, value in data.get("strings", {}).items() if key in english and is_translated(value))
        share = 100 * done / total if total else 100
        print(f"{data.get('english', path.stem):<28} {path.stem:<8} {done:>5}/{total:<5} {share:5.1f}%")


# MARK: - new

def new(code, plurals=None):
    if not re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*", code):
        sys.exit("Use a language code such as de or pt-BR.")
    path = FOLDER / f"{code}.json"
    if path.exists():
        sys.exit(f"{path.name} exists already.")
    if code in LANGUAGES:
        native, english_name, required, _ = LANGUAGES[code]
    else:
        native = input(f"The language's name in itself (e.g. Deutsch): ").strip()
        english_name = input("Its name in English (e.g. German): ").strip()
        required = plurals or ["one", "other"]
    english = load(SOURCE)["strings"]
    strings = {key: ({category: "" for category in required} if isinstance(value, dict) else "") for key, value in english.items()}
    data = {"language": native, "english": english_name, "code": code, "maintainers": [], "strings": strings}
    if code not in LANGUAGES:
        data["plurals"] = required
    save(path, data)
    print(f"Created {path.relative_to(ROOT)} with {len(strings)} strings to translate.")


# MARK: - build

def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def positional(text):
    """Placeholders numbered in order (%@ … %lld → %1$@ … %2$lld), as plural forms need."""
    index = 0

    def number(match):
        nonlocal index
        if match.group(3) == "%" or match.group(1):
            return match.group(0)
        index += 1
        return "%" + f"{index}$" + match.group(0)[1:]
    return SPEC.sub(number, text)


def build(out, info_plist=None):
    import plistlib
    # Packaging never silently accepts missing or unsafe translations.
    with contextlib.redirect_stdout(sys.stderr):
        check("--all", complete=True)
    out = Path(out)
    english = load(SOURCE)["strings"]
    codes = ["en"]
    files = [(SOURCE, "en")] + [(path, path.stem) for path in language_files()]
    for path, code in files:
        data = load(path)
        if code != "en":
            codes.append(code)
        strings = data.get("strings", {})
        folder = out / f"{code}.lproj"
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
        lines = []
        info_lines = []
        plurals = {}
        for key, source in english.items():
            value = strings.get(key)
            text = english_text(key, source)
            if key.startswith(PLIST_PREFIX):
                # Untranslated, macOS shows the Info.plist's English.
                if code != "en" and isinstance(value, str) and value and not placeholder_problem(text, value):
                    info_lines.append(f'"{escape(key[len(PLIST_PREFIX):])}" = "{escape(value)}";')
                continue
            if isinstance(source, dict):
                forms = value if isinstance(value, dict) and is_translated(value) else source
                # A form whose placeholders don't match would crash the app when shown: English instead.
                if forms is not source and any(placeholder_problem(text, form) for form in forms.values() if form):
                    forms = source
                if not all(forms.values()):
                    continue
                ints = [i for i, (_, kind, _) in enumerate(specifiers(text)) if kind == "int"]
                if not ints:
                    continue
                spec = specifiers(text)[ints[0]][2]
                value_type = re.sub(r"^%(\d+\$)?", "", spec)
                variable = {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": value_type}
                for category, form in forms.items():
                    variable[category] = positional(form)
                plurals[key] = {"NSStringLocalizedFormatKey": f"%{ints[0] + 1}$#@n@", "n": variable}
            elif isinstance(value, str) and value and value != key and not placeholder_problem(text, value):
                lines.append(f'"{escape(key)}" = "{escape(value)}";')
            elif code != "en" and key != text:
                # A named key nobody has translated yet: its English, rather than the key.
                lines.append(f'"{escape(key)}" = "{escape(text)}";')
        (folder / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
        if info_lines:
            (folder / "InfoPlist.strings").write_text("\n".join(info_lines) + "\n", encoding="utf-8")
        if plurals:
            with open(folder / "Localizable.stringsdict", "wb") as file:
                plistlib.dump(plurals, file)
    metadata = [{key: load(path)[key] for key in ("code", "language", "english")} for path, _ in files]
    (out / "Languages.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if info_plist:
        path = Path(info_plist)
        with path.open("rb") as file:
            info = plistlib.load(file)
        info["CFBundleDevelopmentRegion"] = "en"
        info["CFBundleLocalizations"] = codes
        with path.open("wb") as file:
            plistlib.dump(info, file)
    print(",".join(codes))


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        return
    command = args[0]
    if command == "extract":
        extract("check" if "--check" in args else "update")
    elif command == "check" and (len(args) == 2 or (len(args) == 3 and args[2] == "--complete")):
        check(args[1], complete=len(args) == 3)
    elif command == "stats":
        stats()
    elif command == "sync":
        sync()
    elif command == "new" and len(args) >= 2:
        plurals = None
        if "--plurals" in args:
            plurals = args[args.index("--plurals") + 1].split(",")
        new(args[1], plurals)
    elif command == "build" and len(args) in (2, 4):
        if len(args) == 4 and args[2] != "--plist":
            sys.exit("Usage: localize.py build OUT [--plist Info.plist]")
        build(args[1], args[3] if len(args) == 4 else None)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
