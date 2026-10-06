#!/bin/bash
# İmzalanmış MenuMonitor.app paketinden kurulum disk imajı üretir.
# İmajda uygulama ve /Applications kısayolu yan yana durur.
# Kullanım: make-dmg.sh <MenuMonitor.app> <çıktı.dmg>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Kullanım: make-dmg.sh <MenuMonitor.app> <çıktı.dmg>" >&2
  exit 1
fi

APP_PATH=$1
DMG_PATH=$2
VOL_NAME="MenuMonitor"
APP_NAME="$(basename "$APP_PATH")"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Uygulama bulunamadı: $APP_PATH" >&2
  exit 1
fi

# Aynı adda açık bir imaj kaldıysa yeni attach başarısız olur.
if [[ -d "/Volumes/$VOL_NAME" ]]; then
  hdiutil detach "/Volumes/$VOL_NAME" -force >/dev/null 2>&1 || true
fi

WORK="$(mktemp -d)"
# Finder "tell disk" yalnızca /Volumes altındaki birimi görür.
MOUNT="/Volumes/$VOL_NAME"
MOUNTED=0

cleanup() {
  if [[ "$MOUNTED" -eq 1 ]]; then
    hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    MOUNTED=0
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

STAGE="$WORK/stage"
mkdir -p "$STAGE"
# ditto imzayı, genişletilmiş öznitelikleri ve zımbalanmış noter biletini korur.
ditto "$APP_PATH" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

RW="$WORK/rw.dmg"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$RW"

# -nobrowse Finder'ın diski görmesini engeller; yerleşim için birim /Volumes altında açılır.
hdiutil attach "$RW" -noverify -noautoopen
MOUNTED=1

if [[ ! -d "$MOUNT/$APP_NAME" || ! -L "$MOUNT/Applications" ]]; then
  echo "İmajda uygulama veya Applications kısayolu yok." >&2
  exit 1
fi

# Finder yerleşimi olmadan da imaj kurulabilir. CI'da Finder takılırsa imajı düşürmeyiz.
layout_window() {
  osascript <<EOF
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    -- Pencere açılmadan görünüm değişirse Finder -10006 döner.
    delay 2
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 16
    delay 1
    set position of item "$APP_NAME" of container window to {180, 205}
    set position of item "Applications" of container window to {480, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
}

layout_window &
LAYOUT_PID=$!
LAYOUT_DONE=0
for _ in $(seq 1 25); do
  if ! kill -0 "$LAYOUT_PID" 2>/dev/null; then
    if wait "$LAYOUT_PID"; then
      LAYOUT_DONE=1
    fi
    break
  fi
  sleep 1
done
if [[ "$LAYOUT_DONE" -ne 1 ]]; then
  kill "$LAYOUT_PID" 2>/dev/null || true
  wait "$LAYOUT_PID" 2>/dev/null || true
  echo "Pencere yerleşimi ayarlanamadı; imaj yine de oluşturuluyor." >&2
fi

rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes" "$MOUNT/.Spotlight-V100" || true
sync
hdiutil detach "$MOUNT"
MOUNTED=0

rm -f "$DMG_PATH" "${DMG_PATH}.dmg"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
# Bazı hdiutil sürümleri -o yoluna ikinci bir .dmg ekler.
if [[ -f "${DMG_PATH}.dmg" && ! -f "$DMG_PATH" ]]; then
  mv "${DMG_PATH}.dmg" "$DMG_PATH"
fi

if [[ ! -s "$DMG_PATH" ]]; then
  echo "Disk imajı oluşturulamadı: $DMG_PATH" >&2
  exit 1
fi

ls -l "$DMG_PATH"
