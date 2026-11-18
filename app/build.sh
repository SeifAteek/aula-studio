#!/bin/zsh
# Builds, self-checks, signs and packages AULA Studio.app.
# Set AULA_RELEASE=1 for a public build with an anonymous signature.
set -euo pipefail
cd "${0:A:h}"

# Keep this computer's folder names out of the compiled app.
PREFIX_MAP=(-Xswiftc -file-prefix-map -Xswiftc "$PWD=.")
swift build -c release --product AulaStudio "${PREFIX_MAP[@]}"
BIN="$(swift build -c release --show-bin-path "${PREFIX_MAP[@]}")/AulaStudio"
"$BIN" --self-check

APP="build/AULA Studio.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp "$BIN" "$APP/Contents/MacOS/AULA Studio"
cp Info.plist "$APP/Contents/Info.plist"

"$BIN" --write-icon build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# A stable local signature lets macOS remember the app's permissions between rebuilds.
IDENTITY="-"
if [[ -z "${AULA_RELEASE:-}" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
codesign --force --sign "${IDENTITY:--}" --identifier local.aula.studio "$APP" 2>/dev/null
codesign --verify "$APP"
echo "Built: $APP"
