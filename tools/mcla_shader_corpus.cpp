#include "shader_identity.h"

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

uint32_t LoadLe32(const uint8_t* data) {
    return uint32_t(data[0]) | uint32_t(data[1]) << 8 |
           uint32_t(data[2]) << 16 | uint32_t(data[3]) << 24;
}

uint64_t LoadLe64(const uint8_t* data) {
    return uint64_t(LoadLe32(data)) | uint64_t(LoadLe32(data + 4)) << 32;
}

std::string Hex64(uint64_t value) {
    std::ostringstream stream;
    stream << std::hex << std::uppercase << std::setw(16)
           << std::setfill('0') << value;
    return stream.str();
}

bool ReadFile(const fs::path& path, std::vector<uint8_t>& bytes) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) {
        return false;
    }
    const std::streamsize size = input.tellg();
    if (size < 0) {
        return false;
    }
    input.seekg(0);
    bytes.resize(size_t(size));
    return size == 0 ||
           bool(input.read(reinterpret_cast<char*>(bytes.data()), size));
}

bool WriteFile(const fs::path& path, const uint8_t* bytes, size_t size) {
    std::error_code error;
    fs::create_directories(path.parent_path(), error);
    if (error) {
        return false;
    }
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) {
        return false;
    }
    output.write(reinterpret_cast<const char*>(bytes),
                 std::streamsize(size));
    return output.good();
}

struct IdentityStats {
    char stage = '?';
    uint32_t byteSize = 0;
    uint32_t variants = 0;
    bool captured = false;
};

}  // namespace

int main(int argc, char** argv) {
    if (argc != 4) {
        std::cerr << "usage: mcla_shader_corpus <title.xsh> "
                     "<native-capture-dir> <output-dir>\n";
        return 2;
    }

    const fs::path xshPath = argv[1];
    const fs::path captureRoot = argv[2];
    const fs::path outputRoot = argv[3];
    std::vector<uint8_t> xsh;
    if (!ReadFile(xshPath, xsh) || xsh.size() < 8 ||
        std::memcmp(xsh.data(), "XESH", 4) != 0) {
        std::cerr << "invalid XSH input: " << xshPath << "\n";
        return 1;
    }

    std::map<uint64_t, IdentityStats> identities;
    std::ofstream manifest(outputRoot / "manifest.tsv",
                           std::ios::binary | std::ios::trunc);
    if (!manifest) {
        std::error_code error;
        fs::create_directories(outputRoot, error);
        manifest.open(outputRoot / "manifest.tsv",
                      std::ios::binary | std::ios::trunc);
    }
    if (!manifest) {
        std::cerr << "cannot create output: " << outputRoot << "\n";
        return 1;
    }
    manifest << "stage\tidentity\tgeneric_hash\tbytes\tcaptured\tfile\n";

    size_t cursor = 8;
    uint32_t records = 0;
    uint32_t capturedRecords = 0;
    while (cursor + 12 <= xsh.size()) {
        const uint64_t genericHash = LoadLe64(xsh.data() + cursor);
        const uint32_t countAndStage = LoadLe32(xsh.data() + cursor + 8);
        cursor += 12;
        const bool pixel = (countAndStage & 0x80000000u) != 0;
        const uint32_t dwords = countAndStage & 0x7FFFFFFFu;
        const size_t bytes = size_t(dwords) * sizeof(uint32_t);
        if (dwords > 0xFFFFu || cursor + bytes > xsh.size()) {
            std::cerr << "truncated XSH record at byte " << cursor - 12 << "\n";
            return 1;
        }

        const uint64_t identity = mcla::native_gfx::ShaderIdentity(
            xsh.data() + cursor, bytes);
        const char stage = pixel ? 'p' : 'v';
        const std::string identityText = Hex64(identity);
        const std::string genericHashText = Hex64(genericHash);
        const fs::path capturedPath = captureRoot / "shaders" /
            (std::string(pixel ? "ps-" : "vs-") + identityText + ".bin");
        const bool captured = fs::exists(capturedPath);
        const fs::path relative = fs::path("variants") /
            (std::string(pixel ? "ps-" : "vs-") + identityText + "-" +
             genericHashText + ".bin");
        if (!WriteFile(outputRoot / relative, xsh.data() + cursor, bytes)) {
            std::cerr << "cannot write " << (outputRoot / relative) << "\n";
            return 1;
        }
        manifest << stage << '\t' << identityText << '\t' << genericHashText
                 << '\t' << bytes << '\t' << (captured ? 1 : 0) << '\t'
                 << relative.generic_string() << '\n';

        auto& stats = identities[identity];
        stats.stage = stage;
        stats.byteSize = uint32_t(bytes);
        ++stats.variants;
        stats.captured |= captured;
        ++records;
        capturedRecords += captured ? 1 : 0;
        cursor += bytes;
    }

    if (cursor != xsh.size()) {
        std::cerr << "trailing bytes in XSH: " << xsh.size() - cursor << "\n";
        return 1;
    }

    uint32_t capturedIdentities = 0;
    for (const auto& [identity, stats] : identities) {
        capturedIdentities += stats.captured ? 1 : 0;
    }
    std::ofstream summary(outputRoot / "summary.txt",
                          std::ios::binary | std::ios::trunc);
    summary << "xsh_records=" << records << '\n'
            << "normalized_identities=" << identities.size() << '\n'
            << "captured_xsh_records=" << capturedRecords << '\n'
            << "captured_identities=" << capturedIdentities << '\n';
    std::cout << "XSH records: " << records
              << ", normalized identities: " << identities.size()
              << ", captured identities: " << capturedIdentities << "\n";
    return 0;
}
