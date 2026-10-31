# Privacy policy

**Sillies for macOS · Last updated October 31, 2026**

Sillies processes your conversations, screenshots, and writing on your Mac. There is no Sillies account,
advertising, in-app analytics, telemetry, or cloud inference fallback. The developer does not receive
your recordings, transcripts, screenshots, selected text, or AI prompts through normal app use.

Local processing does not mean there are no network connections or saved files. This policy describes
the macOS app in this repository, including optional model downloads and updates. It does not cover
GitHub, model-hosting services, or another app into which you insert or export content.

## What the app processes

| Feature | Data used locally |
| --- | --- |
| Window companions | App/window identifiers, titles, geometry, focus and lifecycle events, pointer interactions, and time since input, used to place companions and select reactions. |
| Listen and Participate | Audio from the selected application's output and your microphone, recordings, transcripts, timestamps, optional speaker labels, notes, and suggestions. |
| Record | Microphone audio, a playable recording, transcript, and notes. |
| Snap and Explain | An explicitly selected window image, recognized text, and, for Explain, a local explanation. Snap's text recognition makes saved screenshots searchable. |
| Dictation | Microphone audio during the session, recognized text, optional cleanup, destination information, and a short text recovery history. Dictation does not save an audio recording. |
| Selection commands and insertion | The selected text and bounded focused-field/destination context needed to shorten, correct, translate, or insert text. |
| Pocket Stash and paste-back | Text, links, clipboard items, or file references you explicitly save, plus temporary clipboard contents needed for a requested paste operation. |
| Preferences and dictionary | Companion choices, exclusions, shortcuts, languages, selected models, update settings, and words/replacements you add. |

Ordinary window following does not take screenshots or read document contents. There is no automatic
clipboard-history collection or background recording of what you type. Global shortcuts trigger named
commands; they are not a typing-history feature.

Recording starts only when you choose a capture action. Listen and Participate capture application-wide
audio, which can include other audio-playing tabs in a browser. They also use Sillies' independent
microphone capture: muting your microphone inside a meeting app does not mute Sillies. Paused audio is
discarded. Closing the transcript window keeps the session running; **Finish & Save** stops and saves it.
Use recordings only when you have the appropriate permission from the people involved.

Speaker detection distinguishes voices within a session and audio source. Sillies does not create a
cross-recording voice identity or enrollment profile. Saved speaker labels and names you enter remain
part of the recording's local record.

## Local AI

Apple Speech, Whisper, Parakeet, speaker detection, screenshot text recognition, Apple Intelligence,
and downloaded text models run locally. Audio and text are not sent to Hugging Face or a cloud model
API for inference. Apple's frameworks and system-managed model assets have their own availability and
language requirements. macOS may download those assets through Apple's services.

Model choice does not change where Sillies performs inference. Downloading model files does not upload
your content. Generated notes and edits can be inaccurate; the original transcript is retained for review.

## What is saved, and where

The default application data lives under `~/Library/Application Support/Sillies/`:

| Location | Contents |
| --- | --- |
| `Vault/` | Saved session metadata, recordings, screenshots, transcripts, recognized screenshot text, notes, speaker names, stash items, a local SQLite database containing record bodies, listing metadata, full-text search documents, and an attachment-cleanup journal. Records can include source app/window titles and model revisions. |
| `SpeechModels/` | Downloaded speech/speaker models, installation state, partial downloads/resume information, and model-update metadata. |
| `TextModels/` | Downloaded text models and installation state, including partial downloads. |
| `Dictation/` | The separate text recovery history, including original/result text and destination app labels. |

Preferences, the personal dictionary, exclusions, and shortcuts use macOS preferences under
`app.sillies.macos`. Temporary files and caches may also be created by macOS, download tasks, model
runtimes, or the updater.

These stores are **not encrypted by Sillies** and are not protected by a separate Sillies password.
Your macOS account permissions and any disk encryption you enable apply. Copies in backups, exports,
the clipboard, or other apps are outside Sillies' storage controls. Removing a record is not a promise
of secure erasure from disk or backups.

## Retention and deletion

- **Vault captures** are kept until you delete them by default. You can choose a limit of 200, 500, or
  1,000 unprotected captures. Protected records and Pocket Stash items are exempt from automatic trimming.
  Deleting captures removes their Sillies-owned attachments and updates the search index.
- **Pocket Stash** items remain until you delete them. A saved file reference points to the original file;
  removing the reference does not delete that original.
- **Writing recovery** keeps up to 20 recent results independently of meeting retention. You can remove
  individual results or clear that history. This includes recoverable text when insertion fails.
- **Downloaded models** can be removed in Settings when unused. A speech-model update can retain the
  previous revision for rollback. Paused downloads can retain partial files for resuming.
- **Exports and copies** remain wherever you save or paste them. Deleting the Vault record does not delete
  an exported folder, change another app's document, or clear all copies from the system clipboard.

Uninstalling Sillies alone does not remove all saved data. After quitting, you can remove its application
support folder. This deletes recordings and other retained content, so export anything you want first.
Preferences and OS-managed caches/assets are stored separately. Removing Sillies' files does not remove
Apple's system-managed models or backups of your data.

## Permissions

- **Microphone:** needed for dictation and the microphone input of audio skills.
- **Screen & System Audio Recording:** used for selected-window screenshots and application audio capture;
  the wording and permission controls depend on macOS.
- **Accessibility:** used for explicit selection editing, destination validation, and text insertion. It can
  also improve app/window event observation. Basic companions can follow windows without it.

You control these permissions in **System Settings → Privacy & Security**. Sillies offers buttons to
open the relevant panes. A granted permission does not cause capture to start automatically.

Clipboard-based insertion temporarily preserves the existing clipboard in memory and attempts to restore
it if the user has not changed it during the operation. Sillies does not turn this into a clipboard history.
Other apps and macOS clipboard features may observe content placed on the general pasteboard. Once text
is inserted into a destination app, that app's own storage and network behavior apply.

## When Sillies uses the network

- **Model downloads:** an explicit install, resume, or update requests files from Hugging Face and its
  download/CDN hosts. Requests identify the model, revision, and artifact, and may include byte ranges for
  resuming. The host receives ordinary connection information such as your IP address and request headers.
- **Speech-model update checks:** enabled by default, these check metadata for installed speech/speaker
  models at most once a day while the app is active. You can disable them or check manually in Settings.
  Downloading and activating a new version is explicit. Text-model revisions currently ship with app updates.
- **App updates:** Sparkle can contact the GitHub Releases feed and download hosts. Automatic checks and
  automatic installation have separate settings. Requests can include app/system information and ordinary
  connection metadata; they do not contain your Vault or AI input. Feed availability depends on published releases.
- **Links you open:** opening documentation, a saved URL, or a model page hands the link to your browser
  or another application, which then follows its own privacy behavior.

Sillies does not run a developer-operated inference or synchronization service. GitHub and Hugging Face
handle requests under their own [GitHub privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
and [Hugging Face privacy policy](https://huggingface.co/privacy). Files you export into a cloud-synced
folder can be uploaded by that folder's provider even though Sillies generated them locally.

## Diagnostics and reports you share

Sillies and its dependencies write local diagnostic messages, and macOS can create crash reports.
Sillies does not automatically send these to the developer. System-level diagnostic sharing is controlled
by your macOS settings. Logs can include operational details, app/window names, paths, model identifiers,
or error context; review and redact them before sharing.

If you submit an issue, pull request, or diagnostic attachment, the information you choose to include is
handled by GitHub and can be public. Use the [private security-reporting route](SECURITY.md) for sensitive
security issues. Do not post private recordings or the contents of your Vault to a public issue.

## Questions and changes

For a general privacy question, contact the maintainer through the [Sillies repository](https://github.com/cristipufu/sillies/issues),
without including private content. This policy will be updated when the app's data handling changes.
The source is available in this repository; the policy describes current behavior, not future features.
