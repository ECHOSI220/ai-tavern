# AI Tavern

A local-first Flutter application for AI role-playing, character chat, and solo or multiplayer tabletop adventures. Desktop and mobile builds are available for Windows x64 and Android arm64.

## Downloads

- [Latest release](https://github.com/ECHOSI220/ai-tavern/releases/latest)
- [Windows x64 ZIP — v1.0.36](https://github.com/ECHOSI220/ai-tavern/releases/download/v1.0.36/ai-tavern-v1.0.36-web-links-windows-x64.zip)
- [Android arm64 APK — v1.0.36](https://github.com/ECHOSI220/ai-tavern/releases/download/v1.0.36/ai-tavern-v1.0.36-web-links-arm64.apk)

For Windows, extract the entire ZIP and run `ai_tavern.exe`; keep its DLLs and `data` directory together. Back up important local saves before upgrading. Release notes include SHA-256 checksums.

[Web community](https://ai-tavern-cloud.pages.dev) · [My creations](https://ai-tavern-cloud.pages.dev/me/uploads)

The application UI and many story templates are currently in Chinese. This repository's overview and release notes are in English; the application has not been translated.

## Features

- Independent local stories, character cards, world books, and persistent memory.
- Streaming chat with a user-configured OpenAI-compatible provider.
- Solo adventures and multiplayer TRPG workflows, including dice and turn handling.
- Optional image understanding and voice features.
- A responsive web community for JSON sharing, discovery, and cover images.
- Desktop and Android shortcuts to the web community and uploaded creations.

## Repository layout

| Directory | Purpose |
| --- | --- |
| `lib/` | Flutter screens, models, repositories, services, and widgets |
| `android/` | Android host and native nearby-connection integrations |
| `windows/` | Windows runner and CMake integration |
| `assets/`, `examples/` | Declared runtime artwork and example story packages |
| `test/` | Flutter unit and widget tests |
| `community/` | TypeScript/Vite community website |
| `server/` | Cloudflare Worker and Durable Objects multiplayer backend |
| `shared/` | Shared protocol schemas and test fixtures |
| `supabase/` | SQL migrations and rollback-only access tests |
| `tool/` | Build and deployment helpers |

## Build the application

Use Flutter with Dart **3.12.2 or newer compatible SDK**, JDK 17, and the Android SDK for Android builds. Windows builds require Visual Studio's C++ desktop build tools and a Windows SDK.

```sh
flutter pub get
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release --target-platform android-arm64
```

Flutter regenerates platform wrappers and plugin registration during setup. The public source uses the default SQLite native build hook instead of the original developer machine's prebuilt library path. Native voice libraries are resolved through the pinned package dependencies.

Cloud functionality requires your own backend configuration. Pass public configuration with `--dart-define=APP_ENV=production`, `--dart-define=GAME_SERVER_URL=...`, `--dart-define=SUPABASE_URL=...`, and `--dart-define=SUPABASE_ANON_KEY=...`. Never put an admin/service-role key in an application build.

The Android build configuration currently uses a debug signing key for sideloading. Configure your own signing key before store distribution; signing keys are not included.

## Web community and backend

Use Node.js 24+ and pnpm. See [community setup](community/README.md) and [backend setup](server/README.md).

```sh
cd community
pnpm install --frozen-lockfile
# Copy .env.example to .env.local and provide your public configuration.
pnpm dev
pnpm test
pnpm build
```

The backend uses Cloudflare Workers/Durable Objects and Supabase. The included migrations capture this project's changes, not a fully verified one-command bootstrap of every pre-existing database object. Review schema prerequisites and test on a development project before deployment. Cloud integration and real-device multiplayer acceptance remain separate from local unit tests.

## Publication scope

This repository contains a curated source snapshot of v1.0.36, runtime assets, tests, and framework configuration. Production secrets, signing material, local saves, chat histories, build caches, and development logs are excluded. Existing downloadable binaries are unchanged by documentation and source publication.

No new license grant is made by this upload. Dependency licenses remain applicable; check asset and project permissions before redistribution.
