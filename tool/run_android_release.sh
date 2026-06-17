#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf .dart_tool \
  build/app \
  .flutter-plugins \
  .flutter-plugins-dependencies

./tool/flutter_linux.sh pub get
./tool/flutter_linux.sh build apk --release "$@"

echo
echo "Android release APK:"
echo "  build/app/outputs/flutter-apk/app-release.apk"
