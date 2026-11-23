#pragma once

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

// UIKit host identifiers are VM-local. Keep the VM namespace outside the JS
// identifier, without changing existing bundled JavaScript or retaining a closed VM.
template <typename Runtime>
class HanlinExpoSessionRuntimeRegistry final {
 public:
  void bind(const std::string& sessionID, const std::shared_ptr<Runtime>& runtime) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (runtime) {
      runtimes_[sessionID] = runtime;
    } else {
      runtimes_.erase(sessionID);
    }
  }

  std::shared_ptr<Runtime> find(const std::string& sessionID) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto entry = runtimes_.find(sessionID);
    if (entry == runtimes_.end()) return nullptr;
    auto runtime = entry->second.lock();
    if (!runtime) runtimes_.erase(entry);
    return runtime;
  }

  void clear(const std::string& sessionID) {
    std::lock_guard<std::mutex> lock(mutex_);
    runtimes_.erase(sessionID);
  }

  void clearAll() {
    std::lock_guard<std::mutex> lock(mutex_);
    runtimes_.clear();
  }

 private:
  std::mutex mutex_;
  std::unordered_map<std::string, std::weak_ptr<Runtime>> runtimes_;
};
