#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox -c release
app_destination="${1:-$PWD/Skill Library.app}"
mkdir -p "$app_destination/Contents/MacOS" "$app_destination/Contents/Resources"
cp .build/release/SkillLibrary "$app_destination/Contents/MacOS/SkillLibrary"
cp .build/release/skilltool "$app_destination/Contents/MacOS/skilltool"
cp Guide.html "$app_destination/Contents/Resources/Guide.html"
ditto RecoverySkill "$app_destination/Contents/Resources/RecoverySkill"
if [ -d SeedLibrary ]; then ditto SeedLibrary "$app_destination/Contents/Resources/SeedLibrary"; fi
swift MakeIcon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app_destination/Contents/Resources/AppIcon.icns"
cat > "$app_destination/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SkillLibrary</string>
<key>CFBundleIdentifier</key><string>com.joelhoke.skilllibrary</string>
<key>CFBundleName</key><string>Skill Library</string>
<key>CFBundleDisplayName</key><string>Skill Library</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_destination"
printf 'Built: %s\n' "$app_destination"
