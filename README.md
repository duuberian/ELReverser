# EL Reverser

An audio reverser and scrambler app. Available for **macOS** and **Android**.

## Download

| Platform | How to Get It |
|----------|--------------|
| **🍎 macOS** | Download the DMG from the [latest release](https://github.com/duuberian/ELReverser/releases/latest) |
| **📱 Android** | Download the APK from the [latest release](https://github.com/duuberian/ELReverser/releases/latest) |

### macOS Installation

1. Download and open the DMG
2. Drag **EL Reverser** into **Applications**
3. **Right-click** the app → **Open** → click **Open** in the dialog
4. After the first launch, it opens normally from now on

> ℹ️ Since the app isn't from the App Store, macOS asks you to confirm on first launch. Right-click → Open bypasses this.

## Features

- **Record** audio directly from microphone
- **Import** audio files (WAV, M4A, MP3, AIFF, OGG)
- **Reverse** audio — full or chunked (split into segments and reverse each chunk independently)
- **Trim** audio with a visual waveform slider
- **Chain operations** — apply multiple reverse/chunk steps to build complex scrambles
- **Scramble codes** — every operation chain generates a copyable code (e.g. `SCR1:R-C0.5-R`) that can be shared and decoded
- **Decode** — paste a scramble code to undo all operations and recover the original audio
- **Drag & drop** support (macOS)
- **Save / Share** processed audio

## Scramble Code Protocol

```
SCR1:R          → full reverse
SCR1:C0.5       → chunked reverse (0.5s)
SCR1:R-C0.5-R   → reverse → chunk → reverse
```

To decode: apply the same operations in reverse order.

## Building from Source

### macOS

```bash
cd macos
swift build
swift run ELReverser
```
Requires macOS 13+, Swift 6.2+ / Xcode 16+.

### Android

```bash
cd android
./gradlew assembleDebug
```
Requires JDK 17 and the Android SDK.

## License

MIT
