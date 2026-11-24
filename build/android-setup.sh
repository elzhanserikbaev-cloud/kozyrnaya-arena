#!/usr/bin/env bash
# Готовит Android-проект Capacitor: горизонтальная ориентация, версия, иконки.
set -euo pipefail
VER=$(node -p "require('./package.json').version")
IFS=. read -r MA MI PA <<< "$VER"
CODE=$((MA * 10000 + MI * 100 + PA))

npx cap add android
npx cap sync android

# Игра только горизонтально
perl -0pi -e 's/<activity(\s)/<activity android:screenOrientation="sensorLandscape"$1/' android/app/src/main/AndroidManifest.xml
grep -q 'screenOrientation="sensorLandscape"' android/app/src/main/AndroidManifest.xml

# Версия приложения (versionCode растёт с каждой версией — обновления ставятся поверх)
sed -i "s/versionCode [0-9]*/versionCode $CODE/; s/versionName \"[^\"]*\"/versionName \"$VER\"/" android/app/build.gradle
grep -E 'versionCode|versionName' android/app/build.gradle

# Иконки из build/icon.png
RES=android/app/src/main/res
rm -rf "$RES/mipmap-anydpi-v26"
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  n=${d%%:*}; s=${d##*:}
  mkdir -p "$RES/mipmap-$n"
  convert build/icon.png -resize "${s}x${s}" "$RES/mipmap-$n/ic_launcher.png"
  cp "$RES/mipmap-$n/ic_launcher.png" "$RES/mipmap-$n/ic_launcher_round.png"
  rm -f "$RES/mipmap-$n/ic_launcher_foreground.png"
done
echo "Android-проект готов: версия $VER ($CODE)"
