#!/usr/bin/env bash
# Выравнивает и подписывает APK.
# Постоянный ключ берётся из секретов ANDROID_KEYSTORE_B64 / ANDROID_KEYSTORE_PASS (PKCS12, псевдоним upload).
# Без секретов APK подписывается временным ключом: ставится, но обновление потребует удалить старую версию.
set -euo pipefail
VER=$(node -p "require('./package.json').version")
BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
IN=android/app/build/outputs/apk/release/app-release-unsigned.apk
OUT="dist/KozyrnayaArena-$VER-Android.apk"
mkdir -p dist
"$BT/zipalign" -p -f 4 "$IN" aligned.apk
if [ -n "${KS_B64:-}" ] && [ -n "${KS_PASS:-}" ]; then
  echo "$KS_B64" | base64 -d > ks.p12
  "$BT/apksigner" sign --ks ks.p12 --ks-type PKCS12 --ks-pass env:KS_PASS --ks-key-alias upload --out "$OUT" aligned.apk
  rm -f ks.p12
  echo "Подписано постоянным ключом"
else
  echo "::warning::Нет секретов ANDROID_KEYSTORE_B64/ANDROID_KEYSTORE_PASS: APK подписан временным ключом"
  keytool -genkeypair -keystore tmp.p12 -storetype PKCS12 -storepass temppass -keypass temppass -alias tmp \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Kozyrnaya Arena"
  "$BT/apksigner" sign --ks tmp.p12 --ks-type PKCS12 --ks-pass pass:temppass --ks-key-alias tmp --out "$OUT" aligned.apk
  rm -f tmp.p12
fi
"$BT/apksigner" verify --print-certs "$OUT" | head -3
ls -la "$OUT"
