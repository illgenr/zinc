# AGENTS.md

This repository uses CMake + Ninja for native builds and CMake (Android toolchain) for Android builds (Qt 6.10.1).

## Prerequisites

### Common
- CMake
- Ninja
- Qt 6.10.1 installed under `~/Qt/6.10.1/`
- Git (if contributing)

### Android
- Android SDK installed at: `~/Android/Sdk`
- Android NDK installed at: `~/Android/Sdk/ndk/28.2.13676358`
- `adb` on PATH (usually via Android SDK platform-tools)
- Qt Android kit installed at: `~/Qt/6.10.1/android_arm64_v8a`
- Qt host tools installed at: `~/Qt/6.10.1/gcc_64`

## Repository Layout Conventions

- Native debug build output: `./build/build-debug/`
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

Test
cmake --build build --target zinc_qml_tests
ctest -R zinc_qml_tests --output-on-failure

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