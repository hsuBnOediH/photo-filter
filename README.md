# PhotoFilter

**[简体中文](README.zh-Hans.md)** · English

A free, open-source, keyboard-first photo cleanup app for macOS. Everything runs on-device — your photos never leave your Mac.

![CI](https://github.com/yukunf/photo-filter/actions/workflows/ci.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

PhotoFilter works directly with your **system Photos library** (the one synced by iCloud), so cleanups land in *Recently Deleted* — recoverable for 30 days — and sync to your iPhone. That's the key difference from folder-based duplicate finders: no exports, no hard deletes, no separate library.

## Modules

| | |
|---|---|
| 📸 **Screenshots** | Flashcard-style review: `←` delete, `→` keep, `↑` undo. Burn through hundreds of stale screenshots in minutes. Progress is saved — quit anytime and resume where you left off. |
| 🖼 **Personal Photos** | Finds groups of similar shots (same time + place, confirmed by a local Vision model), auto-suggests the best one to keep, and walks you through **one group at a time**. Results stream in while the scan runs; stop whenever — everything is cached and resumable. |
| 👥 **Shared Albums** | Browse iCloud Shared Albums and bulk-remove your own posts. |
| 🎬 **Videos** | Coming soon. |

## Highlights

- **Keyboard-first, fully customizable** — every key can be rebound in Settings (⌘,); press `?` anytime for the live cheat sheet.
- **Zoomed triage** — all review keys keep working inside the zoom overlay; press `Enter` to jump groups without leaving full-screen, `Z` for pixel-level pan, `C` for a side-by-side against the suggested keeper.
- **Streaming scans** — similar-photo groups appear seconds after the scan starts, newest first. Review and delete while it's still running.
- **Resumable everything** — scan results, marks, and review progress survive app restarts; computed image fingerprints are disk-cached so rescans are near-instant.
- **Bilingual** — English and 简体中文, following your system language.
- **Safe by design** — nothing is written to your library until you confirm a system deletion dialog; deletions go to *Recently Deleted* (30-day recovery). The app warns you if you use iCloud Shared Library, where deletions affect all members.

## Privacy

- All analysis (Apple Vision feature prints) runs **on-device**. No photo, thumbnail, or metadata is ever uploaded.
- No analytics, no telemetry, no third-party SDKs.
- The only network request the app can make is an optional version check against the GitHub Releases API (toggle it off in Settings).
- Don't trust us? It's all in this repo — build it yourself in two commands.

## Install

1. Download the latest `PhotoFilter-x.y.z.dmg` from [Releases](https://github.com/yukunf/photo-filter/releases).
2. Drag **PhotoFilter** into *Applications*.
3. First launch: macOS will warn that the app is from an unidentified developer (it isn't notarized yet). Either:
   - Right-click the app → **Open** → **Open**, or
   - System Settings → Privacy & Security → scroll down → **Open Anyway**, or
   - `xattr -cr /Applications/PhotoFilter.app` in Terminal.
4. Grant **Full Access** to Photos when prompted (required: the app's whole job is reading and deleting photos).

Requires macOS 14 (Sonoma) or later. Universal binary (Apple Silicon + Intel).

## Build from source

No Xcode required — just the Command Line Tools:

```bash
git clone https://github.com/yukunf/photo-filter.git
cd photo-filter
./build-app.sh            # native arch; add --universal for a fat binary
open PhotoFilter.app      # launch via Finder/open, NOT `swift run` (Photos permission
                          # is keyed to the app bundle, not your terminal)
```

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Good first contributions: new locales, the Videos module, smarter keeper heuristics.

## License

[MIT](LICENSE)
