# AI Tavern

[中文](README.md) · **English**

AI Tavern is a local-first Flutter application for AI role-playing, character chat, and solo or multiplayer tabletop adventures. Windows x64 and Android arm64 builds are provided.


## v1.1.1 highlights · September 14, 2026

Character social-life preview and streaming bubble fixes; 369 automated tests pass. Memory extraction no longer delays completed replies.

Full Phase 10 and physical two-device acceptance remain incomplete.

See [implementation report](CHARACTER_SOCIAL_LIFE_REPORT.md) and [display fix](SOCIAL_CHAT_DISPLAY_FIX_1.1.1.md).

## Downloads

- [Latest release](https://github.com/ECHOSI220/ai-tavern/releases/latest)
- [Web community](https://ai-tavern-cloud.pages.dev)
- [My creations](https://ai-tavern-cloud.pages.dev/me/uploads)
- [Baidu Netdisk downloads](https://pan.baidu.com/s/52ffw3X-MMLAoWp3TDZNVTg)
- [Open-source web client](https://github.com/ECHOSI220/ai-tavern/tree/main/community)

For Windows, extract the entire ZIP and run `ai_tavern.exe`; keep its DLLs and `data` directory together. For Android, install the arm64 APK. Back up local saves before upgrading.

## v1.0.39 highlights

- Fixed multiplayer settlement failures caused by missing system proxy routing and DNS lookup failures.
- Added Windows system-proxy detection and Android system `ProxySelector` integration.
- Preserved DeepSeek reasoning context across tool-call rounds and kept tool results during retries.
- Added bounded timeouts, duplicate/late-response protection, host recovery, and safe diagnostic logs.
- The multiplayer path was verified against a real OpenAI-compatible API with a tool-call round trip.

## Features

- Independent local stories, character cards, world books, and persistent memory.
- Streaming chat with a user-configured OpenAI-compatible provider.
- Solo adventures and multiplayer TRPG workflows with dice, turns, and authoritative server rules.
- Optional image understanding and voice features.
- A responsive web community for JSON sharing, discovery, and cover images.
- Windows and Android shortcuts to the web community and uploaded creations.

## Repository layout

| Directory| Purpose|
| --- | --- |
| `lib/` | Flutter screens, models, repositories, services, and widgets|
| `android/` | Android host and native integrations|
| `windows/` | Windows runner and CMake integration|
| `assets/`, `examples/` | Declared runtime artwork and examples|
| `test/` | Flutter tests|
| `community/` | TypeScript/Vite community website|
| `server/` | Cloudflare Worker and Durable Objects backend|
| `shared/` | Shared protocol schemas and fixtures|
| `supabase/` | SQL migrations and access tests|
| `tool/` | Build, deployment, and diagnostic helpers|

## Build

Use Flutter with Dart **3.12.2 or newer compatible SDK**, JDK 17, and the Android SDK. Windows builds require Visual Studio C++ desktop build tools and a Windows SDK.

```sh
flutter pub get
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release --target-platform android-arm64
```

Cloud features require your own backend configuration. Never put an admin/service-role key in an application build.

The Android sideload build uses a debug signing configuration. Configure your own signing key before store distribution.

## Security and publication scope

This repository is a curated source snapshot. Production secrets, signing material, local saves, chat histories, build caches, and development logs are excluded. The app stores API keys locally and diagnostic logs redact keys, prompts, message bodies, and authorization data.

Review the included Cloudflare/Supabase configuration and test on your own development project before deployment.

No new license grant is made by this upload. Dependency and asset licenses remain applicable.
