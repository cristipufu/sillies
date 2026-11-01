"""Catalog metadata and plural rules shared by validation, editing, and packaging."""
import re


def has_text(value):
    return isinstance(value, str) and bool(value.strip())


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

def english_text(key, source):
    """The English a key stands for: the key itself, or for a named key ("git.status.added") its value in en.json."""
    if isinstance(source, dict):
        other = source.get("other")
        return other if has_text(other) else key
    return source if has_text(source) else key


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
    elif any(not isinstance(category, str) or category not in {"zero", "one", "two", "few", "many", "other"} for category in required + optional):
        problems.append("unknown plural category")
    return problems


def plural_rules(code, data=None):
    if code in LANGUAGES:
        return LANGUAGES[code][2], LANGUAGES[code][3]
    required = (data or {}).get("plurals", ["one", "other"])
    return required, []
