#!/bin/zsh
set -euo pipefail

swift build -c release

app_path="FocusMode.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources"
cp ".build/release/FocusMode" "$app_path/Contents/MacOS/FocusMode"
cp "App/Info.plist" "$app_path/Contents/Info.plist"
cp -R ".build/release/FocusMode_FocusMode.bundle" "$app_path/Contents/Resources/"

iconset_path=".build/FocusMode.iconset"
master_icon_path=".build/FocusMode-icon.png"
rm -rf "$iconset_path"
mkdir -p "$iconset_path"
sips -s format png "assets/mark.svg" --out "$master_icon_path" >/dev/null

create_icon() {
    sips -z "$2" "$2" "$master_icon_path" --out "$iconset_path/$1" >/dev/null
}

create_icon "icon_16x16.png" 16
create_icon "icon_16x16@2x.png" 32
create_icon "icon_32x32.png" 32
create_icon "icon_32x32@2x.png" 64
create_icon "icon_128x128.png" 128
create_icon "icon_128x128@2x.png" 256
create_icon "icon_256x256.png" 256
create_icon "icon_256x256@2x.png" 512
create_icon "icon_512x512.png" 512
create_icon "icon_512x512@2x.png" 1024
iconutil -c icns "$iconset_path" -o "$app_path/Contents/Resources/FocusMode.icns"

codesign --force --sign - "$app_path"

if [[ "${1:-}" != "--no-open" ]]; then
    open "$app_path"
fi
