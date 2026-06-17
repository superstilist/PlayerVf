#ifndef RUNNER_MEDIA_CONTROL_BRIDGE_H_
#define RUNNER_MEDIA_CONTROL_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>
#include <unordered_map>

class MediaControlBridge {
 public:
  enum class Command {
    kPlayPause,
    kPlay,
    kPause,
    kStop,
    kNext,
    kPrevious,
    kVolumeUp,
    kVolumeDown,
    kVolumeMute,
  };

  MediaControlBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~MediaControlBridge();

  void HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam,
                           bool* handled);

 private:
  void SetOwned(bool owned);
  bool OwnsControls() const;
  void InstallKeyboardHook();
  void RemoveKeyboardHook();
  void RegisterRawInput();
  void SendCommand(Command command, const char* source);
  bool ShouldDropDuplicate(Command command, DWORD window_ms);
  bool HandleAppCommand(LPARAM lparam);
  void HandleRawInput(LPARAM lparam);
  bool HandleKeyboardEvent(WPARAM wparam, LPARAM lparam);

  static LRESULT CALLBACK KeyboardProc(int code, WPARAM wparam, LPARAM lparam);
  static MediaControlBridge* instance_;

  HWND window_ = nullptr;
  HHOOK keyboard_hook_ = nullptr;
  bool app_active_ = false;
  bool playing_ = false;
  std::unordered_map<int, DWORD> last_command_ticks_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_MEDIA_CONTROL_BRIDGE_H_
