# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

AGENTS.md (imported above) covers the commands, capture scripts, style, testing, commit and change-scope rules. This file adds the architecture you only see after reading several files.

## Architecture

### Dart ↔ Rust boundary

- `rust/src/api/music.rs` is the only Rust surface Dart calls (via flutter_rust_bridge 2.12.0, configured in `flutter_rust_bridge.yaml`: `rust_input: crate::api`, output `lib/src/rust`). Each function is a thin wrapper around `crate::qq::*`. Shared data types live in `rust/src/api/types.rs`.
- Every API error passes through `api_error()`, which maps it to an `ApiError` code that Dart translates, and calls `client::suspect_session()` when the server rejects auth. New API functions should use the same `.map_err(api_error)` pattern.
- After changing anything in `rust/src/api/`, run `flutter_rust_bridge_codegen generate`. Dart imports the generated code as `src/rust/api/music.dart as api`.
- `rust/src/qq/client.rs` is the single place for the network client, login session (`Session`: uin/musickey/login_type) and request signing (`sign.rs`). `store.rs` is one SQLite DB (`kanade.db` in the app support dir) that holds API response cache, song cache index and key-value prefs, login included.

### Startup and state

- `lib/main.dart` → `initApp()` in `lib/app.dart`: MediaKit, `RustLib.init()`, window setup, `api.initCore(dataDir)`, glass shader warm-up. Integration tests call the same `initApp` with a copied data dir (`integration_test/harness.dart` `initTestApp`) so they never touch the live `kanade.db`.
- State uses `provider` `ChangeNotifier`s wired in `AppProviders`: `LocaleController`, `ThemeController`, `AuthController`, `LibraryController` (liked songs, eager), `PlayerController`. `MediaSession` (SMTC on Windows, `audio_service` on Android) attaches once all of these exist.

### Playback: two implementations behind `PlayerController`

`lib/player/player_controller.dart` is an abstract class with two `part` implementations:

- `_LocalPlayerController` (`local_player_controller.dart`) owns a media_kit `Player`. Windows uses it directly.
- `_RemotePlayerController` (`remote_player_controller.dart`) is used on Android when `KANADE_SEPARATE_ANDROID_PLAYBACK` is set (the default). Playback runs in a separate Flutter engine (`androidPlaybackMain` → `runAndroidPlayback()` in `android_playback_service.dart`), which itself runs a `_LocalPlayerController`. The UI talks to it over a Unix socket (`<dataDir>/playback.sock`) using newline-delimited JSON (`android_playback_connection.dart`, `playback_messages.dart`).
- On Android the UI process calls `api.initUiCore` (DB only) and the playback process calls `api.initCore`. Only the playback process opens the audio cache.
- Playback-facing changes usually touch both sides. Anything the UI needs from the player must go through the message protocol on Android.

### Audio sources and caching

- `AudioSource.resolve` (`lib/player/audio_source.dart`) tries the local cache first, then an online URL, then any cached quality when offline.
- Online audio never reaches media_kit directly. `rust/src/qq/audio_cache.rs` runs a local relay that streams to the player while it writes the whole file to the cache, and evicts least-recently-played songs above the size limit (`pref:audio_cache_limit_mb`, default 1024 MB).
- `rust/src/qq/quality.rs` builds the list of quality tiers for the current account. Special formats (DTS, 360 Reality Audio, NAC) depend on optional platform decoders (`dts.rs`, `ra360.rs`, `nac.rs`), which exist only on Windows x86_64 and Android aarch64; on other targets `available()` returns false. Their C++ sources live in `native/` and are built by `windows/CMakeLists.txt` and `android/app/build.gradle.kts` (via `native/android/CMakeLists.txt`), not by cargo.

### UI

- `lib/ui/home_shell.dart` (mobile) and `desktop_shell.dart` are the app shells. The player is a custom route (`player_route.dart`, `player_page.dart`) that animates out of the mini player / bar.
- Glass effects come from the patched `third_party/liquid_glass_widgets`, wrapped by `lib/ui/glass.dart` (`KanadeGlass`). Use the `liquid-glass-widgets` skill when editing glass UI.
- `ExcludeSemantics(excluding: Platform.isWindows)` in `main.dart` deliberately works around a Flutter Windows accessibility crash. Keep it.
- The ARB template is `lib/l10n/app_zh.arb` (Chinese is the source language). Code comments and docs are mostly in Chinese.

### Patched dependencies (`third_party/`)

- `audio_service`: notification artwork cache capped at 4 MB.
- `smtc_windows`: bindings regenerated with frb 2.12.0 to match the project.
- `liquid_glass_widgets`: arc lens plus Windows background refraction.

## Reference material

- `docs/qqmusic-api.md` maps each upstream QQ Music HTTP/MQTT endpoint to its Rust/Dart entry point. Read it before adding or changing an API call. The `docs/*-capture.md` notes record how each endpoint was captured.
- The repo root holds local `.har` / `.saz` / `.etl` / `.pcapng` captures (gitignored). Use them as reference for request shapes; they contain credentials, so never commit or quote them.
- `rust/tests/live.rs` holds opt-in live smoke tests. They read the login state from the HAR at `QQMUSIC_TEST_HAR` into an in-memory DB.
- Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed (Flutter 3.47.8, Windows zip + Inno Setup installer, Android arm64 APK).
