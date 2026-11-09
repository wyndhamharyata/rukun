#!/bin/sh
# Makes build/Rukun.app as GPUI Kit's packaging guide makes a local bundle: the release build, the
# bundle's folders and Info.plist, the photos and avatars in Resources, and an ad hoc signature.
set -eu
cd "$(dirname "$0")"
cargo build --release --locked

app=build/Rukun.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp target/release/rukun "$app/Contents/MacOS/rukun"
cp -R ../../data/photos ../../data/avatars "$app/Contents/Resources/"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Rukun</string>
  <key>CFBundleDisplayName</key><string>Rukun</string>
  <key>CFBundleIdentifier</key><string>dev.thor.research.rukun-gpui</string>
  <key>CFBundleExecutable</key><string>rukun</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

plutil -lint "$app/Contents/Info.plist" >/dev/null
codesign --force --sign - "$app"
echo "built $app"
