#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/linux/packaged/ffmpeg"
FFMPEG_SOURCE="${1:-$(command -v ffmpeg || true)}"
FFPROBE_SOURCE="$(command -v ffprobe || true)"

download_static_ffmpeg() {
  local arch url tmp archive extracted
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
      ;;
    aarch64|arm64)
      url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-arm64-static.tar.xz"
      ;;
    *)
      echo "No automatic FFmpeg download is configured for architecture: $arch"
      return 1
      ;;
  esac

  tmp="$(mktemp -d)"
  archive="$tmp/ffmpeg.tar.xz"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail "$url" -o "$archive"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$archive" "$url"
  else
    echo "curl or wget is required to auto-download FFmpeg."
    return 1
  fi

  tar -xJf "$archive" -C "$tmp"
  extracted="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  FFMPEG_SOURCE="$extracted/ffmpeg"
  FFPROBE_SOURCE="$extracted/ffprobe"
}

if [[ -z "$FFMPEG_SOURCE" || ! -x "$FFMPEG_SOURCE" ]]; then
  echo "ffmpeg executable not found; downloading a static FFmpeg build."
  download_static_ffmpeg
fi

rm -rf "$DEST"
mkdir -p "$DEST/bin" "$DEST/lib"

cp "$FFMPEG_SOURCE" "$DEST/bin/ffmpeg.real"
chmod +x "$DEST/bin/ffmpeg.real"

if [[ -n "${FFPROBE_SOURCE:-}" && -x "$FFPROBE_SOURCE" ]]; then
  cp "$FFPROBE_SOURCE" "$DEST/bin/ffprobe.real"
  chmod +x "$DEST/bin/ffprobe.real"
fi

if command -v ldd >/dev/null 2>&1; then
  LDD_OUTPUT="$(mktemp)"
  if ldd "$FFMPEG_SOURCE" > "$LDD_OUTPUT" 2>/dev/null; then
    awk '/=>/ { print $3 } /^[[:space:]]*\/.*\.so/ { print $1 }' "$LDD_OUTPUT" \
    | while read -r lib; do
        [[ -f "$lib" ]] || continue
        case "$lib" in
          /lib*/ld-linux*|/usr/lib*/ld-linux*|/lib*/libc.so*|/usr/lib*/libc.so*)
            continue
            ;;
        esac
        cp -L "$lib" "$DEST/lib/" 2>/dev/null || true
      done
  fi
  rm -f "$LDD_OUTPUT"
fi

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'DIR="$(cd "$(dirname "$0")" && pwd)"'
  printf '%s\n' 'export LD_LIBRARY_PATH="$DIR/../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'
  printf '%s\n' 'exec "$DIR/ffmpeg.real" "$@"'
} > "$DEST/bin/ffmpeg"
chmod +x "$DEST/bin/ffmpeg"

if [[ -x "$DEST/bin/ffprobe.real" ]]; then
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'DIR="$(cd "$(dirname "$0")" && pwd)"'
    printf '%s\n' 'export LD_LIBRARY_PATH="$DIR/../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'
    printf '%s\n' 'exec "$DIR/ffprobe.real" "$@"'
  } > "$DEST/bin/ffprobe"
  chmod +x "$DEST/bin/ffprobe"
fi

cat > "$DEST/README.txt" <<EOF
Bundled FFmpeg copied from:
$FFMPEG_SOURCE

Created by tool/package_linux_ffmpeg.sh.
EOF

echo "Bundled FFmpeg prepared at $DEST"
