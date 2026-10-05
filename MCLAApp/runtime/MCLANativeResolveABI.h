#pragma once

#include <cstdint>
#include <optional>
#include <span>

namespace mcla::native {

// Verified against MCLA CE D3DDevice_Resolve (0x82420BA8): the
// 368-byte prologue loads old-SP+92 and old-SP+100 as its two trailing
// arguments. EndTiling's call sites write exactly those slots.
inline constexpr uint32_t kResolveStencilStackOffset = 0x5C;
inline constexpr uint32_t kResolveParametersStackOffset = 0x64;
inline constexpr uint32_t kResolveStackBytes = 0x68;

inline constexpr bool ResolveUsesClearParameters(uint32_t flags, uint32_t parameters) {
  return parameters != 0 && (flags & 0x300u) != 0;
}

struct ResolveStackArguments {
  uint32_t stencil;
  uint32_t parameters;
};

inline std::optional<ResolveStackArguments> DecodeResolveStack(
    std::span<const uint8_t> stack) {
  if (stack.size() < kResolveStackBytes) return std::nullopt;
  const auto word = [&](uint32_t offset) {
    return uint32_t(stack[offset]) << 24 | uint32_t(stack[offset + 1]) << 16 |
           uint32_t(stack[offset + 2]) << 8 | uint32_t(stack[offset + 3]);
  };
  return ResolveStackArguments{word(kResolveStencilStackOffset),
                               word(kResolveParametersStackOffset)};
}

// This is a selector, not a wrapping two-bit index: 5..7 are invalid.
inline constexpr std::optional<uint32_t> ResolveSurfaceOffset(uint32_t flags) {
  const uint32_t index = flags & 7u;
  if (index == 4) return 12456;
  if (index < 4) return 12440 + index * 4;
  return std::nullopt;
}

}  // namespace mcla::native
