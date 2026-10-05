#pragma once
#include "MCLADrawReuse.h"

namespace mcla::metal {
// Ordinary Metal draws read fetch descriptors, the control register block,
// shader constants and the remapped fields below. Full snapshots remain the
// default for clears, other backends and diagnostics. Never reuse guest bytes
// by pointer identity: every live field is refreshed on every draw.
inline void CopyCanonicalDrawState(uint8_t* dst, const uint8_t* src, size_t size,
                                  const uint64_t* vertexConstants,
                                  const uint64_t* pixelConstants,
                                  bool compact) {
  auto copy = [&](size_t out, size_t in, size_t bytes) {
    std::memcpy(dst + out, src + in, bytes);
  };
  if (compact) {
    copy(1152, 1152, 26 * 24);
    // Includes booleans, integer constants, raster/blend/depth controls,
    // scissor, pixel-center control and polygon-offset canonical slots.
    copy(10112, 10112, 10848 - 10112);
  } else {
    copy(0, 0, 1920);
    copy(10112, 10112, size - 10112);
  }
  CopyConstantRegisters(dst + 1920, src + 1920, vertexConstants);
  CopyConstantRegisters(dst + 6016, src + 6016, pixelConstants);
  copy(12428,12436,4); copy(12432,12440,16); copy(12448,12456,4);
  copy(12452,12460,17*4); copy(12536,12544,26*4);
  copy(11844,11852,4); copy(11848,11856,4); copy(11868,11876,8);
  copy(12640,12648,24); copy(12668,12676,16);
  copy(10832,11196,4); copy(10836,11192,4);
  copy(10840,11204,4); copy(10844,11200,4);
  copy(10436,10424,8);
  const uint32_t zero = 0;
  std::memcpy(dst + 10432, &zero, 4);
  // Canonical state retains guest big-endian representation.
  const uint8_t one[4] = {0,0,0,1};
  std::memcpy(dst + 11848, one, 4);
}
} // namespace mcla::metal
