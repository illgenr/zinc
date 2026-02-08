# Zinc Notes

Zinc is a Qt Quick (QML) note app with a C++ backend.  
It supports local-first note editing, SQLite persistence, and peer sync.

For a deeper system map, see `architecture.md`.

## Prerequisites

### Common
- CMake
- Ninja
- Qt 6.10.1 installed under `~/Qt/6.10.1/`
- Git (if contributing)
- ImageMagick (`magick`) for regenerating Android launcher icons

### Android
- Android SDK at `~/Android/Sdk`
- Android NDK at `~/Android/Sdk/ndk/28.2.13676358`
- `adb` on `PATH`
- Qt Android kit at `~/Qt/6.10.1/android_arm64_v8a`
- Qt host tools at `~/Qt/6.10.1/gcc_64`

## Build And Run (Linux Desktop)

Configure:

```bash
cmake -S . -B ./build/build-debug -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PREFIX_PATH=~/Qt/6.10.1/gcc_64/lib/cmake \
  -DZINC_BUILD_TESTS=OFF
```

Build:

```bash
ninja -C ./build/build-debug
```

Run:

```bash
./build/build-debug/bin/zinc
```

## Run Tests

Configure test build:

```bash
cmake -S . -B ./build-tests -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PREFIX_PATH=~/Qt/6.10.1/gcc_64/lib/cmake \
  -DZINC_BUILD_TESTS=ON
```

Build tests:

```bash
ninja -C ./build-tests zinc_tests zinc_property_tests zinc_integration_tests zinc_qml_tests
```

Run tests:

```bash
ctest --test-dir ./build-tests --output-on-failure
```

Headless CI / no display:

```bash
QT_QPA_PLATFORM=offscreen ctest --test-dir ./build-tests --output-on-failure
```

## Using The App

1. Launch `zinc`.
2. Use the page tree to create/select notes.
3. Edit note content in the editor; changes autosave to SQLite.
4. Open Settings for sync, startup, editor, import/export, and device pairing.

Default pages are seeded on a fresh database (for example, `Getting Started`).

## CLI Commands

The same `zinc` binary supports CLI operations:

```bash
zinc list [--ids] [--json]
zinc note --id <pageId> [--html]
zinc note --name "<exact title>" [--html]
zinc notebook-create --name "<name>" [--json]
zinc notebook-delete --id <notebookId> [--delete-pages] [--json]
zinc page-create --title "<title>" [--notebook <notebookId> | --loose | --parent <pageId>] [--json]
zinc page-delete --id <pageId> [--json]
```

Global options:

- `--db <path>`: override database path for this run (sets `ZINC_DB_PATH`)
- `--debug-attachments`
- `--debug-sync`
- `--debug-search-ui`
- `--debug-sync-ui`

## Data And Logs

- Database default: Qt `AppDataLocation` + `zinc.db`
- Attachments default: `<database_folder>/attachments`
- Log file: Qt `AppLocalDataLocation` + `logs/zinc.log`

Useful env vars:

- `ZINC_DB_PATH` (override DB path)
- `ZINC_ATTACHMENTS_DIR` (override attachments directory)
- `ZINC_DEBUG_ATTACHMENTS`
- `ZINC_DEBUG_SYNC`
- `ZINC_DEBUG_SYNC_CONFLICTS`
- `ZINC_DEBUG_SEARCH_UI`
- `ZINC_DEBUG_SYNC_UI`

## Android Build (arm64-v8a)

From repo root:

```bash
cd build-android

cmake \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PREFIX_PATH="/home/raleigh/Qt/6.10.1/android_arm64_v8a" \
  -DCMAKE_FIND_ROOT_PATH="/home/raleigh/Qt/6.10.1/android_arm64_v8a" \
  -DQT_HOST_PATH=/home/raleigh/Qt/6.10.1/gcc_64 \
  -DANDROID_SDK_ROOT=/home/raleigh/Android/Sdk \
  -DANDROID_NDK=/home/raleigh/Android/Sdk/ndk/28.2.13676358 \
  -DQT_ANDROID_ABIS="arm64-v8a" \
  -DCMAKE_TOOLCHAIN_FILE=/home/raleigh/Android/Sdk/ndk/28.2.13676358/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  ..

cmake --build . --parallel
adb install -r ./android-build/build/outputs/apk/debug/android-build-debug.apk
```

## Maintenance Commands

Regenerate Android launcher icons:

```bash
bash scripts/regenerate_android_launcher_icons.sh
```

Verify Android icon resources:

```bash
ninja -C ./build/build-debug zinc_android_icon_check
```
