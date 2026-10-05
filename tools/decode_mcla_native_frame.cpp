// Decode the renderer's completed, fenced RGBA8/BGRA8 GPU readback artifacts.
#include <nlohmann/json.hpp>
#include <zstd.h>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>
#include <algorithm>
#include <bit>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  unsigned decoded = 0;
  for (const auto& entry : std::filesystem::directory_iterator(argv[1])) {
    if (entry.path().extension() != ".json") continue;
    nlohmann::json j; std::ifstream(entry.path()) >> j;
    if (!j.value("gpu_completed", false)) continue;
    const bool depth = j.value("aspect", 0) == 2;
    if (!depth && j.value("aspect", 0) != 1) continue;
    const unsigned format = j.at("format");
    if (format != 37 && format != 44 && format != 97 && !(depth && format == 130)) continue;
    const unsigned width = j.at("width"), height = j.at("height");
    const uint64_t bytes = uint64_t(width) * height * (format == 97 ? 8 : 4);
    if (!width || !height || bytes > 64*1024*1024 || bytes != j.at("bytes")) return 3;
    const auto filename = std::filesystem::path(j.at("binary").get<std::string>()).filename();
    std::ifstream input(entry.path().parent_path() / filename, std::ios::binary);
    std::vector<uint8_t> compressed{std::istreambuf_iterator<char>(input), {}};
    std::vector<uint8_t> raw(bytes), rgba(uint64_t(width)*height*4);
    if (ZSTD_decompress(raw.data(), raw.size(), compressed.data(), compressed.size()) != bytes)
      return 4;
    if (depth) {
      float low=INFINITY, high=-INFINITY; size_t invalid=0;
      for(size_t i=0;i<raw.size();i+=4){
        float v;std::memcpy(&v,raw.data()+i,4);
        if(std::isfinite(v)){low=std::min(low,v);high=std::max(high,v);}else ++invalid;
      }
      for(size_t i=0;i<raw.size();i+=4){
        float v;std::memcpy(&v,raw.data()+i,4);
        const uint8_t c=std::isfinite(v)?uint8_t(std::clamp(high>low?(v-low)/(high-low):v,0.f,1.f)*255.f):255;
        rgba[i]=rgba[i+1]=rgba[i+2]=c;rgba[i+3]=255;
      }
      std::cout << entry.path().filename() << " depth=" << low << ".." << high
                << " nonfinite=" << invalid << " (display normalized to depth range)\n";
    } else if (format == 97) {
      float low = INFINITY, high = -INFINITY;
      size_t invalid = 0;
      for (size_t i = 0; i < rgba.size(); ++i) {
        uint16_t bits; std::memcpy(&bits, raw.data()+i*2, 2);
        const float v = float(std::bit_cast<_Float16>(bits));
        if (i%4 != 3 && std::isfinite(v)) {low=std::min(low,v);high=std::max(high,v);}
        if (!std::isfinite(v)) ++invalid;
        rgba[i] = std::isfinite(v) ? uint8_t(std::clamp(v, 0.f, 1.f)*255.f+0.5f) : 255;
      }
      std::cout << entry.path().filename() << " raw-float-rgb=" << low << ".." << high
                << " nonfinite-components=" << invalid << " (display clamped to [0,1])\n";
    } else rgba=std::move(raw);
    uint64_t nonblack = 0, sum = 0;
    uint8_t minimum = 255, maximum = 0;
    for (size_t i = 0; i < rgba.size(); i += 4) {
      if (format == 44) std::swap(rgba[i], rgba[i+2]);
      nonblack += bool(rgba[i] | rgba[i+1] | rgba[i+2]);
      for (unsigned c = 0; c < 3; ++c) {
        minimum = std::min(minimum, rgba[i+c]); maximum = std::max(maximum, rgba[i+c]);
        sum += rgba[i+c];
      }
      // Display RGB even if the composited frame's unused alpha plane is zero.
      rgba[i+3] = 255;
    }
    auto output = entry.path(); output.replace_extension(".png");
    if (!stbi_write_png(output.c_str(), width, height, 4, rgba.data(), width * 4)) return 5;
    std::cout << output << " rgb-range=" << unsigned(minimum) << ".." << unsigned(maximum)
              << " rgb-mean=" << double(sum)/(width*height*3.0)
              << " nonblack=" << nonblack << '/' << width*height << '\n';
    ++decoded;
  }
  return decoded ? 0 : 6;
}
