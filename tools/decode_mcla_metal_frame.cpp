// Display tight-row raw GPU readback. Default: RGBA8 or RGBA16F by size.
// Optional final argument "r32f": normalized float depth -> grayscale PNG.
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>
#include <algorithm>
#include <bit>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <vector>
int main(int argc, char **argv) {
  if ((argc != 5 && argc != 6) ||
      (argc == 6 && std::strcmp(argv[5], "r32f") != 0)) {
    std::cerr << "usage: " << argv[0]
              << " input.bin width height output.png [r32f]\n";
    return 2;
  }
  const bool depth = argc == 6;
  const unsigned w = std::stoul(argv[2]), h = std::stoul(argv[3]);
  if (!w || !h || w > unsigned(std::numeric_limits<int>::max() / 4) ||
      h > unsigned(std::numeric_limits<int>::max())) return 2;
  const uint64_t pixels = uint64_t(w) * h;
  std::ifstream in(argv[1], std::ios::binary);
  std::vector<uint8_t> raw{std::istreambuf_iterator<char>(in), {}};
  if (depth ? raw.size() != pixels * 4
            : raw.size() != pixels * 4 && raw.size() != pixels * 8) return 3;
  const bool half = !depth && raw.size() == pixels * 8;
  std::vector<uint8_t> out(pixels * 4);
  size_t lit = 0, nonfinite = 0;
  double sum = 0;
  float minimum = std::numeric_limits<float>::infinity();
  float maximum = -std::numeric_limits<float>::infinity();
  if (depth) {
    for (size_t p = 0; p < pixels; ++p) {
      float v;
      std::memcpy(&v, raw.data() + p * sizeof(float), sizeof(float));
      if (!std::isfinite(v)) {
        ++nonfinite;
        v = 0;
      } else {
        // Preserve the original finite range for diagnosing invalid depth;
        // visualization alone is clamped to the normalized [0,1] interval.
        minimum = std::min(minimum, v);
        maximum = std::max(maximum, v);
      }
      const auto gray = uint8_t(std::clamp(v, 0.f, 1.f) * 255 + .5f);
      out[p * 4] = out[p * 4 + 1] = out[p * 4 + 2] = gray;
      out[p * 4 + 3] = 255;
      lit += gray != 0;
      sum += gray * 3;
    }
  } else {
    for (size_t i = 0; i < out.size(); ++i) {
      float v = raw[i] / 255.f;
      if (half) {
        uint16_t b;
        std::memcpy(&b, raw.data() + i * 2, 2);
        v = std::bit_cast<_Float16>(b);
      }
      if (!std::isfinite(v)) { ++nonfinite; v = 0; }
      out[i] = uint8_t(std::clamp(v, 0.f, 1.f) * 255 + .5f);
      if (i % 4 == 3) {
        out[i] = 255;
        lit += (out[i - 1] | out[i - 2] | out[i - 3]) != 0;
      } else sum += out[i];
    }
  }
  if (!stbi_write_png(argv[4], w, h, 4, out.data(), w * 4)) return 4;
  std::cout << "pixels=" << pixels << " nonblack=" << lit
            << " mean=" << sum / (pixels * 3) << " nonfinite=" << nonfinite
            << " half=" << half;
  if (depth) {
    std::cout << " format=r32f";
    if (nonfinite == pixels) std::cout << " min=none max=none";
    else std::cout << " min=" << minimum << " max=" << maximum;
  }
  std::cout << '\n';
}
