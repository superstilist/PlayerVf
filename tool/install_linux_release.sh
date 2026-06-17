#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PlayerVF"
APP_ID="playervf"
EXECUTABLE_NAME="playervf"
ARCHIVE_URL="${PLAYERVF_ARCHIVE_URL:-https://github.com/superstilist/PlayerVf/releases/download/Release_V1/playervf.linux.zip}"
INSTALL_DIR="${PLAYERVF_INSTALL_DIR:-$HOME/.local/opt/playervf}"
BIN_DIR="${PLAYERVF_BIN_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

usage() {
  cat <<EOF
Install PlayerVF for Linux.

Usage:
  $(basename "$0") [options]

Options:
  --url URL           Download a different PlayerVF Linux ZIP.
  --install-dir DIR   Install directory. Default: $INSTALL_DIR
  --bin-dir DIR       Symlink directory. Default: $BIN_DIR
  --no-deps           Skip system dependency installation.
  --no-desktop        Skip desktop launcher creation.
  -h, --help          Show this help.

Environment:
  PLAYERVF_ARCHIVE_URL
  PLAYERVF_INSTALL_DIR
  PLAYERVF_BIN_DIR
EOF
}

install_deps=true
create_desktop=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      ARCHIVE_URL="${2:?Missing URL after --url}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:?Missing directory after --install-dir}"
      shift 2
      ;;
    --bin-dir)
      BIN_DIR="${2:?Missing directory after --bin-dir}"
      shift 2
      ;;
    --no-deps)
      install_deps=false
      shift
      ;;
    --no-desktop)
      create_desktop=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

sudo_cmd() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    need_cmd sudo
    sudo "$@"
  fi
}

install_system_dependencies() {
  local common_debian common_fedora common_arch common_suse optional_debian optional_fedora optional_arch optional_suse

  common_debian=(
    ca-certificates curl unzip python3 python3-venv python3-pip
    libgtk-3-0 libglib2.0-0 libblkid1 liblzma5 libstdc++6 libx11-6
    libpulse0
  )
  common_fedora=(
    ca-certificates curl unzip python3 python3-pip gtk3 glib2 util-linux-libs
    xz-libs libstdc++ libX11 pulseaudio-libs
  )
  common_arch=(
    ca-certificates curl unzip python python-pip gtk3 glib2 util-linux-libs
    xz gcc-libs libx11 libpulse
  )
  common_suse=(
    ca-certificates curl unzip python3 python3-pip gtk3 glib2 libblkid1
    liblzma5 libstdc++6 libX11-6 libpulse0
  )
  optional_debian=(libayatana-appindicator3-1 pipewire)
  optional_fedora=(libappindicator-gtk3 pipewire)
  optional_arch=(libappindicator-gtk3 pipewire)
  optional_suse=(libappindicator3-1 pipewire)

  install_optional() {
    "$@" >/dev/null 2>&1 || true
  }

  if command -v apt-get >/dev/null 2>&1; then
    sudo_cmd apt-get update
    sudo_cmd apt-get install -y "${common_debian[@]}"
    install_optional sudo_cmd apt-get install -y "${optional_debian[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    sudo_cmd dnf install -y "${common_fedora[@]}"
    install_optional sudo_cmd dnf install -y "${optional_fedora[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    sudo_cmd pacman -Sy --needed --noconfirm "${common_arch[@]}"
    install_optional sudo_cmd pacman -S --needed --noconfirm "${optional_arch[@]}"
  elif command -v zypper >/dev/null 2>&1; then
    sudo_cmd zypper --non-interactive install "${common_suse[@]}"
    install_optional sudo_cmd zypper --non-interactive install "${optional_suse[@]}"
  else
    echo "No supported package manager found. Install these manually:"
    echo "  curl unzip python3 python3-venv python3-pip gtk3 glib2 libblkid liblzma libstdc++ libx11"
  fi
}

download_archive() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --progress-bar "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
  else
    echo "curl or wget is required to download $url" >&2
    exit 1
  fi
}

find_bundle_dir() {
  local root="$1"
  local bundle

  bundle="$(find "$root" -type f -name "$EXECUTABLE_NAME" -perm -111 -printf '%h\n' 2>/dev/null | head -n 1 || true)"
  if [[ -z "$bundle" ]]; then
    bundle="$(find "$root" -type f -name "$EXECUTABLE_NAME" -printf '%h\n' 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -z "$bundle" ]]; then
    echo "Could not find $EXECUTABLE_NAME inside the downloaded archive." >&2
    echo "Expected a ZIP containing a Flutter Linux bundle directory." >&2
    exit 1
  fi

  printf '%s\n' "$bundle"
}

write_launcher() {
  local launcher="$1"
  local app_dir="$2"

  cat > "$launcher" <<EOF
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$app_dir"

uid="\$(id -u 2>/dev/null || printf '1000')"
if [[ -z "\${XDG_RUNTIME_DIR:-}" && -d "/run/user/\$uid" ]]; then
  export XDG_RUNTIME_DIR="/run/user/\$uid"
fi
if [[ -z "\${PIPEWIRE_RUNTIME_DIR:-}" && -n "\${XDG_RUNTIME_DIR:-}" ]]; then
  export PIPEWIRE_RUNTIME_DIR="\$XDG_RUNTIME_DIR"
fi
if [[ -z "\${PULSE_SERVER:-}" && -S /mnt/wslg/PulseServer ]]; then
  export PULSE_SERVER="unix:/mnt/wslg/PulseServer"
elif [[ -z "\${PULSE_SERVER:-}" && -n "\${XDG_RUNTIME_DIR:-}" && -S "\$XDG_RUNTIME_DIR/pulse/native" ]]; then
  export PULSE_SERVER="unix:\$XDG_RUNTIME_DIR/pulse/native"
fi

export PLAYER_VF_LINUX_AUDIO_OUTPUTS="\${PLAYER_VF_LINUX_AUDIO_OUTPUTS:-pulse,pipewire,alsa}"
exec "\$APP_DIR/$EXECUTABLE_NAME" "\$@"
EOF
  chmod +x "$launcher"
}

write_desktop_file() {
  local desktop_file="$1"
  local launcher="$2"
  local app_dir="$3"
  local icon="$app_dir/data/flutter_assets/assets/logo.png"

  mkdir -p "$(dirname "$desktop_file")"
  cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Modern music player
Exec=$launcher
Icon=$icon
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=$EXECUTABLE_NAME
EOF
  chmod 0644 "$desktop_file"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$(dirname "$desktop_file")" >/dev/null 2>&1 || true
  fi
}

main() {
  local tmp archive extract_dir bundle_dir target_tmp launcher desktop_file

  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "This installer is for Linux." >&2
    exit 1
  fi

  case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
      echo "Warning: this release archive is expected to be x64 Linux. Current architecture: $(uname -m)"
      ;;
  esac

  if [[ "$install_deps" == true ]]; then
    install_system_dependencies
  fi

  need_cmd unzip
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  archive="$tmp/playervf.linux.zip"
  extract_dir="$tmp/extract"
  mkdir -p "$extract_dir"

  echo "Downloading PlayerVF:"
  echo "  $ARCHIVE_URL"
  download_archive "$ARCHIVE_URL" "$archive"

  echo "Extracting archive..."
  unzip -q "$archive" -d "$extract_dir"
  bundle_dir="$(find_bundle_dir "$extract_dir")"

  target_tmp="${INSTALL_DIR}.tmp.$$"
  rm -rf "$target_tmp"
  mkdir -p "$(dirname "$INSTALL_DIR")" "$target_tmp"
  cp -a "$bundle_dir/." "$target_tmp/"
  chmod +x "$target_tmp/$EXECUTABLE_NAME"

  rm -rf "$INSTALL_DIR"
  mv "$target_tmp" "$INSTALL_DIR"

  mkdir -p "$BIN_DIR"
  launcher="$BIN_DIR/$APP_ID"
  write_launcher "$launcher" "$INSTALL_DIR"

  if [[ "$create_desktop" == true ]]; then
    desktop_file="$DESKTOP_DIR/$APP_ID.desktop"
    write_desktop_file "$desktop_file" "$launcher" "$INSTALL_DIR"
  fi

  echo
  echo "$APP_NAME installed successfully."
  echo "Run it with:"
  echo "  $launcher"
  if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo
    echo "Add $BIN_DIR to PATH to run '$APP_ID' from any terminal."
  fi
}

main "$@"
