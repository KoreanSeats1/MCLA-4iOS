#include "../MCLAApp/runtime/MCLAMetalRasterState.h"
#include <cassert>
#include <cstdio>
#include <limits>

int main() {
  using mcla::metal::GuestRasterDepthBias;
  using mcla::metal::GuestCullMode;

  assert(GuestCullMode(0, 4) == 0);
  assert(GuestCullMode(1, 4) == 1);
  assert(GuestCullMode(2, 4) == 2);
  assert(GuestCullMode(3, 4) == 3);
  assert(GuestCullMode(3, 8) == 0);
  constexpr uint32_t front = 1u << 11, back = 1u << 12;
  constexpr float quantum = 1.f / float((1u << 24) - 1u);
  auto b = GuestRasterDepthBias(front, 0, true, 16, quantum, 32, -quantum);
  assert(b.constant == 1 && b.slope == 1);
  b = GuestRasterDepthBias(back, 0, true, 16, quantum, 32, -quantum);
  assert(b.constant == -1 && b.slope == 2);
  b = GuestRasterDepthBias(front | back | 1u, 0, true, 16, quantum, 32, -quantum);
  assert(b.constant == -1 && b.slope == 2);  // Front culled: prefer back.
  b = GuestRasterDepthBias(front | back | 2u, 0, true, 16, quantum, 32, -quantum);
  assert(b.constant == 1 && b.slope == 1);
  b = GuestRasterDepthBias(front | back, 0, true, 0, 0, 32, -quantum);
  assert(b.constant == -1 && b.slope == 2);  // Zero front falls back to back.
  b = GuestRasterDepthBias(front, 1, true, 0, 1.f / float(1u << 21), 0, 0);
  assert(b.constant == 8 && b.slope == 0);  // Guest float24 has 3 fewer bits.
  b = GuestRasterDepthBias(front, 0, true, 0, quantum * .01f, 0, 0);
  assert(b.constant == 1);  // Preserve nonzero offsets below one unit.
  const auto zero = [](mcla::metal::RasterDepthBias v) {
    assert(v.constant == 0 && v.slope == 0);
  };
  zero(GuestRasterDepthBias(0, 0, true, 16, quantum, 32, -quantum));
  zero(GuestRasterDepthBias(front | back | 3u, 0, true, 16, quantum, 32, -quantum));
  zero(GuestRasterDepthBias(front, 0, false, 16, quantum, 32, -quantum));
  zero(GuestRasterDepthBias(front, 2, true, 16, quantum, 32, -quantum));
  zero(GuestRasterDepthBias(front, 0, true, std::numeric_limits<float>::quiet_NaN(), quantum, 0, 0));
  zero(GuestRasterDepthBias(front, 0, true, 0, std::numeric_limits<float>::infinity(), 0, 0));
  zero(GuestRasterDepthBias(front, 0, true, 1e5f, quantum, 0, 0));
  zero(GuestRasterDepthBias(front, 0, true, 0, 1e4f, 0, 0));  // Overflow-safe.
  // Disabled state after an enabled draw must explicitly reset both fields.
  b = GuestRasterDepthBias(0, 0, true, 16, quantum, 32, -quantum);
  zero(b);
  std::puts("PASS: guest polygon offset faces, units, disable/reset, and invalid values");
}
