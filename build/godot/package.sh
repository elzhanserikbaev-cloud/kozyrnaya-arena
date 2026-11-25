#!/usr/bin/env bash
# Упаковка результатов экспорта Godot в файлы релиза.
#   build/godot/package.sh <версия> <каталог экспорта> <каталог вывода>
# Ожидает в каталоге экспорта: windows/ linux/ macos/KozyrnayaArena.zip android/KozyrnayaArena.apk
set -euo pipefail
VER="$1"; EXP="$(cd "$2" && pwd)"; OUT="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
N="KozyrnayaArena-$VER"
ICON="$ROOT/godot/assets/icon.png"; [ -f "$ICON" ] || ICON="$ROOT/build/icon.png"
STAGE="$(mktemp -d)"

# Windows: отдельный exe (pck внутри) + zip с exe и DLL WebRTC (без DLL онлайн недоступен).
if [ -f "$EXP/windows/KozyrnayaArena.exe" ]; then
  mkdir -p "$STAGE/win/KozyrnayaArena"
  cp "$EXP"/windows/*.exe "$STAGE/win/KozyrnayaArena/"
  cp "$EXP"/windows/*.dll "$STAGE/win/KozyrnayaArena/" 2>/dev/null || echo "::warning::нет DLL WebRTC для Windows"
  (cd "$STAGE/win" && zip -9 -r -q "$OUT/$N-Windows.zip" KozyrnayaArena)
fi

# Linux: бинарник + .so + .desktop + значок + README.
if [ -f "$EXP/linux/KozyrnayaArena.x86_64" ]; then
  D="$STAGE/linux/KozyrnayaArena"; mkdir -p "$D"
  cp "$EXP/linux/KozyrnayaArena.x86_64" "$D/"
  cp "$EXP"/linux/*.so "$D/" 2>/dev/null || echo "::warning::нет .so WebRTC для Linux"
  chmod +x "$D/KozyrnayaArena.x86_64"
  cp "$HERE/kozyrnaya-arena.desktop" "$HERE/README-Linux.txt" "$D/"
  [ -f "$ICON" ] && cp "$ICON" "$D/kozyrnaya-arena.png"
  (cd "$STAGE/linux" && zip -9 -r -q -y "$OUT/$N-Linux-x86_64.zip" KozyrnayaArena)
fi

# macOS: Godot уже собрал zip с .app (универсальный, ad-hoc подпись).
[ -f "$EXP/macos/KozyrnayaArena.zip" ] && cp "$EXP/macos/KozyrnayaArena.zip" "$OUT/$N-macOS-universal.zip"

# Web: архив для GitHub Pages (pages.yml берёт его из последнего релиза).
if [ -f "$EXP/web/index.html" ]; then
  (cd "$EXP/web" && zip -9 -r -q "$OUT/$N-Web.zip" .)
fi

# Android: APK уже подписан при экспорте.
[ -f "$EXP/android/KozyrnayaArena.apk" ] && cp "$EXP/android/KozyrnayaArena.apk" "$OUT/$N-Android.apk"

rm -rf "$STAGE"
ls -la "$OUT"
