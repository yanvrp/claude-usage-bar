#!/bin/bash
# Compila em release, monta Limites.app, assina localmente (ad-hoc) e instala em ~/Applications.
# Uso: scripts/empacotar.sh          (instala e abre)
#      scripts/empacotar.sh --so-montar  (só gera build/Limites.app)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSAO="1.0.0"
APP="build/Limites.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Limites" "$APP/Contents/MacOS/Limites"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.yanrockenback.limites</string>
  <key>CFBundleName</key><string>Limites</string>
  <key>CFBundleDisplayName</key><string>Limites do Claude</string>
  <key>CFBundleExecutable</key><string>Limites</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSAO}</string>
  <key>CFBundleVersion</key><string>${VERSAO}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Yan Rockenback</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Montado: $APP"

if [ "${1:-}" != "--so-montar" ]; then
  mkdir -p "$HOME/Applications"
  pkill -x Limites 2>/dev/null || true
  # Espera o app antigo fechar de vez: abrir antes disso dá o erro -609 do macOS.
  for _ in $(seq 1 20); do pgrep -x Limites >/dev/null || break; sleep 0.25; done
  rm -rf "$HOME/Applications/Limites.app"
  cp -R "$APP" "$HOME/Applications/Limites.app"
  open "$HOME/Applications/Limites.app"
  echo "Instalado e aberto: ~/Applications/Limites.app"
fi
