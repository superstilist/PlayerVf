// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "video_output_manager.h"

VideoOutputManager::VideoOutputManager(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

void VideoOutputManager::Create(
    int64_t handle,
    VideoOutputConfiguration configuration,
    std::function<void(int64_t, int64_t, int64_t)> texture_update_callback) {
  uint64_t generation = 0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    generation = ++generations_[handle];
  }
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (generations_[handle] != generation) {
      return;
    }
    auto instance = std::make_unique<VideoOutput>(
        handle, configuration, registrar_, thread_pool_.get());
    instance->SetTextureUpdateCallback(texture_update_callback);
    video_outputs_[handle] = std::move(instance);
  }).detach();
}

void VideoOutputManager::SetSize(int64_t handle,
                                 std::optional<int64_t> width,
                                 std::optional<int64_t> height) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) != video_outputs_.end()) {
      video_outputs_[handle]->SetSize(width, height);
    }
  }).detach();
}

void VideoOutputManager::Dispose(int64_t handle) {
  uint64_t generation = 0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    generation = generations_[handle];
  }
  std::thread([=]() {
    std::unique_ptr<VideoOutput> instance;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (generations_[handle] != generation) {
        return;
      }
      auto it = video_outputs_.find(handle);
      if (it != video_outputs_.end()) {
        instance = std::move(it->second);
        video_outputs_.erase(it);
      }
      generations_.erase(handle);
    }
    // Destroy outside |mutex_|. VideoOutput destruction waits on Flutter and
    // the render thread pool, so keeping the manager lock held here can stall
    // create/resize calls and make stale teardown races much easier to hit.
    instance.reset();
  }).detach();
}

VideoOutputManager::~VideoOutputManager() {
  std::lock_guard<std::mutex> lock(mutex_);
  // |VideoOutput| destructor will do the relevant cleanup.
  video_outputs_.clear();
  generations_.clear();
  // This destructor is only called when the plugin is being destroyed i.e. the
  // application is being closed. So, doesn't really matter on the other hand.
}
