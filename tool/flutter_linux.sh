#!/usr/bin/env bash
set -euo pipefail

flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"

if [[ -z "$flutter_bin" ]]; then
  echo "flutter was not found in PATH."
  exit 127
fi

if [[ ! -f "$flutter_bin" ]]; then
  exec "$flutter_bin" "$@"
fi

normalize_lf() {
  local file="$1"

  [[ -f "$file" ]] || return 0
  if LC_ALL=C grep -Iq . "$file" && LC_ALL=C grep -q $'\r' "$file"; then
    tmp="${file}.player_vf_lf.$$"
    tr -d '\r' < "$file" > "$tmp"
    chmod --reference="$file" "$tmp" 2>/dev/null || chmod +x "$tmp"
    mv "$tmp" "$file"
    echo "Normalized CRLF to LF: $file"
  fi
}

normalize_lf "$flutter_bin"

flutter_dir="$(cd "$(dirname "$flutter_bin")" && pwd)"
if [[ -d "$flutter_dir/internal" ]]; then
  while IFS= read -r -d '' script; do
    normalize_lf "$script"
  done < <(find "$flutter_dir/internal" -maxdepth 1 -type f -name '*.sh' -print0)
fi

exec "$flutter_bin" "$@"
