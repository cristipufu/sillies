# Interface languages

Each `.json` file is a complete, independently discoverable language contribution.
Start with the [localization guide](../docs/contributing/localization.md) for the schema, placeholders,
plurals, extraction, and checks.

The initial languages match Strata Files: `cs`, `da`, `de`, `en`, `es`, `fr`, `hu`, `it`, `ja`, `ko`,
`nb`, `nl`, `pl`, `pt-BR`, `pt-PT`, `ro`, `ru`, `sv`, `tr`, `uk`, `zh-Hans`, and `zh-Hant`.
This list is documentation, not an application registry; adding another valid catalog is sufficient.

`en.json` is generated from source and also holds translator context. Other catalogs contain translated
values under the same keys. Build products are native `Localizable.strings`, `Localizable.stringsdict`,
and `InfoPlist.strings`; do not commit generated `.lproj` directories.

The initial catalogs include machine-assisted translations with reviewed navigation and count labels.
Completeness and format checks do not certify linguistic quality; native-speaker corrections to tone,
terminology, and permission instructions are welcome.
