# CloudNotes 🌥️📝

A native macOS notes app inspired by the classic three-pane Notes layout — sidebar,
notes list, editor — built with SwiftUI, plus three things the original doesn't do:

1. **Cloud auto-sync, zero save buttons.** Every keystroke autosaves (0.5 s debounce)
   to a folder inside **iCloud Drive** (`iCloud Drive/CloudNotes`). iCloud carries the
   files to your other Macs; the app watches the folder and live-merges changes that
   sync in. If iCloud Drive isn't set up, it falls back to `~/Documents/CloudNotes`.
2. **WhatsApp-style timestamps.** New notes start with a `[11 June 2026, 2:20 PM]`
   stamp. Come back to a note after 10+ minutes and a fresh stamp is inserted
   automatically — like a new message bubble. You can also insert one manually
   (clock button or ⇧⌘T).
3. **One-button AI cleanup.** Hit the ✨ button and your rough, fragmented text is
   rewritten into proper, structured notes via the Anthropic API — keeping every
   fact and every timestamp. An undo arrow appears so you can revert instantly.

## Requirements

- macOS 13 Ventura or newer
- Xcode 15+ (or just the Command Line Tools with a recent Swift toolchain)
- An Anthropic API key for the AI button (everything else works without one)

## Run it

```bash
git clone <your-remote-url> CloudNotes
cd CloudNotes
swift run
```

Or open `Package.swift` in Xcode and press **Run**.

First launch: open **Settings (⌘,)**, paste your Anthropic API key
(from https://console.anthropic.com), done.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New note |
| ⇧⌘T | Insert timestamp |
| ⌘, | Settings (API key, model, sync folder) |
| ⌘F (toolbar) | Search notes |

## How sync works

Each note is a small JSON file (`<uuid>.json`) with content, created/updated dates,
and a pre-AI snapshot for revert. Storing notes as plain files in iCloud Drive means:

- no accounts, no server, no manual saving
- sync conflicts resolve by "newest `updatedAt` wins"
- your notes are always readable, greppable, and yours

A `DispatchSource` filesystem monitor watches the folder, so edits synced in from
another Mac appear without relaunching.

## Project layout

```
Sources/CloudNotes/
├── CloudNotesApp.swift      # App entry, menu commands, Settings scene
├── Models/Note.swift        # Note model (title/preview derived from content)
├── Store/NotesStore.swift   # Persistence, autosave, sync merge, folder watcher
├── Services/AIService.swift # Anthropic Messages API client
└── Views/
    ├── ContentView.swift    # Three-pane split view + toolbar + AI action
    ├── NoteListView.swift   # Middle column list with relative dates
    ├── EditorView.swift     # Editor with date header and AI progress overlay
    └── SettingsView.swift   # API key, model, sync folder
```

## Roadmap (v2 ideas)

- Move the API key into the Keychain
- Rich text / markdown rendering with a styled first-line title
- Folders, pinning, attachments
- Menu bar quick-capture window

## License

MIT — do whatever you like, no warranty.
