#!/usr/bin/env bash

setup_player_vf_linux_audio_env() {
  local uid
  uid="$(id -u 2>/dev/null || printf '1000')"

  if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$uid" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$uid"
  fi

  if [[ -z "${PIPEWIRE_RUNTIME_DIR:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
  fi

  if [[ -z "${PULSE_SERVER:-}" ]]; then
    if [[ -S /mnt/wslg/PulseServer ]]; then
      export PULSE_SERVER="unix:/mnt/wslg/PulseServer"
    elif [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/pulse/native" ]]; then
      export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
    fi
  fi

  export PLAYER_VF_LINUX_AUDIO_OUTPUTS="${PLAYER_VF_LINUX_AUDIO_OUTPUTS:-pulse,pipewire,alsa}"

  if [[ -n "${PULSE_SERVER:-}" ]]; then
    echo "PlayerVF audio: using PulseAudio at $PULSE_SERVER"
  elif [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/pipewire-0" ]]; then
    echo "PlayerVF audio: using PipeWire at $XDG_RUNTIME_DIR/pipewire-0"
  elif [[ -e /dev/snd/controlC0 || -e /dev/snd/pcmC0D0p ]]; then
    echo "PlayerVF audio: using ALSA device under /dev/snd"
  else
    echo "PlayerVF audio warning: no PulseAudio/PipeWire socket or ALSA card found."
    echo "If this is WSL, start the app from WSLg with /mnt/wslg/PulseServer available."
  fi
}
