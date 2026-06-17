#include "media_control_bridge.h"

#include <hidusage.h>

#include <algorithm>
#include <vector>

MediaControlBridge* MediaControlBridge::instance_ = nullptr;

namespace {

bool BoolArg(const flutter::EncodableValue* args, const char* key) {
  if (!args) return false;
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) return false;
  const auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) return false;
  const auto* value = std::get_if<bool>(&it->second);
  return value != nullptr && *value;
}

std::string CommandName(MediaControlBridge::Command command) {
  switch (command) {
    case MediaControlBridge::Command::kPlayPause:
      return "playPause";
    case MediaControlBridge::Command::kPlay:
      return "play";
    case MediaControlBridge::Command::kPause:
      return "pause";
    case MediaControlBridge::Command::kStop:
      return "stop";
    case MediaControlBridge::Command::kNext:
      return "next";
    case MediaControlBridge::Command::kPrevious:
      return "previous";
    case MediaControlBridge::Command::kVolumeUp:
      return "volumeUp";
    case MediaControlBridge::Command::kVolumeDown:
      return "volumeDown";
    case MediaControlBridge::Command::kVolumeMute:
      return "volumeMute";
  }
  return "unknown";
}

}  // namespace

MediaControlBridge::MediaControlBridge(flutter::BinaryMessenger* messenger,
                                       HWND window)
    : window_(window) {
  instance_ = this;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "player_vf_media_controls",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setOwnership") {
          app_active_ = BoolArg(call.arguments(), "active");
          playing_ = BoolArg(call.arguments(), "playing");
          SetOwned(OwnsControls());
          result->Success(flutter::EncodableValue(OwnsControls()));
          return;
        }
        result->NotImplemented();
      });
  RegisterRawInput();
}

MediaControlBridge::~MediaControlBridge() {
  RemoveKeyboardHook();
  if (instance_ == this) instance_ = nullptr;
}

bool MediaControlBridge::OwnsControls() const {
  return app_active_ || playing_;
}

void MediaControlBridge::SetOwned(bool owned) {
  if (owned) {
    InstallKeyboardHook();
  } else {
    RemoveKeyboardHook();
  }
}

void MediaControlBridge::InstallKeyboardHook() {
  if (keyboard_hook_ != nullptr) return;
  keyboard_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardProc, nullptr, 0);
}

void MediaControlBridge::RemoveKeyboardHook() {
  if (keyboard_hook_ == nullptr) return;
  UnhookWindowsHookEx(keyboard_hook_);
  keyboard_hook_ = nullptr;
}

void MediaControlBridge::RegisterRawInput() {
  RAWINPUTDEVICE device{};
  device.usUsagePage = HID_USAGE_PAGE_CONSUMER;
  device.usUsage = 0x01;
  device.dwFlags = RIDEV_INPUTSINK;
  device.hwndTarget = window_;
  RegisterRawInputDevices(&device, 1, sizeof(device));
}

void MediaControlBridge::HandleWindowMessage(UINT message, WPARAM wparam,
                                             LPARAM lparam, bool* handled) {
  if (!handled) return;
  switch (message) {
    case WM_ACTIVATE:
      app_active_ = LOWORD(wparam) != WA_INACTIVE;
      SetOwned(OwnsControls());
      break;
    case WM_INPUT:
      if (OwnsControls()) HandleRawInput(lparam);
      break;
    case WM_APPCOMMAND:
      if (OwnsControls() && HandleAppCommand(lparam)) {
        *handled = true;
      }
      break;
  }
}

void MediaControlBridge::SendCommand(Command command, const char* source) {
  if (!OwnsControls() || channel_ == nullptr) return;
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("command")] =
      flutter::EncodableValue(CommandName(command));
  payload[flutter::EncodableValue("source")] = flutter::EncodableValue(source);
  channel_->InvokeMethod("control",
                         std::make_unique<flutter::EncodableValue>(payload));
}

bool MediaControlBridge::ShouldDropDuplicate(Command command,
                                             DWORD window_ms) {
  const auto key = static_cast<int>(command);
  const DWORD now = GetTickCount();
  const auto it = last_command_ticks_.find(key);
  if (it != last_command_ticks_.end() && now - it->second < window_ms) {
    return true;
  }
  last_command_ticks_[key] = now;
  return false;
}

bool MediaControlBridge::HandleAppCommand(LPARAM lparam) {
  switch (GET_APPCOMMAND_LPARAM(lparam)) {
    case APPCOMMAND_MEDIA_PLAY_PAUSE:
      if (!ShouldDropDuplicate(Command::kPlayPause, 220))
        SendCommand(Command::kPlayPause, "appcommand");
      return true;
    case APPCOMMAND_MEDIA_PLAY:
      if (!ShouldDropDuplicate(Command::kPlay, 180))
        SendCommand(Command::kPlay, "appcommand");
      return true;
    case APPCOMMAND_MEDIA_PAUSE:
      if (!ShouldDropDuplicate(Command::kPause, 180))
        SendCommand(Command::kPause, "appcommand");
      return true;
    case APPCOMMAND_MEDIA_STOP:
      if (!ShouldDropDuplicate(Command::kStop, 180))
        SendCommand(Command::kStop, "appcommand");
      return true;
    case APPCOMMAND_MEDIA_NEXTTRACK:
      if (!ShouldDropDuplicate(Command::kNext, 220))
        SendCommand(Command::kNext, "appcommand");
      return true;
    case APPCOMMAND_MEDIA_PREVIOUSTRACK:
      if (!ShouldDropDuplicate(Command::kPrevious, 220))
        SendCommand(Command::kPrevious, "appcommand");
      return true;
    case APPCOMMAND_VOLUME_UP:
      if (!ShouldDropDuplicate(Command::kVolumeUp, 35))
        SendCommand(Command::kVolumeUp, "appcommand");
      return true;
    case APPCOMMAND_VOLUME_DOWN:
      if (!ShouldDropDuplicate(Command::kVolumeDown, 35))
        SendCommand(Command::kVolumeDown, "appcommand");
      return true;
    case APPCOMMAND_VOLUME_MUTE:
      if (!ShouldDropDuplicate(Command::kVolumeMute, 180))
        SendCommand(Command::kVolumeMute, "appcommand");
      return true;
  }
  return false;
}

void MediaControlBridge::HandleRawInput(LPARAM lparam) {
  UINT size = 0;
  GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT, nullptr,
                  &size, sizeof(RAWINPUTHEADER));
  if (size == 0) return;

  std::vector<BYTE> buffer(size);
  if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT,
                      buffer.data(), &size, sizeof(RAWINPUTHEADER)) != size) {
    return;
  }

  const RAWINPUT* raw = reinterpret_cast<const RAWINPUT*>(buffer.data());
  if (raw->header.dwType != RIM_TYPEHID) return;
  const RAWHID& hid = raw->data.hid;
  const BYTE* data = hid.bRawData;
  const size_t total = static_cast<size_t>(hid.dwSizeHid) * hid.dwCount;
  for (size_t i = 0; i + 1 < total; i += 2) {
    const USHORT usage = static_cast<USHORT>(data[i] | (data[i + 1] << 8));
    Command command = Command::kPlayPause;
    bool matched = true;
    switch (usage) {
      case 0x00E9:
        command = Command::kVolumeUp;
        break;
      case 0x00EA:
        command = Command::kVolumeDown;
        break;
      case 0x00E2:
        command = Command::kVolumeMute;
        break;
      case 0x00CD:
        command = Command::kPlayPause;
        break;
      case 0x00B5:
        command = Command::kNext;
        break;
      case 0x00B6:
        command = Command::kPrevious;
        break;
      default:
        matched = false;
        break;
    }
    if (!matched) continue;
    const DWORD window = command == Command::kVolumeUp ||
                                 command == Command::kVolumeDown
                             ? 35
                             : 220;
    if (!ShouldDropDuplicate(command, window)) {
      SendCommand(command, "rawinput");
    }
  }
}

bool MediaControlBridge::HandleKeyboardEvent(WPARAM wparam, LPARAM lparam) {
  if (!OwnsControls()) return false;
  if (wparam != WM_KEYDOWN && wparam != WM_SYSKEYDOWN) return false;
  const auto* keyboard = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
  Command command = Command::kPlayPause;
  DWORD duplicate_window = 220;
  switch (keyboard->vkCode) {
    case VK_MEDIA_PLAY_PAUSE:
      command = Command::kPlayPause;
      break;
    case VK_MEDIA_NEXT_TRACK:
      command = Command::kNext;
      break;
    case VK_MEDIA_PREV_TRACK:
      command = Command::kPrevious;
      break;
    case VK_MEDIA_STOP:
      command = Command::kStop;
      break;
    case VK_VOLUME_UP:
      command = Command::kVolumeUp;
      duplicate_window = 35;
      break;
    case VK_VOLUME_DOWN:
      command = Command::kVolumeDown;
      duplicate_window = 35;
      break;
    case VK_VOLUME_MUTE:
      command = Command::kVolumeMute;
      duplicate_window = 180;
      break;
    default:
      return false;
  }
  if (!ShouldDropDuplicate(command, duplicate_window)) {
    SendCommand(command, "keyboard_hook");
  }
  return true;
}

LRESULT CALLBACK MediaControlBridge::KeyboardProc(int code, WPARAM wparam,
                                                  LPARAM lparam) {
  if (code == HC_ACTION && instance_ != nullptr &&
      instance_->HandleKeyboardEvent(wparam, lparam)) {
    return 1;
  }
  return CallNextHookEx(instance_ ? instance_->keyboard_hook_ : nullptr, code,
                        wparam, lparam);
}
