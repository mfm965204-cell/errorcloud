#!/usr/bin/env bash
# Generates the Android platform folder for Errorcloud with `flutter create`,
# so the Gradle/AGP/Kotlin versions always match the installed Flutter SDK.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
flutter create --platforms=android --org com.error --project-name errorcloud "$TMP/scaffold"
rm -rf android
cp -r "$TMP/scaffold/android" ./android
rm -rf "$TMP"

# App label shown under the launcher icon.
sed -i 's/android:label="errorcloud"/android:label="Errorcloud"/' android/app/src/main/AndroidManifest.xml

# Internet permission is required for the upload/download calls.
python3 - <<'PY'
import re, pathlib
p = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()
if 'android.permission.INTERNET' not in s:
    s = s.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
p.write_text(s)
PY

echo "Android platform scaffolded."
