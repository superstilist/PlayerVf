#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MPV_SOURCE="${1:-$(command -v mpv || true)}"
DEST="$ROOT/linux/packaged/mpv"

if [[ -z "$MPV_SOURCE" || ! -x "$MPV_SOURCE" ]]; then
  echo "mpv executable not found."
  echo "Install mpv for packaging, or pass an executable path:"
  echo "  tool/package_linux_mpv.sh /path/to/mpv"
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST/bin" "$DEST/lib"

cp "$MPV_SOURCE" "$DEST/bin/mpv.real"
chmod +x "$DEST/bin/mpv.real"

ldd "$MPV_SOURCE" \
  | awk '/=>/ { print $3 } /^[[:space:]]*\/.*\.so/ { print $1 }' \
  | while read -r lib; do
      [[ -f "$lib" ]] || continue
      case "$lib" in
        /lib*/ld-linux*|/usr/lib*/ld-linux*|/lib*/libc.so*|/usr/lib*/libc.so*)
          continue
          ;;
      esac
      cp -L "$lib" "$DEST/lib/" 2>/dev/null || true
    done

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'DIR="$(cd "$(dirname "$0")" && pwd)"'
  printf '%s\n' 'if [[ -z "${PULSE_SERVER:-}" && -S /mnt/wslg/PulseServer ]]; then'
  printf '%s\n' '  export PULSE_SERVER="unix:/mnt/wslg/PulseServer"'
  printf '%s\n' 'fi'
  printf '%s\n' 'if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then'
  printf '%s\n' '  export XDG_RUNTIME_DIR="/run/user/$(id -u)"'
  printf '%s\n' 'fi'
  printf '%s\n' 'export PLAYER_VF_LINUX_AUDIO_OUTPUTS="${PLAYER_VF_LINUX_AUDIO_OUTPUTS:-pulse,pipewire,alsa}"'
  printf '%s\n' 'export LD_LIBRARY_PATH="$DIR/../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'
  printf '%s\n' 'exec "$DIR/mpv.real" "$@"'
} > "$DEST/bin/mpv"
chmod +x "$DEST/bin/mpv"

cat > "$DEST/README.txt" <<EOF
Bundled mpv copied from:
$MPV_SOURCE

Created by tool/package_linux_mpv.sh.
EOF

echo "Bundled mpv prepared at $DEST"
echo "Rebuild Linux: flutter build linux"
