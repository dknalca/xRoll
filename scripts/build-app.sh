#!/bin/zsh
set -eu

project_root=${0:A:h:h}
output="$project_root/dist/xRoll.app"
binary="$project_root/.build/release/xroll-pads"

cd "$project_root"
swift build -c release --product xroll-pads
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
cp "$binary" "$output/Contents/MacOS/xRoll"
cat > "$output/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDisplayName</key><string>xRoll</string>
  <key>CFBundleExecutable</key><string>xRoll</string>
  <key>CFBundleIdentifier</key><string>com.alkbit.xroll</string>
  <key>CFBundleName</key><string>xRoll</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
PLIST
echo "Aplicacion creada: $output"
