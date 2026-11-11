#!/bin/sh
# Makes build/<Name>.app from the thor app in the current folder, signed ad hoc so it runs on this
# Mac. Run it from the app's folder: ./thor/bundle.sh <Name> [icon.png]
# The folder resources/, if there is one, goes into the .app's Resources, where app.resource_path
# finds it. A 1024 by 1024 PNG becomes the app's icon.
set -eu
name=${1:?usage: ./thor/bundle.sh <Name> [icon.png]}
icon=${2:-}
executable=$(printf '%s' "$name" | tr 'A-Z ' 'a-z-')
app="build/$name.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# -minimum-os-version: with none, the binary asks for the macOS that built it, and Finder refuses
#   to open it on an older one.
# -use-separate-modules: with -o:speed and none, the input view's Objective-C methods drop out of
#   the binary, and typing stops working.
odin build . -out:"$app/Contents/MacOS/$executable" -o:speed -use-separate-modules \
	-minimum-os-version:26.0

if [ -d resources ]; then cp -RL resources/. "$app/Contents/Resources/"; fi

icon_entry=""
if [ -n "$icon" ]; then
	iconset=$(mktemp -d)/AppIcon.iconset
	mkdir -p "$iconset"
	for size in 16 32 128 256 512; do
		sips -z $size $size "$icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
		sips -z $((size * 2)) $((size * 2)) "$icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
	done
	iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
	icon_entry="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>$name</string>
	<key>CFBundleIdentifier</key><string>dev.thor.$executable</string>
	<key>CFBundleExecutable</key><string>$executable</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>NSHighResolutionCapable</key><true/>
	$icon_entry
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null 2>&1
echo "built $app"
