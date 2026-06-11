# CloudNotes 🌥️📝

A native macOS notes app inspired by the classic three-pane Notes layout — sidebar,
notes list, editor — built with SwiftUI, plus three things the original doesn't do:

1. **Cloud auto-sync, zero save buttons — now with sign-in & real time.** Every
   keystroke autosaves (0.5 s debounce). Two sync modes:
   - **Account mode (recommended):** sign in with email + password in Settings and
     every edit is pushed instantly to the cloud (free Supabase backend) while a
     realtime subscription streams in changes from your other devices, live.
   - **No-account mode:** notes are plain files in `iCloud Drive/CloudNotes`
     (fallback `~/Documents/CloudNotes`); iCloud Drive carries them between Macs
     and the app live-merges changes it sees in the folder.
2. **WhatsApp-style timestamps.** New notes start with a `[11 June 2026, 2:20 PM]`
   stamp. Come back to a note after 10+ minutes and a fresh stamp is inserted
   automatically — like a new message bubble. You can also insert one manually
   (clock button or ⇧⌘T).
3. **One-button AI cleanup — free by default.** Hit the ✨ button and your rough,
   fragmented text is rewritten into proper, structured notes — keeping every fact
   and every timestamp. An undo arrow appears so you can revert instantly.
   By default it uses a **free local model via Ollama** (no API tokens, no account,
   works offline, notes never leave your Mac). The Anthropic API remains available
   as an optional provider in Settings if you ever want a stronger model.

## Requirements

- macOS 13 Ventura or newer
- Xcode 15+ (or just the Command Line Tools with a recent Swift toolchain)
- For the AI button: [Ollama](https://ollama.com) (free) — or optionally an Anthropic API key

## Run it

```bash
git clone <your-remote-url> CloudNotes
cd CloudNotes
swift run
```

Or open `Package.swift` in Xcode and press **Run**.

### Make a double-clickable app

```bash
./scripts/build-app.sh
```

This produces `build/CloudNotes.app` (release build, ad-hoc signed). Drag it into
`/Applications` and launch it like any other Mac app.

### Real-time account sync (one-time backend setup, ~3 minutes, free)

1. Create a free project at https://supabase.com (free tier is plenty).
2. In the project's **SQL Editor**, paste and run `supabase/schema.sql` from this repo.
3. In the app: **Settings (⌘,) → Account**, paste your project URL and anon key
   (Supabase dashboard → Project Settings → API), then **Create Account** / **Sign In**.

From then on the sidebar footer shows your signed-in account, and edits sync across
your Macs the moment you type them. Row-level security in the schema means each
account can only ever read its own notes.

### Free AI setup (one time)

```bash
brew install ollama
ollama pull llama3.2   # ~2 GB, runs great on Apple Silicon
ollama serve           # leave running (or it autostarts as a service)
```

That's it — the ✨ button now works with zero tokens. Prefer a different local
model? Pull it (`ollama pull qwen2.5:7b`) and set the name in **Settings (⌘,)**.
To use the Anthropic API instead, switch the provider in Settings and paste a key.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New note |
| ⌘B / ⌘I / ⌘U | Bold / Italic / Underline |
| ⇧⌘H | Highlight (yellow) |
| ⇧⌘X | Strikethrough |
| ⇧⌘T | Insert timestamp |
| ⌘, | Settings |
| ⌘F (toolbar) | Search notes |

Formatting is real rich text (stored as RTF alongside a plain-text mirror used
for search, sync, and AI). AI cleanup outputs plain text, so formatting resets
on the cleaned note — the revert arrow restores the original.

## Choose your cloud

**Settings → Offline Storage** picks where note files live and auto-sync:

- **iCloud Drive** — default when available
- **Google Drive** — appears automatically when the
  [Google Drive for desktop](https://www.google.com/drive/download/) app is
  installed and signed in; notes go to `My Drive/CloudNotes` and Google syncs them
- **Local only** — `~/Documents/CloudNotes`

Switching copies your notes over instantly; relaunch to finish. Account-based
real-time sync (sign-in) works on top of any of these.

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
├── Services/AIService.swift # AI providers: Ollama (local, free) + Anthropic (optional)
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
