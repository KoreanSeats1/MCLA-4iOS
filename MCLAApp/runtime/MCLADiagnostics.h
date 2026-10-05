#pragma once
#include <atomic>

// Selected by the launcher before runtime startup; immutable during gameplay.
namespace mcla {
inline std::atomic<bool> diagnosticsEnabled{false};
inline bool DiagnosticsEnabled() noexcept {
    return diagnosticsEnabled.load(std::memory_order_relaxed);
}
inline void SetDiagnosticsEnabled(bool enabled) noexcept {
    diagnosticsEnabled.store(enabled, std::memory_order_relaxed);
}
}
