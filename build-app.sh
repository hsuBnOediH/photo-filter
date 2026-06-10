#!/bin/bash
# Builds PhotoFilter and assembles it into a runnable .app bundle, then ad-hoc signs it.
# We assemble the bundle by hand because plain SwiftPM (no full Xcode) can't emit a .app.
set -euo pipefail

APP_NAME="PhotoFilter"
BUNDLE_ID="com.yukunf.photofilter"   # MUST stay stable — TCC keys the Photos grant to it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --universal also cross-compiles an x86_64 slice and lipo-merges it, so the app runs
# on Intel Macs too — use it when packaging for other people. (Done via two --triple
# builds because swiftpm's --arch needs full Xcode, and this machine has CLT only.)
UNIVERSAL=0
[ "${1:-}" = "--universal" ] && UNIVERSAL=1

echo "==> Building (release)…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

if [ "$UNIVERSAL" = 1 ]; then
  # Separate scratch path — sharing .build between two triples corrupts swiftpm's
  # build database ("command … not registered").
  echo "==> Building x86_64 slice…"
  swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-x86
  X86_PATH="$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-x86 --show-bin-path)/$APP_NAME"
  FAT_PATH="$SCRIPT_DIR/.build/$APP_NAME-universal"
  lipo -create "$BIN_PATH" "$X86_PATH" -output "$FAT_PATH"
  BIN_PATH="$FAT_PATH"
  echo "==> Universal binary: $(lipo -archs "$FAT_PATH")"
fi
if [ ! -f "$BIN_PATH" ]; then
  echo "Build failed: binary not found at $BIN_PATH" >&2
  exit 1
fi

APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# SwiftPM packs Localizable.strings into this bundle, and the generated
# Bundle.module accessor looks for it in Contents/Resources when running inside
# a .app — without this copy the app CRASHES on the first localized string.
# The arm64 build's copy is fine for universal builds (strings are arch-free).
RES_BUNDLE="$(swift build -c release --show-bin-path)/${APP_NAME}_${APP_NAME}.bundle"
if [ ! -d "$RES_BUNDLE" ]; then
  echo "Build failed: resource bundle not found at $RES_BUNDLE" >&2
  exit 1
fi
cp -R "$RES_BUNDLE" "$APP_DIR/Contents/Resources/"

# Localized TCC prompt (the plist itself keeps an English fallback below).
mkdir -p "$APP_DIR/Contents/Resources/en.lproj" "$APP_DIR/Contents/Resources/zh-Hans.lproj"
cat > "$APP_DIR/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOF'
"NSPhotoLibraryUsageDescription" = "PhotoFilter needs access to your photo library to browse and delete photos.";
EOF
cat > "$APP_DIR/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'EOF'
"NSPhotoLibraryUsageDescription" = "PhotoFilter 需要访问你的照片图库，以便浏览并删除照片。";
EOF

# NSPhotoLibraryUsageDescription is mandatory — without it macOS silently denies access.
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>             <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>             <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                   <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>            <string>APPL</string>
    <key>CFBundleShortVersionString</key>     <string>1.0</string>
    <key>CFBundleVersion</key>                <string>1</string>
    <key>LSMinimumSystemVersion</key>         <string>14.0</string>
    <key>NSHighResolutionCapable</key>        <true/>
    <key>CFBundleDevelopmentRegion</key>      <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>LSApplicationCategoryType</key>      <string>public.app-category.photography</string>
    <key>NSHumanReadableCopyright</key>       <string>MIT License</string>
    <key>NSPhotoLibraryUsageDescription</key> <string>PhotoFilter needs access to your photo library to browse and delete photos.</string>
</dict>
</plist>
EOF

echo "==> Validating Info.plist…"
plutil -lint "$APP_DIR/Contents/Info.plist"

# Sign LAST, after Info.plist is in place, so the signature covers it.
echo "==> Codesigning (ad-hoc)…"
codesign --force --sign - "$APP_DIR"

echo ""
echo "==> Done: $APP_DIR"
echo "启动方式(重要):用 Finder 双击,或运行下面这行 —— 不要用 'swift run',否则权限会归到终端而不是 App:"
echo "    open \"$APP_DIR\""
