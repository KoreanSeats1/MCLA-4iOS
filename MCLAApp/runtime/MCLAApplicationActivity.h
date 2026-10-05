#pragma once
#include <atomic>
#include <condition_variable>
#include <mutex>

namespace mcla::metal {
class ApplicationActivity {
  std::atomic<bool> active_{true};
  std::mutex mutex_;
  std::condition_variable changed_;
public:
  void Set(bool active) {
    { std::lock_guard lock(mutex_); active_.store(active,std::memory_order_release); }
    if (active) changed_.notify_all();
  }
  bool IsActive() const { return active_.load(std::memory_order_acquire); }
  bool Wait(bool mayBlock=true) {
    if (active_.load(std::memory_order_acquire)) return true;
    if (!mayBlock) return false; // Never block UIKit's notification thread.
    std::unique_lock lock(mutex_);
    changed_.wait(lock,[&]{return active_.load(std::memory_order_acquire);});
    return true;
  }
};
} // namespace mcla::metal
