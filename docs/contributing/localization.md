# Add or improve a language

Sillies uses one JSON catalog per interface language in [`Localization`](../../Localization).
Adding a language does not require a Swift switch, a Settings row, or a package registration.
The build discovers the files, validates them, and generates native `.lproj` resources and the
language picker metadata. Nothing is translated over the network at runtime.

Extraction keeps compiler output in separate module directories so same-named dependency files
cannot overwrite app strings. The compiler wrapper is only used by `localize.py extract`.

## Contribute a catalog

1. Copy `Localization/en.json` to a language-code filename, such as `fi.json`, or run
   `python3 scripts/localize.py new fi`. Use a regional code when the writing differs, such as
   `pt-BR`, `pt-PT`, `zh-Hans`, or `zh-Hant`.
2. Set `code` to the filename, `language` to the language's own name, and `english` to its English name.
   `maintainers` is optional attribution for people maintaining that translation. Remove copied
   English `notes`; they are context for translators, not strings shown in the app.
3. Translate every value in `strings`. Keep the English keys unchanged. Preserve product and model
   names, file extensions, and keyboard shortcuts. Match the purpose of the control: a recording
   action and a saved record are different meanings of “record.”
4. Preserve placeholders such as `%@` and `%lld`, including their native types. Reordering is allowed
   with numbered arguments: `%@ · %lld items` can become `%2$lld … %1$@`. Do not change `%lld` to `%d`,
   introduce `%n`, or add formatting arguments.
5. Translate every plural category required for the language. A plural value is an object such as
   `{"one": "%lld item", "other": "%lld items"}`. For a new language outside the tooling's existing
   CLDR rules, add a top-level `plurals` array; include `other`. Never build plurals by appending “s.”

```sh
python3 scripts/localize.py check --all --complete
python3 scripts/localize.py stats
make check BUILD_DIR=/tmp/sillies-localization
```

Select the language in **Settings → General → Language**, then reopen Sillies. The change deliberately
waits until the next launch so it cannot interrupt a recording or discard a draft. Interface language
does not change recognition, translation output, or a companion's spoken language.

## Add interface copy

Use a literal native SwiftUI label (`Text("Save")`, `Button("Save")`) or `String(localized:)` for
computed labels, AppKit menus, notices, and error descriptions. A conditional string passed to `Text`
is already a `String`, so localize each branch explicitly. Pass complete sentences with interpolation;
do not concatenate translated fragments. Use `comment: "plural"` for count-dependent copy and fill
the English singular form in the catalog.

```sh
source scripts/toolchain.sh
python3 scripts/localize.py extract
python3 scripts/localize.py sync
```

Extraction uses the Swift compiler, including its actual interpolation types. It also collects
permission prompts, character subtitles/bios, scene messages, and designated model
description fields. `sync` removes retired keys and adds blank entries for new ones while preserving
completed translations. Update every shipped translation before packaging.

Keep user content, speech transcripts, model prompts, identifiers, diagnostic logs, and canonical
archive markers out of translation catalogs. `LocalizedCatalogText` is only for the explicitly
extracted display fields in bundled JSON. Persisted speaker markers must remain parseable when the
interface language changes.

## Review the result

Use natural, concise language that fits Sillies' warm voice. Review technical and permission language
carefully; an automatic translation is a draft, not proof of accuracy. Test long labels, plural counts,
diacritics, CJK scripts, text selection, and minimum window sizes. Check the language picker, Settings,
Chat, the skill wheel, permissions, and Vault actions.

`make check` rejects missing keys, blank values, duplicate JSON keys, mismatched placeholders, missing
plural forms, and a stale English source catalog. A Swift syntax check catches unlocalized display
properties and custom view arguments. These checks cannot judge whether a translation sounds natural;
native-speaker corrections are welcome.

For a release or a catalog/layout change, exercise the real app windows in every packaged language:

```sh
python3 scripts/test-localized-windows.py /tmp/sillies-localization/Sillies.app \
  --snapshots /tmp/sillies-language-previews
```

This runs the existing activation, close/reopen, companion exclusion, and stacking checks sequentially.
Each language has a 45-second deadline. Previews contain fixture content only; inspect them for
truncation and wording. The command does not replace or restart your normal running app.

The CLI owns catalog I/O and reporting. `localization_catalog.py` owns metadata and plural rules; `localization_validation.py` returns diagnostics without I/O or process exits. Use `Coverage.PRESENT` while authoring and `Coverage.COMPLETE` for shipping. The CLI flags remain unchanged.
