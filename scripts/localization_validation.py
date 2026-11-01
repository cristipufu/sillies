"""Pure catalog validation. File access, CLI reporting, and packaging live elsewhere."""
from enum import Enum
from dataclasses import dataclass

from localization_catalog import english_text, has_text, metadata_problems, plural_rules
from localization_formats import placeholder_problem, specifiers


class Coverage(Enum):
    PRESENT = "present"
    COMPLETE = "complete"


@dataclass(frozen=True)
class CatalogContext:
    code: str
    english: dict
    rules: tuple
    coverage: Coverage


def source_problems(english):
    problems = []
    for key, value in english.items():
        if not isinstance(value, dict):
            if not has_text(value):
                problems.append(f"en: “{key}” needs its English text")
            continue
        source = english_text(key, value)
        if not any(kind == "int" for _, kind, _ in specifiers(source)):
            problems.append(f"en: “{key}” has plural forms but no whole-number placeholder")
        for category in ("one", "other"):
            if not has_text(value.get(category)):
                problems.append(f"en: “{key}” needs its English “{category}” form")
        for category, form in value.items():
            problems.extend(form_problems(f"en: “{key}” [{category}]", source, form, Coverage.PRESENT))
    return problems


def catalog_problems(data, code, english, coverage):
    if not isinstance(data, dict):
        return [f"{code}: the language file must be an object"]
    metadata = metadata_problems(data, code)
    if data.get("code") != code:
        metadata.append(f"“code” is {data.get('code')!r}; it must match the file name")
    problems = [f"{code}: {problem}" for problem in metadata]
    strings = data.get("strings")
    if not isinstance(strings, dict):
        return problems + [f"{code}: “strings” must be an object"]
    # Invalid metadata must never reach plural set operations or native packaging.
    if metadata:
        return problems
    if coverage == Coverage.COMPLETE:
        problems.extend(f"{code}: “{key}” is missing its translation" for key in sorted(english.keys() - strings.keys()))
    context = CatalogContext(code, english, plural_rules(code, data), coverage)
    for key, value in strings.items():
        problems.extend(translation_problems(context, key, value))
    return problems


def translation_problems(context, key, value):
    label = f"{context.code}: “{key}”"
    english = context.english
    if key not in english:
        return [f"{label} isn't in the app (anymore); remove it"]
    source = english[key]
    if not isinstance(value, (str, dict)) or isinstance(source, dict) != isinstance(value, dict):
        kind = "plural forms (an object)" if isinstance(source, dict) else "a plain string"
        return [f"{label} should be {kind}"]
    if isinstance(value, dict):
        return plural_problems(label, english_text(key, source), value, context)
    return form_problems(label, english_text(key, source), value, context.coverage)


def plural_problems(label, source, forms, context):
    required, optional = context.rules
    coverage = context.coverage
    problems = []
    extra = set(forms) - set(required + optional)
    if extra:
        problems.append(f"{label} has unused plural forms: {sorted(extra)}")
    filled = [category for category in required if has_text(forms.get(category))]
    if coverage == Coverage.COMPLETE or filled:
        missing = [category for category in required if category not in filled]
        if missing:
            problems.append(f"{label} needs translated plural forms: {missing}")
    for category, form in forms.items():
        problems.extend(form_problems(f"{label} [{category}]", source, form, coverage))
    return problems


def form_problems(label, source, value, coverage):
    if not isinstance(value, str):
        return [f"{label} must be text"]
    if not has_text(value):
        return [f"{label} needs a nonblank translation"] if coverage == Coverage.COMPLETE else []
    problem = placeholder_problem(source, value)
    return [f"{label} {problem}"] if problem else []
