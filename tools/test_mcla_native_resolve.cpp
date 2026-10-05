#include "../MCLAApp/runtime/MCLANativeResolveABI.h"

#include <array>
#include <cassert>
#include <iostream>

// Host-side checks for the MCLA CE boundary, not a GPU rendering test.
int main() {
  using namespace mcla::native;
  std::array<uint8_t, 0x68> stack{};
  const auto put = [&](uint32_t offset, uint32_t value) {
    for (uint32_t i = 0; i < 4; ++i) {
      stack[offset + i] = uint8_t(value >> ((3 - i) * 8));
    }
  };

  // Literal offsets are independently verified in CE's generated Resolve
  // prologue (new-SP+460/468 after allocating 368 bytes). Keep a different
  // value in the previous, incorrect slot so this catches that regression.
  put(0x54, 0xBAD0BAD0);
  put(0x5C, 0x01234567);
  put(0x64, 0x829ABCDE);
  const auto arguments = DecodeResolveStack(stack);
  assert(arguments && arguments->stencil == 0x01234567);
  assert(arguments->parameters == 0x829ABCDE);
  for (size_t length = 0; length < stack.size(); ++length) {
    assert(!DecodeResolveStack(std::span<const uint8_t>(stack).first(length)));
  }
  stack.fill(0);
  const auto defaults = DecodeResolveStack(stack);
  assert(defaults && !defaults->stencil && !defaults->parameters);
  assert(!ResolveUsesClearParameters(0x70, 0x829ABCDE));
  assert(!ResolveUsesClearParameters(0x300, 0));
  for (uint32_t clear : {0x100u, 0x200u, 0x300u}) {
    assert(ResolveUsesClearParameters(clear | 0x70, 0x829ABCDE));
  }

  for (uint32_t flags : {0u, 0x70u, 0x300u, 0xFFFFFFF8u}) {
    for (uint32_t index = 0; index < 4; ++index) {
      assert(ResolveSurfaceOffset(flags | index) == 12440 + index * 4);
    }
    assert(ResolveSurfaceOffset(flags | 4) == 12456);
    for (uint32_t index = 5; index < 8; ++index) {
      assert(!ResolveSurfaceOffset(flags | index));
    }
  }
  std::cout << "PASS: MCLA CE resolve stack offsets, big-endian decoding, "
               "truncated inputs, optional defaults, and surface selectors\n";
}
