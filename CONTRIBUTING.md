# Contributing to PhotoFilter

Thanks for helping! A few ground rules keep the project easy to build and review.

## Building

Command Line Tools only — **no Xcode needed**:

```bash
./build-app.sh        # debug-friendly native build
open PhotoFilter.app  # always launch the bundle; `swift run` won't get Photos permission
```

The app must be launched via the assembled `.app` bundle because macOS ties the
Photos (TCC) permission to the bundle identifier `com.yukunf.photofilter` —
running the bare binary attributes the permission prompt to your terminal.

## Rules

1. **Zero warnings.** `swift build -c release` must compile clean; CI greps for
   `warning:` and fails the build.
2. **Every user-facing string is localized.** Add the key to BOTH
   `Sources/PhotoFilter/Resources/en.lproj/Localizable.strings` and
   `zh-Hans.lproj/Localizable.strings`, then use `L("your.key")` in code.
   `Scripts/check-l10n.sh` enforces key parity in CI.
   Key naming: `<module>.<area>.<name>`; shared strings go under `common.*`.
   (Known simplification: plain format strings, no `.stringsdict` plural rules.)
3. **No new dependencies** without prior discussion in an issue — the project
   deliberately builds with nothing but Apple frameworks.
4. **PhotoKit writes need a confirmation path.** Anything that deletes or
   removes user content must go through a user-visible confirmation and be
   documented in the UI copy.
5. Match the house style: completion handlers + `Task { @MainActor in }` hops
   (the package intentionally stays in Swift 5 language mode), guard-heavy
   optionals, `///` doc comments that explain *why*.

## Good first contributions

- New locales (copy `en.lproj`, translate, add to `CFBundleLocalizations` in
  `build-app.sh`).
- The Videos module (the home-screen card is already there, disabled).
- Smarter keeper heuristics (sharpness via Laplacian variance on the 300 px
  thumbs — the hook is described in `AssetGrouper.recommendKeeper`).
- A Sparkle-based auto-updater once Developer ID signing lands (see the note
  in `UpdateChecker.swift`).

## Releasing (maintainers)

```bash
./release.sh 1.2.0
```

Signs (Developer ID if `$DEVELOPER_ID` is set, ad-hoc otherwise), notarizes
(if `$NOTARY_PROFILE` is set), builds DMG + zip, and drafts the GitHub release
from the matching CHANGELOG section.
