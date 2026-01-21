# Zinc Notes – Architecture (LLM-oriented)

This document is a high-signal map of the project so an LLM (or a new engineer) can quickly find the right files to change for UI, editor, persistence, and sync behavior.

## Big Picture

Zinc is a Qt Quick (QML) note app with a C++ backend. The UI lives in QML; persistence and sync live primarily in `src/ui` and `src/network`.

At runtime:

- `src/main.cpp` starts `QQmlApplicationEngine` and loads QML `zinc/Main` (`qml/Main.qml`).
- QML talks to C++ via registered QML types/singletons (`src/ui/qml_types.cpp`).
- The note “document” is stored per-page as a single markdown string in SQLite (`DataStore.savePageContentMarkdown`).
- Sync is a snapshot-based JSON protocol over a secure TCP connection (`network::SyncManager`), orchestrated by QML (`qml/Main.qml`).

## Build & Targets (CMake)

Top-level build config: `CMakeLists.txt`.

Main libraries:

- `zinc_core` (`src/core/*`): pure-ish business logic and utilities (e.g., merge, commands, fractional index).
- `zinc_storage` (`src/storage/*`): low-level SQLite wrapper + migrations (not the same as the UI datastore).
- `zinc_crypto` (`src/crypto/*`): keys, Noise sessions, encryption helpers.
- `zinc_network` (`src/network/*`): discovery, transport, sync manager.
- `zinc_ui` (`src/ui/*`): QML bridge layer (DataStore, controllers, models, QML helpers).

Executables:

- `appzinc` (desktop binary named `zinc`): QML app (`src/main.cpp`) + QML module (`qt_add_qml_module`).
- `zinc_qml_tests`: Catch2 host that loads the same QML module offscreen.

Key feature flags:

- `ZINC_ENABLE_QR`: includes QR pairing QML + ZXing.
- `ZINC_USE_SQLCIPHER`: optional SQLCipher support (mostly for `src/storage`, not the QML datastore).

## Module Map (Where to Look)

### QML UI (`qml/`)

Entry point:

- `qml/Main.qml`: the application shell, wiring of dialogs, editor, sync orchestration, and snapshot send/receive.

Core UI components:

- `qml/components/BlockEditor.qml`: the note editor (block list, autosave, cursor movement signals, remote refresh behavior).
- `qml/components/Block.qml`: wrapper for a single block; hosts the remote-cursor indicator and connects to per-block `TextEdit`.
- `qml/components/blocks/*.qml`: block implementations (`ParagraphBlock.qml`, `TodoBlock.qml`, etc).
- `qml/components/PageTree.qml`: page list/navigation.

Dialogs:

- `qml/dialogs/SettingsDialog.qml`: settings pages (Sync settings, Data, etc).
- `qml/dialogs/PairingDialog.qml`: device pairing / connect workflow.
- `qml/dialogs/SyncConflictDialog.qml`: conflict resolution UI.

Preferences (QML singletons):

- `qml/theme/ThemeManager.qml`: theme + font scale persistence (Qt `Settings`).
- `qml/sync/SyncPreferences.qml`: sync preferences (currently `autoSyncEnabled`).

Reusable header buttons:

- `qml/components/SyncButtons.qml`: settings button + conditional manual sync.

### QML ↔ C++ bridge (`src/ui/`)

Registration:

- `src/ui/qml_types.cpp`: registers QML singletons/types under modules `zinc` and `Zinc 1.0`.

Persistence / state:

- `src/ui/DataStore.hpp`, `src/ui/DataStore.cpp`: the canonical app datastore (SQLite via `QSqlDatabase`).
  - Stores pages, notebooks, attachments, paired devices, and sync conflict state.
  - Exposes invokables/signals used by QML (e.g., `pagesChanged`, `pageContentChanged`, `applyPageUpdates`).

Controllers:

- `src/ui/controllers/SyncController.*`: QML-facing sync façade; wraps `network::SyncManager`, parses snapshots, emits QML-friendly signals; handles presence/cursor state.
- `src/ui/controllers/PairingController.*`: pairing logic (used by pairing dialogs).
- `src/ui/controllers/EditorController.*`: editor-related helpers (where present).
- `src/ui/controllers/sync_presence.*`: presence payload serialize/parse (cursor + auto-sync flag).

Models (QML-friendly list models):

- `src/ui/models/PageTreeModel.*`, `BlockModel.*`, `SearchResultModel.*`

Markdown helpers:

- `src/ui/MarkdownBlocks.*`: parse/serialize block lists to markdown.
- `src/ui/Cmark.*`: markdown → HTML rendering.

Attachments:

- `src/ui/AttachmentImageProvider.*`: `image://attachments/<id>` provider.

### Network & Sync (`src/network/`)

Transport:

- `src/network/transport.*`: framed message transport + Noise handshake.
  - Message types include `PagesSnapshot` and `PresenceUpdate` (cursor/presence).

Sync management:

- `src/network/sync_manager.*`: manages discovery, connections, broadcast of page snapshots, and presence updates.

Discovery:

- `src/network/discovery.*`, `udp_discovery_backend.*`: peer discovery (mDNS/Avahi when available, or UDP backend).

Pairing protocol:

- `src/network/pairing.*`: pairing message handling.

### Core logic (`src/core/`, `src/crdt/`)

Merge logic:

- `src/core/three_way_merge.*`: used by `DataStore` conflict detection/resolution.

Other utilities:

- fractional index, commands, etc.

CRDT:

- `src/crdt/*` exists but the current app-level sync flow is snapshot-based through `DataStore` + `PagesSnapshot` messages (not incremental CRDT replication).

### Storage library (`src/storage/`)

There is a separate low-level SQLite wrapper + migrations here (`storage::Database`, `storage/migrations.hpp`).

Important: the shipped app datastore used by QML is `src/ui/DataStore.cpp` (Qt SQL), not `src/storage/*`.

## Key Runtime Data Flows

### 1) Editing → Persisting a Page

1. QML `BlockEditor` maintains an in-memory `ListModel` of blocks (`qml/components/BlockEditor.qml`).
2. On edit, block content updates call `scheduleAutosave()` which:
   - marks the editor `dirty`
   - debounces saves via timers (faster in realtime mode)
3. `saveBlocks()` serializes blocks to markdown via `MarkdownBlocks.serializeContent(...)` and calls:
   - `DataStore.savePageContentMarkdown(pageId, markdown)`
4. `DataStore` writes `pages.content_markdown`, bumps `updated_at`, and emits `pageContentChanged(pageId)`.

Relevant files:

- `qml/components/BlockEditor.qml`
- `src/ui/MarkdownBlocks.cpp`
- `src/ui/DataStore.cpp` (`savePageContentMarkdown`)

### 2) Persisted Changes → Snapshot Sync Outbound

The app currently syncs by sending “deltas since cursor” from the local DB:

1. `BlockEditor` emits `contentSaved(pageId)` after a successful save.
2. `qml/Main.qml` listens and calls `scheduleOutgoingSnapshot()`.
3. On timer fire, `sendLocalSnapshot(full=false)` collects deltas via `DataStore.get*ForSyncSince(...)` and sends JSON to:
   - `SyncController.sendPageSnapshot(payload)`
4. `SyncController` forwards bytes into `network::SyncManager::sendPageSnapshot(...)`, broadcasting to connected peers.

Relevant files:

- `qml/Main.qml` (`scheduleOutgoingSnapshot`, `sendLocalSnapshot`)
- `src/ui/DataStore.cpp` (`getPagesForSyncSince`, `getAttachmentsForSyncSince`, etc.)
- `src/ui/controllers/SyncController.cpp`
- `src/network/sync_manager.cpp`

### 3) Snapshot Sync Inbound → Applying to Local DB → Updating UI

1. Remote `PagesSnapshot` arrives in `network::SyncManager`, emitted to `SyncController`.
2. `SyncController` parses JSON and emits typed signals:
   - `pageSnapshotReceivedPages(...)`, `attachmentSnapshotReceivedAttachments(...)`, etc.
3. `qml/Main.qml` receives those and applies to the DB:
   - `DataStore.applyPageUpdates(pages)` etc.
4. `DataStore` writes new rows, emits:
   - `pagesChanged`
   - `pageContentChanged(pageId)` for content-bearing page updates
5. `BlockEditor` listens to `pageContentChanged` and merges/reloads current page content from DB.

Relevant files:

- `src/network/sync_manager.cpp` (message receive)
- `src/ui/controllers/SyncController.cpp` (parse + signals)
- `qml/Main.qml` (apply incoming)
- `src/ui/DataStore.cpp` (apply updates)
- `qml/components/BlockEditor.qml` (merge from storage)

### 4) Presence / Remote Cursor

1. `qml/components/Block.qml` emits `cursorMoved(cursorPos)` when its `TextEdit` cursor changes.
2. `BlockEditor` forwards this as `cursorMoved(blockIndex, cursorPos)`.
3. `Main.qml` throttles and calls `SyncController.sendPresence(pageId, blockIndex, cursorPos, autoSyncEnabled)`.
4. `SyncController` stores remote presence and exposes:
   - `remoteAutoSyncEnabled`, `remoteCursor*` properties.
5. `Block.qml` renders the remote cursor indicator using `ThemeManager.remoteCursor`.

Relevant files:

- `qml/components/Block.qml`
- `qml/components/BlockEditor.qml`
- `qml/Main.qml`
- `src/ui/controllers/SyncController.*`
- `src/network/transport.hpp` (`PresenceUpdate`)

### 5) Conflict Detection & Resolution

Conflict logic lives in `DataStore.applyPageUpdates`:

- Tracks a “base” (`last_synced_*`) and detects when both local and remote diverged since the last sync base.
- Stores conflict rows in `page_conflicts`.
- Emits `pageConflictDetected(...)` which shows `qml/dialogs/SyncConflictDialog.qml`.
- Uses `src/core/three_way_merge.*` for merge preview/resolution.

Relevant files:

- `src/ui/DataStore.cpp` (`applyPageUpdates`, conflict table)
- `src/core/three_way_merge.*`
- `qml/dialogs/SyncConflictDialog.qml`

## Settings & Preferences

QML preference singletons:

- Appearance: `qml/theme/ThemeManager.qml`
- Sync: `qml/sync/SyncPreferences.qml`

Settings UI:

- `qml/dialogs/SettingsDialog.qml`

If you’re adding settings:

- Add a persisted property to the appropriate QML singleton (`ThemeManager` or `SyncPreferences`)
- Wire it into `SettingsDialog.qml`
- Use it in `Main.qml` / components to gate behavior

## Debugging & Diagnostics

Runtime flags:

- `--debug-sync`: sets `ZINC_DEBUG_SYNC=1` (C++ sync logging) (`src/main.cpp`)
- `--debug-sync-ui`: enables high-level QML sync logs (used in `qml/Main.qml` and `qml/components/BlockEditor.qml`)
- `--debug-attachments`: enables attachment debug logging

Environment variables:

- `ZINC_DB_PATH`: override SQLite file path (used by `DataStore`)
- `ZINC_ATTACHMENTS_DIR`: override attachment directory
- `ZINC_SYNC_DISABLE_DISCOVERY`: disables discovery (sync server still starts)
- `ZINC_DEBUG_SYNC`: enables verbose sync logs in C++

## Tests (Catch2 + QML)

Test layout:

- `tests/unit/*`: core/unit tests
- `tests/integration/*`: integration tests (including sync)
- `tests/qml/*`: offscreen QML tests (loads the same QML module as the app)

To add a UI behavior regression test, prefer `tests/qml/*` if it can be asserted without full UI automation.

## “Where do I change X?”

- **Editor behavior / cursor / focus:** `qml/components/BlockEditor.qml`, `qml/components/Block.qml`, `qml/components/blocks/*`
- **Autosave timing / realtime writes:** `qml/components/BlockEditor.qml` (timers + `saveBlocks`), `src/ui/DataStore.cpp` (no-op save, timestamps)
- **Sync payload contents / scheduling:** `qml/Main.qml` (`sendLocalSnapshot`, `scheduleOutgoingSnapshot`, suppression logic)
- **Sync transport/protocol:** `src/network/transport.hpp` (message types), `src/network/sync_manager.*`
- **JSON snapshot parsing / signals:** `src/ui/controllers/SyncController.cpp`
- **Conflict behavior:** `src/ui/DataStore.cpp` (conflict detection), `qml/dialogs/SyncConflictDialog.qml`
- **Settings UI:** `qml/dialogs/SettingsDialog.qml`, `qml/sync/SyncPreferences.qml`
- **QML registration / exposing C++ to QML:** `src/ui/qml_types.cpp`