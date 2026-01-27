# AGENTS.md

This repository uses CMake + Ninja for native builds and CMake (Android toolchain) for Android builds (Qt 6.10.1).

## Prerequisites

### Common
- CMake
- Ninja
- Qt 6.10.1 installed under `~/Qt/6.10.1/`
- Git (if contributing)
- ImageMagick (`magick`) for regenerating Android launcher icons

### Android
- Android SDK installed at: `~/Android/Sdk`
- Android NDK installed at: `~/Android/Sdk/ndk/28.2.13676358`
- `adb` on PATH (usually via Android SDK platform-tools)
- Qt Android kit installed at: `~/Qt/6.10.1/android_arm64_v8a`
- Qt host tools installed at: `~/Qt/6.10.1/gcc_64`

## Repository Layout Conventions

- Native debug build output: `./build/build-debug/`
- Native test build output: `./build-tests/`
- Android build directory: `./build-android/`
- Android Gradle output APK (expected): `./android-build/build/outputs/apk/debug/android-build-debug.apk`

If your tree differs, update the commands below to match the repo.

---

## Native (Linux) Debug Build (Qt Desktop)

### Configure
```bash
cmake -S . -B ./build/build-debug -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH=~/Qt/6.10.1/gcc_64/lib/cmake -DZINC_BUILD_TESTS=OFF
```

Build
ninja -C ./build/build-debug

Run
`./build/build-debug/bin/zinc`

Test
The default `./build/build-debug/` configure uses `-DZINC_BUILD_TESTS=OFF`, so tests are built in a separate build dir:

```bash
cmake -S . -B ./build-tests -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH=~/Qt/6.10.1/gcc_64/lib/cmake -DZINC_BUILD_TESTS=ON
ninja -C ./build-tests zinc_qml_tests
ctest --test-dir ./build-tests -R zinc_qml_tests --output-on-failure
```

## Native (Windows) Debug Build (Qt Desktop)
cmd.exe:
set PATH=C:\Qt\Tools\mingw1310_64\bin;%PATH%

PowerShell:
$env:Path = "C:\\Qt\\Tools\\mingw1310_64\\bin;" + $env:Path

### Configure
```bash
cmake -S . -B ./build/build-debug -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH=C:\Qt\6.10.1\mingw_64\bin -DQt6_DIR=C:/Qt/6.10.1/mingw_64/lib/cmake/Qt6 -DZINC_BUILD_TESTS=OFF "-DQT_QMAKE_EXECUTABLE:FILEPATH=C:/Qt/6.10.1/mingw_64/bin/qmake.exe" "-DCMAKE_C_COMPILER:FILEPATH=C:/Qt/Tools/mingw1310_64/bin/gcc.exe" "-DCMAKE_CXX_COMPILER:FILEPATH=C:/Qt/Tools/mingw1310_64/bin/g++.exe"
```

Build
```bash
ninja -C ./build/build-debug
"C:\Qt\6.10.1\mingw_64\bin\windeployqt.exe" --qmldir=.\qml .\build\build-debug\bin\zinc.exe

Run
.\build\build-debug\bin\zinc.exe


Headless / CI note:

- If there is no display server available, run QML tests with `QT_QPA_PLATFORM=offscreen`, e.g.
  - `QT_QPA_PLATFORM=offscreen ctest --test-dir ./build-tests -R zinc_qml_tests --output-on-failure`

Notes

If CMake cache gets into a bad state, delete ./build/build-debug/ and re-configure.

If Qt is not found, verify CMAKE_PREFIX_PATH points to the Qt Desktop kit CMake directory.

Android Debug Build (arm64-v8a)

From repo root:

Configure (in build-android/)
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

Build
cmake --build . --parallel

Install APK (Debug)
adb install -r ./android-build/build/outputs/apk/debug/android-build-debug.apk

Notes / Troubleshooting

If adb install fails because adb cannot find a device:

Ensure a device or emulator is running: adb devices

If Qt host tools aren’t found, confirm:

-DQT_HOST_PATH=/home/raleigh/Qt/6.10.1/gcc_64

If Android NDK mismatch errors appear, verify the toolchain file path and NDK version.

Android Launcher Icon Assets

- Canonical icon source (used for desktop + Android generation): `src/assets/icon.png`
- To regenerate Android launcher icons (writes `android/res/mipmap-*/ic_launcher*.png`):

```bash
bash scripts/regenerate_android_launcher_icons.sh
```

- Verify the manifest + icon dimensions:

```bash
ninja -C ./build/build-debug zinc_android_icon_check
```

Clean Builds
Native
rm -rf ./build/build-debug

Android
rm -rf ./build-android


Re-run the configure + build steps after cleaning.

Agent Expectations

Use functional programming principles when possible.

Follow a test driven development pattern, implementing small changes and testing immediately to verify functionality performs as expected.

When changing build files or dependencies:

Keep the commands in this file accurate.

Prefer minimal, reproducible changes (avoid local-only hacks).

If modifying Qt/Android paths, either:

keep /home/raleigh/... as-is (current dev machine), or

parameterize via env vars and update this doc accordingly.
