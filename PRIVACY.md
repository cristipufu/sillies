# Privacy policy

**Sillies for macOS · Last updated November 13, 2026**

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
| Chat | Messages you type, microphone audio after choosing Talk, recognized words, local replies, and synthesized speech. Each companion has a continuous, locally saved conversation. Chat can search earlier messages and your Vault/Stash locally. You can explicitly select Vault items and pin shared or companion-specific facts. Bounded context summaries and model-written memories are stored separately; model-written facts show a memory chip with Undo and can be reviewed or forgotten. Closing the bubble saves the draft and selected item references. Chat does not save microphone recordings or generated audio. |
| Snap and Explain | An explicitly selected window image, recognized text, and, for Explain, a local explanation. Snap's text recognition makes saved screenshots searchable. |
| Dictation | Microphone audio during the session, recognized text, optional cleanup, destination information, and a short text recovery history. Dictation does not save an audio recording. |
| Selection commands and insertion | The selected text and bounded focused-field/destination context needed to shorten, correct, translate, or insert text. |
| Pocket Stash and paste-back | Text, links, clipboard items, or file references you explicitly save, plus temporary clipboard contents needed for a requested paste operation. |
| Vault notes and saved links | Notes, titles, tags, collections, saved searches, editing drafts, corrected transcripts and link previews. Explicitly saving a URL requests preview metadata from that website and, for supported posts/videos, its public preview service. |
| Preferences and dictionary | Companion choices, exclusions, shortcuts, languages, selected models, update settings, and words/replacements you add. |

Ordinary window following does not take screenshots or read document contents. There is no automatic
clipboard-history collection or background recording of what you type. Global shortcuts trigger named
commands; they are not a typing-history feature.

Recording starts only when you choose a capture action. Listen and Participate capture application-wide
audio, which can include other audio-playing tabs in a browser. They also use Sillies' independent
microphone capture: muting your microphone inside a meeting app does not mute Sillies. Paused audio is
discarded. Closing the transcript window keeps the session running; **Finish & Save** stops and saves it.
Listen and Participate prefer a native Core Audio tap scoped to the selected application's verified
processes. Unsupported startup configurations can use ScreenCaptureKit instead. macOS may request
system-audio or screen-recording access for the selected provider. Silence and permission errors do not
cause a provider switch. The audio tap is stopped while paused and recreated when recording resumes.
Use recordings only when you have the appropriate permission from the people involved.

Speaker detection distinguishes voices within a session and audio source. Sillies does not create a
cross-recording voice identity or enrollment profile. Saved speaker labels and names you enter remain
part of the recording's local record.

While Listen or Participate is recording, Sillies can read participant names and speaking indicators
from the selected call window through macOS Accessibility. Separate adapters recognize Zoom, Teams,
and Google Meet metadata. Names are attached only when the available evidence meets the attribution
rules; missing or ambiguous evidence leaves anonymous labels. These reads stop when capture pauses
or ends. Names and corrections are saved with the recording; call-window trees and participant names
are never written to the diagnostics archive.

## Local AI

Apple Speech, Whisper, Parakeet, speaker detection, screenshot text recognition, Apple Intelligence,
downloaded text models, and optional voice synthesis run locally. Audio and text are not sent to Hugging Face or a cloud model
API for inference. Apple's frameworks and system-managed model assets have their own availability and
language requirements. macOS may download those assets through Apple's services.

Model choice does not change where Sillies performs inference. Downloading model files does not upload
your content. Generated notes and edits can be inaccurate; the original transcript is retained for review.

## What is saved, and where

The default application data lives under `~/Library/Application Support/Sillies/`:

| Location | Contents |
| --- | --- |
| `Vault/` | Saved session metadata, recordings, screenshots, transcripts, recognized screenshot text, notes, speaker names, stash items, a separate `conversations.sqlite` containing per-companion messages, drafts, search indexes, context summaries and personal memories with source quotes and recent Undo payloads; a local SQLite database containing record bodies, listing metadata, full-text search documents, editable content blocks, revision-checked drafts, Trash, link previews, and an attachment-cleanup journal. `VectorIndexes/` contains derived native search caches; canonical vectors remain in SQLite. Records can include source app/window titles and model revisions. |
| `SpeechModels/` | Downloaded speech/speaker models, installation state, partial downloads/resume information, and model-update metadata. |
| `TextModels/` | Downloaded text models and installation state, including partial downloads. |
| `SearchModels/` | Optional downloaded embedding models, installation state and partial downloads. Memory search vectors are derived locally in the conversation database and invalidated when the corresponding memory changes or is deleted. |
| `VoiceModels/` | Downloaded voice models, codecs, supplied voices, installation state, and partial downloads. |
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
  1,000 unprotected captures. Protected/starred records, authored notes, saved links and Pocket Stash items are exempt from automatic trimming.
  Moving an item to Trash hides it from normal browsing and assistant retrieval; its files remain until permanent deletion. Permanent deletion removes Sillies-owned attachments and invalidates search entries. Automatic retention permanently removes eligible captures; it is an explicit preference.
- **Pocket Stash** items remain until you delete them. A saved file reference points to the original file;
  removing the reference does not delete that original.
- **Writing recovery** keeps up to 20 recent results independently of meeting retention. You can remove
  individual results or clear that history. This includes recoverable text when insertion fails.
- **Conversation messages and learned memories** have separate deletion controls in Chat → Memories →
  Manage. Deleting messages retains learned memories and their source quotes unless you choose to delete
  both. Forgetting learned memories retains original messages, which remain searchable. Context summaries
  and affected derived search data are invalidated. Companion preferences and user-pinned facts remain.
- **Pinned facts** are manually authored and remain until you edit or unpin them. Shared facts are
  available to every companion; companion-specific facts apply only to that companion. Models cannot
  modify these facts. They live locally in the conversation database.
- **Selected Vault context** stores up to three record references with the conversation. Removing a chip
  stops its automatic inclusion in future requests; earlier messages may still quote it, and ordinary
  Vault search remains available. Deleting the Vault item makes that reference unavailable.
- **Downloaded models** can be removed in Settings when unused. A speech-model update can retain the
  previous revision for rollback. Paused downloads can retain partial files for resuming.
- **Vault backups** include captures, authored documents, drafts, organization and Trash, plus referenced attachments. Companion conversations are stored separately and have their own export controls. Downloaded models and disposable native search caches are excluded. Backup copies remain until you remove them. Preparing a restore creates a local staging copy. Restoration happens on the next app launch and preserves the previous Vault in a separate recovery folder; it does not replace companion conversations or downloaded models. These recovery copies also remain until you remove them.
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
- **Saved-link previews:** explicitly saving or refreshing a URL fetches metadata and possibly an image from its website using Apple Link Presentation. Supported X posts and YouTube videos also use their public preview endpoints. These services receive the saved URL, IP address and ordinary request metadata. Notes, transcripts and AI prompts are not included. A failed preview does not prevent saving the URL. Sillies does not embed remote scripts or download video transcripts.
- **Links you open:** opening documentation, a saved URL, or a model page hands the link to your browser
  or another application, which then follows its own privacy behavior.

Sillies does not run a developer-operated inference or synchronization service. GitHub and Hugging Face
handle requests under their own [GitHub privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
and [Hugging Face privacy policy](https://huggingface.co/privacy). Files you export into a cloud-synced
folder can be uploaded by that folder's provider even though Sillies generated them locally.

## Diagnostics and reports you share

Sillies keeps a small local diagnostic archive by default. Settings → General → Diagnostics lets you
turn it off, clear it, or export a JSON report. Events include app/build and macOS versions, memory
capacity, model/provider identifiers, operation IDs, lifecycle changes, cancellation causes, timing
milestones and error identities. The archive does not contain messages, prompts, model replies,
audio, Vault content, clipboard data, window titles or user file paths.

The archive lives in `~/Library/Logs/Sillies/Diagnostics`. Four rolling files retain at most 8 MB;
an additional bounded file used for atomic pruning keeps peak archive storage within **10 MB**.
Entries older than **7 days** are pruned on startup, writes and export. Capacity limits may remove
events sooner. The pending queue is also bounded; dropped events are disclosed. Exports are capped
at 10 MB. Copies you explicitly export are yours to keep or delete and are not removed by Clear diagnostics.

Content-free error events are also sent to Apple's unified logging system, whose retention macOS
manages separately. Other system/dependency logs and macOS crash reports can include broader error
context; they are not included in Sillies' export. Sillies does not automatically send diagnostics
to the developer. System-level diagnostic sharing is controlled by your macOS settings.

If you submit an issue, pull request, or diagnostic attachment, the information you choose to include is
handled by GitHub and can be public. Use the [private security-reporting route](SECURITY.md) for sensitive
security issues. Do not post private recordings or the contents of your Vault to a public issue.

## Questions and changes

For a general privacy question, contact the maintainer through the [Sillies repository](https://github.com/cristipufu/sillies/issues),
without including private content. This policy will be updated when the app's data handling changes.
The source is available in this repository; the policy describes current behavior, not future features.
