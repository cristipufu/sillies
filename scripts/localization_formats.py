"""Validate native printf arguments before translations reach Foundation's formatter."""
import re

SPEC = re.compile(r"%(?:(\d+)\$)?[-+ 0#]*(?:\d+)?(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@diuoxXfFeEgGaA%])")
UNSAFE = re.compile(r"%(?:\d+\$)?[-+ 0#]*(?:\*|\d+)?(?:\.(?:\*|\d+))?(?:hh|ll|[hlqLztj])?[npsScC]")


def specifiers(text):
    result = []
    for match in SPEC.finditer(text):
        conversion = match.group(3)
        if conversion == "%":
            continue
        kind = "object" if conversion == "@" else "int" if conversion in "diuoxX" else "float"
        result.append((int(match.group(1)) if match.group(1) else None, kind, match.group(0)))
    return result


def argument_type(spec):
    match = SPEC.fullmatch(spec)
    length, conversion = match.group(2), match.group(3)
    if conversion == "@":
        return "object"
    if conversion in "fFeEgGaA":
        return "long double" if length == "L" else "double"
    return (length or "int") + (" signed" if conversion in "di" else " unsigned")


def placeholder_problem(source, translation):
    unescaped = translation.replace("%%", "")
    if UNSAFE.search(unescaped) or re.search(r"%[^%\s]*\*", unescaped):
        return "contains an unsupported or unsafe format argument"
    wanted = [argument_type(spec) for _, _, spec in specifiers(source)]
    found = specifiers(translation)
    positions = [position for position, _, _ in found]
    if any(position is not None for position in positions):
        if any(position is None for position in positions):
            return "mixes numbered and unnumbered arguments"
        if set(positions) != set(range(1, len(wanted) + 1)):
            return "does not preserve every argument position"
        actual = [(position - 1, argument_type(spec)) for position, _, spec in found]
        if any(wanted[position] != kind for position, kind in actual):
            return "changes an argument's native type"
    elif [argument_type(spec) for _, _, spec in found] != wanted:
        return "does not preserve the source's argument types and order"
    source_formats = [argument_format(spec) for _, _, spec in specifiers(source)]
    for index, (position, _, spec) in enumerate(found):
        source_index = position - 1 if position is not None else index
        if argument_format(spec) != source_formats[source_index]:
            return "changes an argument's formatting; preserve width, precision, and conversion"
    remainder = SPEC.sub("", translation)
    if re.search(r"%[0-9.$*]", remainder):
        return "contains a malformed format argument"
    return None


def argument_format(spec):
    """Only argument order may change; untrusted widths can allocate enormous native buffers."""
    return re.sub(r"^%\d+\$", "%", spec)
