#include "../MCLAApp/runtime/MCLAPackedTexture.h"
#include <cassert>
#include <cmath>
#include <cstdio>
int main() {
    for (unsigned value = 0; value < 65536; ++value) {
        uint8_t source[] = {uint8_t(value), uint8_t(value >> 8)}, rgba[4];
        mcla::metal::DecodeR5G5B5A1(source, rgba);
        for (unsigned channel = 0; channel < 3; ++channel) {
            double normalized = double((value >> (channel * 5)) & 31) / 31;
            assert(rgba[channel] == std::lround(normalized * 255));
        }
        assert(rgba[3] == ((value >> 15) ? 255 : 0));
    }
    puts("65536 packed texels: RGB normalization and one-bit alpha passed");
}
