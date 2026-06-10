# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-06-10

First public release.

### Added
- **Screenshots module**: flashcard review (delete / keep / undo), pre-commit
  review grid, batch deletion via a single system dialog, resumable progress.
- **Personal Photos module**: streaming scan that buckets photos by capture
  time + GPS, confirms same-scene with on-device Vision feature prints,
  clusters near-duplicates, and suggests one keeper per group. One-group-at-a-
  time review with partial deletes ("delete reviewed"), per-group deletes,
  zoomed triage, pixel zoom, side-by-side compare, and a resumable session
  that survives restarts.
- **Shared Albums module**: browse iCloud Shared Albums and remove your own
  posts with explicit, member-visible-consequence warnings.
- Customizable keyboard shortcuts with click-to-record settings UI.
- Live cheat-sheet overlay (`?`), first-launch onboarding.
- Bilingual UI: English + 简体中文, following the system language.
- Settings window: scan defaults, auto-update toggle, shortcut editor,
  feature-print cache management.
- Update check against GitHub Releases (manual + optional daily).
- Universal binary build script (Apple Silicon + Intel), no Xcode required.
