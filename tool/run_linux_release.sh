#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source ./tool/linux_audio_env.sh
setup_player_vf_linux_audio_env

if command -v mpv >/dev/null 2>&1; then
  ./tool/package_linux_mpv.sh
else
  echo "mpv not found on this machine; building without bundled mpv."
  echo "Install mpv and rerun this script to bundle it into the Linux release."
fi

bash ./tool/package_linux_ffmpeg.sh

rm -rf .dart_tool \
  build/linux \
  linux/flutter/ephemeral \
  .flutter-plugins \
  .flutter-plugins-dependencies

./tool/flutter_linux.sh pub get
./tool/flutter_linux.sh build linux --release "$@"

echo
echo "Linux release bundle:"
echo "  build/linux/x64/release/bundle"
