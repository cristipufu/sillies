# Security

Sillies can handle private conversations, screenshots, and writing. Please report security issues
privately so we can investigate without exposing that information.

## Report a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/cristipufu/sillies/security/advisories/new),
or open this repository's **Security** tab and choose **Report a vulnerability**. Private reporting is
enabled for this repository. Do not put exploit details, private recordings, or credentials in a public issue.

Include what you can:

- Sillies' version/build or source commit, macOS version, and Mac chip.
- The affected workflow, such as dictation, Listen, Snap, a model download, or Vault export.
- Reproduction steps and the expected and actual behavior. Use synthetic or redacted examples where possible.
- The likely impact: what could be read, recorded, changed, inserted, or executed without authorization.
- For model issues, the provider, model ID/revision, and whether it was installing, loading, or running.

Keep the discussion in the private advisory. If the reporting page is unavailable, open a public issue
asking only for a private contact route; leave out the vulnerability and sensitive evidence.

## In scope

- Capture starting without an explicit action, continuing after a stop, or bypassing permission controls.
- Exposure of recordings, screenshots, transcripts, writing recovery, or clipboard/selection content.
- Text inserted into the wrong destination, unintended keystrokes, or a command/message sent without consent.
- Path traversal, symlink escapes, unintended overwrites or deletion in model storage, the Vault, or export.
- Model/download tampering, unverified artifacts being activated, or unexpected executable code/network fallback.
- Helper-process boundaries, malformed saved data or model metadata, and update-signature validation.
- A dependency vulnerability that can be reached through a Sillies workflow.

Unexpected text from a model is normally a quality bug. It is a security issue when it crosses a boundary,
such as executing an action, exposing unrelated content, or inserting into an unintended app.

## Supported versions

Sillies is currently under active development. Security fixes target the current `main` branch; no
maintenance branches or older-build support periods are promised. Include the affected commit, and check
the current version if you can do so safely. An issue in an older build is still useful to report.

The repository has release/signing workflows, but that alone does not establish that a downloaded build
is an official, signed, notarized release. Local builds may be ad-hoc signed. Include the build's source
when reporting update or signing issues.

## Handling reports

The maintainer reviews reports in the advisory and may ask for a smaller reproduction. Confirmed fixes
are coordinated there before public disclosure. Reporter credit is offered unless you prefer anonymity.
There is no guaranteed response deadline or paid bounty program.

For ordinary bugs and feature requests, use [the contribution guide](CONTRIBUTING.md). See
[PRIVACY.md](PRIVACY.md) for the current storage, permissions, and network behavior. Local storage is
not an application-encrypted vault; local processing does not protect against someone who already
controls your macOS account. Report an issue in macOS or another app to its vendor, and tell us if
Sillies contributes to the exposure.
