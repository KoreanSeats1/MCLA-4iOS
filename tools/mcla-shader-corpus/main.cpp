// Extract RAGE Xbox 360 shader containers from MCLA's encrypted RPF3 archives.
//
// This tool intentionally lives outside larecomp and the Theft4 project. It
// reads both trees as reference/dependency inputs without modifying either one.

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <unordered_set>
#include <vector>

#include <lzx.h>
#include <mspack.h>

#include "aes256.h"

namespace fs = std::filesystem;

namespace {

constexpr uint32_t kMagicRpf0 = 0x30465052u;  // RPF0, little endian.
constexpr uint32_t kMagicRpf3 = 0x33465052u;  // RPF3, little endian.
constexpr uint32_t kMagicRsc5 = 0x05435352u;  // RSC5, big endian.
constexpr uint32_t kXCompressMagic = 0x0FF512EFu;
constexpr uint64_t kTocOffset = 2048;
constexpr int kCryptRounds = 16;
constexpr size_t kShaderHeaderSize = 9 * sizeof(uint32_t);
constexpr size_t kLzxFrameSize = 32768;

uint32_t LoadLE32(const uint8_t* bytes) {
  return static_cast<uint32_t>(bytes[0]) |
         (static_cast<uint32_t>(bytes[1]) << 8) |
         (static_cast<uint32_t>(bytes[2]) << 16) |
         (static_cast<uint32_t>(bytes[3]) << 24);
}

uint64_t LoadLE64(const uint8_t* bytes) {
  return static_cast<uint64_t>(LoadLE32(bytes)) |
         (static_cast<uint64_t>(LoadLE32(bytes + 4)) << 32);
}

uint32_t LoadBE32(const uint8_t* bytes) {
  return (static_cast<uint32_t>(bytes[0]) << 24) |
         (static_cast<uint32_t>(bytes[1]) << 16) |
         (static_cast<uint32_t>(bytes[2]) << 8) |
         static_cast<uint32_t>(bytes[3]);
}

uint16_t LoadBE16(const uint8_t* bytes) {
  return static_cast<uint16_t>((static_cast<uint16_t>(bytes[0]) << 8) |
                               static_cast<uint16_t>(bytes[1]));
}

struct RpfEntry {
  uint32_t hash = 0;
  uint32_t size = 0;
  uint32_t offset_type = 0;
  uint32_t flag = 0;

  bool IsDirectory() const { return (offset_type & 0x80000000u) != 0; }
  uint64_t DataOffset() const {
    return static_cast<uint64_t>(offset_type >> 11) * 2048ull;
  }
};

bool ReadAt(std::ifstream& stream, uint64_t offset, size_t size,
            std::vector<uint8_t>& output) {
  if (offset > static_cast<uint64_t>(std::numeric_limits<std::streamoff>::max()) ||
      size > static_cast<size_t>(std::numeric_limits<std::streamsize>::max())) {
    return false;
  }
  output.assign(size, 0);
  stream.clear();
  stream.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
  if (!stream) return false;
  if (size != 0) {
    stream.read(reinterpret_cast<char*>(output.data()),
                static_cast<std::streamsize>(size));
    if (stream.gcount() != static_cast<std::streamsize>(size)) return false;
  }
  return true;
}

bool ReadToc(std::ifstream& archive, std::vector<RpfEntry>& entries,
             std::string& error) {
  std::vector<uint8_t> header;
  if (!ReadAt(archive, 0, 20, header)) {
    error = "cannot read RPF header";
    return false;
  }
  const uint32_t magic = LoadLE32(header.data());
  const uint32_t toc_size = LoadLE32(header.data() + 4);
  const uint32_t count = LoadLE32(header.data() + 8);
  if (magic < kMagicRpf0 || magic > kMagicRpf3) {
    error = "not an RPF0-RPF3 archive";
    return false;
  }
  if (toc_size < static_cast<uint64_t>(count) * 16 || toc_size > 256u * 1024u * 1024u) {
    error = "invalid RPF table size";
    return false;
  }

  std::vector<uint8_t> toc;
  if (!ReadAt(archive, kTocOffset, toc_size, toc)) {
    error = "cannot read RPF table";
    return false;
  }
  mc::modloader::Aes256EcbDecrypt(toc.data(), toc.size(),
                                  mc::modloader::kRpfKey, kCryptRounds);

  entries.resize(count);
  for (uint32_t i = 0; i < count; ++i) {
    const uint8_t* record = toc.data() + static_cast<size_t>(i) * 16;
    entries[i] = {LoadLE32(record), LoadLE32(record + 4),
                  LoadLE32(record + 8), LoadLE32(record + 12)};
  }
  return true;
}

struct ReadStream {
  const uint8_t* cursor = nullptr;
  const uint8_t* end = nullptr;
  size_t frame_remaining = 0;
  bool malformed = false;
};

struct WriteStream {
  uint8_t* cursor = nullptr;
  size_t remaining = 0;
};

int MspackRead(mspack_file* file, void* destination, int requested) {
  auto* stream = reinterpret_cast<ReadStream*>(file);
  if (!stream || requested < 0 || (!destination && requested != 0) || stream->malformed) {
    return -1;
  }
  if (stream->frame_remaining == 0) {
    if (static_cast<size_t>(stream->end - stream->cursor) < 2) return 0;
    uint32_t frame_size = LoadBE16(stream->cursor);
    stream->cursor += 2;

    // XCompress optionally prefixes a frame with 0xFFxx plus a 24-bit
    // uncompressed-size marker. The retail RSC5 resources normally use the
    // compact two-byte form, but accepting both keeps this scanner reusable.
    if ((frame_size & 0xFF00u) == 0xFF00u) {
      if (static_cast<size_t>(stream->end - stream->cursor) < 3) {
        stream->malformed = true;
        return -1;
      }
      stream->cursor += 1;
      frame_size = LoadBE16(stream->cursor);
      stream->cursor += 2;
    }
    if (frame_size == 0 || frame_size > static_cast<size_t>(stream->end - stream->cursor)) {
      stream->malformed = true;
      return -1;
    }
    stream->frame_remaining = frame_size;
  }

  const size_t count = std::min({stream->frame_remaining,
                                 static_cast<size_t>(requested),
                                 static_cast<size_t>(stream->end - stream->cursor)});
  if (count != 0) {
    std::memcpy(destination, stream->cursor, count);
    stream->cursor += count;
    stream->frame_remaining -= count;
  }
  return static_cast<int>(count);
}

int MspackWrite(mspack_file* file, void* source, int requested) {
  auto* stream = reinterpret_cast<WriteStream*>(file);
  if (!stream || requested < 0 || (!source && requested != 0)) return -1;
  const size_t count = std::min(stream->remaining, static_cast<size_t>(requested));
  if (count != 0) {
    std::memcpy(stream->cursor, source, count);
    stream->cursor += count;
    stream->remaining -= count;
  }
  return static_cast<int>(count);
}

void* MspackAlloc(mspack_system*, size_t size) { return std::calloc(1, size); }
void MspackFree(void* pointer) { std::free(pointer); }
void MspackCopy(void* source, void* destination, size_t size) {
  std::memcpy(destination, source, size);
}

bool DecompressRsc5(const std::vector<uint8_t>& file,
                    std::vector<uint8_t>& output,
                    uint32_t& resource_type,
                    int& successful_window_bits) {
  if (file.size() < 20 || LoadBE32(file.data()) != kMagicRsc5 ||
      LoadBE32(file.data() + 12) != kXCompressMagic) {
    return false;
  }
  resource_type = LoadBE32(file.data() + 4);
  const uint32_t flag = LoadBE32(file.data() + 8);
  const uint32_t virtual_size =
      (flag & 0x7FFu) << (((flag >> 11) & 0xFu) + 8);
  const uint32_t physical_size =
      ((flag >> 15) & 0x7FFu) << (((flag >> 26) & 0xFu) + 8);
  const uint64_t output_size = static_cast<uint64_t>(virtual_size) + physical_size;
  size_t payload_size = LoadBE32(file.data() + 16);
  payload_size = std::min(payload_size, file.size() - 20);
  if (virtual_size == 0 || output_size > 512ull * 1024ull * 1024ull || payload_size < 2) {
    return false;
  }

  output.assign(static_cast<size_t>(output_size), 0);
  for (int window_bits : {17, 16, 18, 19, 20, 21, 15}) {
    ReadStream input{file.data() + 20, file.data() + 20 + payload_size};
    WriteStream destination{output.data(), output.size()};
    mspack_system system{};
    system.read = MspackRead;
    system.write = MspackWrite;
    system.alloc = MspackAlloc;
    system.free = MspackFree;
    system.copy = MspackCopy;

    lzxd_stream* decoder = lzxd_init(
        &system, reinterpret_cast<mspack_file*>(&input),
        reinterpret_cast<mspack_file*>(&destination), window_bits, 0,
        static_cast<int>(kLzxFrameSize), static_cast<off_t>(output.size()), 0);
    if (!decoder) continue;
    const int result = lzxd_decompress(decoder, static_cast<off_t>(output.size()));
    lzxd_free(decoder);
    if (result == MSPACK_ERR_OK && destination.remaining == 0 && !input.malformed) {
      successful_window_bits = window_bits;
      return true;
    }
    std::fill(output.begin(), output.end(), 0);
  }
  output.clear();
  return false;
}

std::string Hex32(uint32_t value) {
  std::ostringstream stream;
  stream << std::hex << std::setfill('0') << std::setw(8) << value;
  return stream.str();
}

size_t ExtractShaderContainers(const std::vector<uint8_t>& bytes,
                               const fs::path& output_directory,
                               const std::string& archive_stem,
                               size_t entry_index,
                               uint32_t entry_hash,
                               size_t& serial) {
  size_t found = 0;
  for (size_t offset = 0; bytes.size() >= kShaderHeaderSize &&
                          offset <= bytes.size() - kShaderHeaderSize;) {
    const uint8_t* container = bytes.data() + offset;
    const uint32_t flags = LoadBE32(container);
    const uint64_t virtual_size = LoadBE32(container + 4);
    const uint64_t physical_size = LoadBE32(container + 8);
    const uint64_t total_size = virtual_size + physical_size;
    if ((flags & 0xFFFFFF00u) == 0x102A1100u &&
        total_size >= kShaderHeaderSize && total_size <= bytes.size() - offset &&
        LoadBE32(container + 28) == 0 && LoadBE32(container + 32) == 0) {
      std::ostringstream filename;
      filename << archive_stem << "_e" << std::setfill('0') << std::setw(6)
               << entry_index << "_h" << Hex32(entry_hash) << "_o" << std::hex
               << offset << "_n" << std::dec << std::setw(6) << serial++ << ".ragefx";
      std::ofstream output(output_directory / filename.str(), std::ios::binary);
      output.write(reinterpret_cast<const char*>(container),
                   static_cast<std::streamsize>(total_size));
      if (!output) {
        std::cerr << "error: cannot write " << filename.str() << '\n';
        std::exit(EXIT_FAILURE);
      }
      ++found;
      offset += static_cast<size_t>(total_size);
    } else {
      ++offset;
    }
  }
  return found;
}

struct Stats {
  size_t entries = 0;
  size_t files = 0;
  size_t raw_containers = 0;
  size_t rsc5_files = 0;
  size_t decompressed_files = 0;
  size_t decompression_failures = 0;
  size_t decompressed_containers = 0;
  uint64_t raw_bytes = 0;
  uint64_t decompressed_bytes = 0;
  size_t live_ucode_matches = 0;
};

struct UcodeNeedle {
  uint64_t runtime_hash = 0;
  bool pixel = false;
  std::vector<uint8_t> bytes;
  bool found = false;
};

bool LoadUcodeNeedles(const fs::path& xsh_path, std::vector<UcodeNeedle>& needles,
                      std::string& error) {
  std::ifstream input(xsh_path, std::ios::binary | std::ios::ate);
  if (!input) {
    error = "cannot open XSH cache";
    return false;
  }
  const std::streamsize file_size = input.tellg();
  input.seekg(0);
  if (file_size < 8) {
    error = "XSH cache is truncated";
    return false;
  }
  std::vector<uint8_t> bytes(static_cast<size_t>(file_size));
  if (!input.read(reinterpret_cast<char*>(bytes.data()), file_size) ||
      std::memcmp(bytes.data(), "XESH", 4) != 0) {
    error = "XSH cache has an invalid header";
    return false;
  }

  std::vector<UcodeNeedle> pixels;
  std::vector<UcodeNeedle> vertices;
  for (size_t offset = 8; offset + 12 <= bytes.size();) {
    const uint64_t hash = LoadLE64(bytes.data() + offset);
    const uint32_t packed = LoadLE32(bytes.data() + offset + 8);
    offset += 12;
    const size_t dword_count = packed & 0x7FFFFFFFu;
    const bool pixel = (packed >> 31) != 0;
    const size_t byte_count = dword_count * 4;
    if (dword_count == 0 || byte_count > bytes.size() - offset) {
      error = "XSH cache has a truncated shader record";
      return false;
    }
    UcodeNeedle needle;
    needle.runtime_hash = hash;
    needle.pixel = pixel;
    needle.bytes.assign(bytes.begin() + static_cast<std::ptrdiff_t>(offset),
                        bytes.begin() + static_cast<std::ptrdiff_t>(offset + byte_count));
    (pixel ? pixels : vertices).push_back(std::move(needle));
    offset += byte_count;
  }

  // Runtime pixel microcode is not patched by the D3D vertex declaration, so
  // exact matching is a strong way to locate MCLA's otherwise-undocumented
  // container inside decoded archives. A small largest-first sample avoids
  // multiplying a multi-gigabyte scan by every warm-cache record.
  auto by_size = [](const UcodeNeedle& a, const UcodeNeedle& b) {
    return a.bytes.size() > b.bytes.size();
  };
  std::sort(pixels.begin(), pixels.end(), by_size);
  std::sort(vertices.begin(), vertices.end(), by_size);
  const size_t pixel_count = std::min<size_t>(pixels.size(), 24);
  const size_t vertex_count = std::min<size_t>(vertices.size(), 8);
  needles.insert(needles.end(),
                 std::make_move_iterator(pixels.begin()),
                 std::make_move_iterator(pixels.begin() + pixel_count));
  needles.insert(needles.end(),
                 std::make_move_iterator(vertices.begin()),
                 std::make_move_iterator(vertices.begin() + vertex_count));
  std::cout << "loaded " << needles.size() << " live shader needles from "
            << xsh_path.filename().string() << " (" << pixel_count << " pixel, "
            << vertex_count << " vertex)" << std::endl;
  return true;
}

size_t FindLiveUcode(const std::vector<uint8_t>& haystack,
                     const fs::path& output_directory,
                     const std::string& archive_stem,
                     size_t entry_index,
                     bool decoded,
                     std::vector<UcodeNeedle>& needles) {
  size_t matches = 0;
  for (UcodeNeedle& needle : needles) {
    if (needle.found || needle.bytes.size() > haystack.size()) continue;
    const auto found = std::search(haystack.begin(), haystack.end(),
                                   needle.bytes.begin(), needle.bytes.end());
    if (found == haystack.end()) continue;
    needle.found = true;
    ++matches;
    const size_t offset = static_cast<size_t>(found - haystack.begin());
    constexpr size_t kContext = 128 * 1024;
    const size_t begin = offset > kContext ? offset - kContext : 0;
    const size_t end = std::min(haystack.size(), offset + needle.bytes.size() + kContext);
    std::ostringstream filename;
    filename << archive_stem << "_e" << std::setfill('0') << std::setw(6)
             << entry_index << '_' << (decoded ? "decoded" : "raw") << "_live_"
             << std::hex << std::setw(16) << needle.runtime_hash << "_at_" << offset
             << ".context.bin";
    std::ofstream output(output_directory / filename.str(), std::ios::binary);
    output.write(reinterpret_cast<const char*>(haystack.data() + begin),
                 static_cast<std::streamsize>(end - begin));
    std::cout << "  live " << (needle.pixel ? "pixel" : "vertex")
              << " ucode match: entry=" << entry_index << " offset=0x" << std::hex
              << offset << " hash=" << needle.runtime_hash << std::dec
              << " context=" << filename.str() << std::endl;
  }
  return matches;
}

bool ProcessArchive(const fs::path& archive_path,
                    const fs::path& output_directory,
                    size_t& serial,
                    Stats& stats,
                    std::vector<UcodeNeedle>& needles) {
  std::ifstream archive(archive_path, std::ios::binary);
  if (!archive) {
    std::cerr << "error: cannot open " << archive_path << '\n';
    return false;
  }

  std::vector<RpfEntry> entries;
  std::string error;
  if (!ReadToc(archive, entries, error)) {
    std::cerr << "error: " << archive_path.filename().string() << ": " << error << '\n';
    return false;
  }
  stats.entries += entries.size();
  std::cout << archive_path.filename().string() << ": " << entries.size()
            << " RPF entries" << std::endl;

  size_t archive_containers = 0;
  size_t archive_resources = 0;
  size_t archive_decompressed = 0;
  size_t archive_failures = 0;
  const std::string stem = archive_path.stem().string();
  for (size_t i = 0; i < entries.size(); ++i) {
    const RpfEntry& entry = entries[i];
    if (entry.IsDirectory() || entry.size == 0) continue;
    ++stats.files;
    stats.raw_bytes += entry.size;

    std::vector<uint8_t> raw;
    if (!ReadAt(archive, entry.DataOffset(), entry.size, raw)) {
      std::cerr << "warning: cannot read entry " << i << " at 0x" << std::hex
                << entry.DataOffset() << std::dec << '\n';
      continue;
    }
    const size_t raw_found = ExtractShaderContainers(
        raw, output_directory, stem, i, entry.hash, serial);
    stats.raw_containers += raw_found;
    archive_containers += raw_found;
    stats.live_ucode_matches += FindLiveUcode(
        raw, output_directory, stem, i, false, needles);

    if (raw.size() < 20 || LoadBE32(raw.data()) != kMagicRsc5) continue;
    ++stats.rsc5_files;
    ++archive_resources;
    std::vector<uint8_t> decompressed;
    uint32_t resource_type = 0;
    int window_bits = 0;
    if (!DecompressRsc5(raw, decompressed, resource_type, window_bits)) {
      ++stats.decompression_failures;
      ++archive_failures;
      continue;
    }
    ++stats.decompressed_files;
    ++archive_decompressed;
    stats.decompressed_bytes += decompressed.size();
    const size_t decoded_found = ExtractShaderContainers(
        decompressed, output_directory, stem, i, entry.hash, serial);
    stats.decompressed_containers += decoded_found;
    archive_containers += decoded_found;
    stats.live_ucode_matches += FindLiveUcode(
        decompressed, output_directory, stem, i, true, needles);

    if ((archive_decompressed % 250) == 0) {
      std::cout << "  decoded " << archive_decompressed << "/" << archive_resources
                << " RSC5 resources, found " << archive_containers
                << " shader containers (window bits " << window_bits << ")"
                << std::endl;
    }
  }
  std::cout << "  complete: resources=" << archive_resources
            << " decoded=" << archive_decompressed
            << " failed=" << archive_failures
            << " containers=" << archive_containers << std::endl;
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) {
    std::cerr << "usage: mcla_shader_corpus <output-directory> [--xsh cache.xsh] "
                 "<archive.rpf> [archive.rpf ...]\n";
    return EXIT_FAILURE;
  }

  const fs::path output_directory = fs::absolute(argv[1]);
  std::error_code filesystem_error;
  fs::create_directories(output_directory, filesystem_error);
  if (filesystem_error) {
    std::cerr << "error: cannot create " << output_directory << ": "
              << filesystem_error.message() << '\n';
    return EXIT_FAILURE;
  }

  Stats stats;
  size_t serial = 0;
  int first_archive = 2;
  std::vector<UcodeNeedle> needles;
  if (first_archive + 1 < argc && std::string(argv[first_archive]) == "--xsh") {
    std::string error;
    if (!LoadUcodeNeedles(fs::absolute(argv[first_archive + 1]), needles, error)) {
      std::cerr << "error: " << error << '\n';
      return EXIT_FAILURE;
    }
    first_archive += 2;
  }
  if (first_archive >= argc) {
    std::cerr << "error: no RPF archive supplied\n";
    return EXIT_FAILURE;
  }
  for (int i = first_archive; i < argc; ++i) {
    if (!ProcessArchive(fs::absolute(argv[i]), output_directory, serial, stats, needles)) {
      return EXIT_FAILURE;
    }
  }

  std::cout << "summary: entries=" << stats.entries
            << " files=" << stats.files
            << " raw-bytes=" << stats.raw_bytes
            << " rsc5=" << stats.rsc5_files
            << " decoded=" << stats.decompressed_files
            << " decode-failures=" << stats.decompression_failures
            << " decoded-bytes=" << stats.decompressed_bytes
            << " raw-containers=" << stats.raw_containers
            << " decoded-containers=" << stats.decompressed_containers
            << " live-ucode-matches=" << stats.live_ucode_matches
            << " output-files=" << serial << '\n';
  return stats.decompressed_containers + stats.raw_containers +
                     stats.live_ucode_matches ==
                 0
             ? EXIT_FAILURE
             : EXIT_SUCCESS;
}
