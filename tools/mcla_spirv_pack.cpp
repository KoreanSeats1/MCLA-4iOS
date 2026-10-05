#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

namespace fs = std::filesystem;

namespace {

struct Entry {
    uint64_t identity = 0;
    uint32_t stage = 0;
    uint32_t flags = 0;
    std::vector<uint8_t> spirv;
};

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
    bytes.resize(static_cast<size_t>(size));
    return size == 0 ||
           bool(input.read(reinterpret_cast<char*>(bytes.data()), size));
}

void AppendLe32(std::vector<uint8_t>& bytes, uint32_t value) {
    bytes.push_back(static_cast<uint8_t>(value));
    bytes.push_back(static_cast<uint8_t>(value >> 8));
    bytes.push_back(static_cast<uint8_t>(value >> 16));
    bytes.push_back(static_cast<uint8_t>(value >> 24));
}

void AppendLe64(std::vector<uint8_t>& bytes, uint64_t value) {
    AppendLe32(bytes, static_cast<uint32_t>(value));
    AppendLe32(bytes, static_cast<uint32_t>(value >> 32));
}

uint32_t LoadLe32(const uint8_t* bytes) {
    return uint32_t(bytes[0]) | uint32_t(bytes[1]) << 8 |
           uint32_t(bytes[2]) << 16 | uint32_t(bytes[3]) << 24;
}

bool ParseHex64(const std::string& text, uint64_t& value) {
    if (text.size() != 16) {
        return false;
    }
    std::istringstream stream(text);
    stream >> std::hex >> value;
    return stream && stream.eof();
}

std::vector<std::string> SplitTabs(const std::string& line) {
    std::vector<std::string> fields;
    size_t start = 0;
    while (true) {
        const size_t tab = line.find('\t', start);
        fields.emplace_back(line.substr(start, tab - start));
        if (tab == std::string::npos) {
            break;
        }
        start = tab + 1;
    }
    return fields;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "usage: mcla_spirv_pack <compiled-shader-dir> <output-pack>\n";
        return 2;
    }
    const fs::path inputRoot = argv[1];
    const fs::path outputPath = argv[2];
    std::ifstream manifest(inputRoot / "manifest.tsv");
    if (!manifest) {
        std::cerr << "cannot read compiled shader manifest\n";
        return 1;
    }

    std::vector<Entry> entries;
    std::string line;
    std::getline(manifest, line);
    uint32_t lineNumber = 1;
    while (std::getline(manifest, line)) {
        ++lineNumber;
        const std::vector<std::string> fields = SplitTabs(line);
        if (fields.size() != 6 || fields[5] != "ok") {
            std::cerr << "non-production shader record at line " << lineNumber
                      << '\n';
            return 1;
        }
        Entry entry;
        if (!ParseHex64(fields[1], entry.identity) ||
            (fields[0] != "vs" && fields[0] != "ps")) {
            std::cerr << "invalid shader identity/stage at line " << lineNumber
                      << '\n';
            return 1;
        }
        entry.stage = fields[0] == "ps" ? 1u : 0u;
        // The reconstructed FXC definition table currently provides a
        // conservative single-iteration value for integer loop registers.
        // Preserve that limitation in the binary ABI so takeover code cannot
        // accidentally treat this first corpus as final-correct.
        entry.flags = 1u;
        if (!ReadFile(inputRoot / fields[3], entry.spirv) ||
            entry.spirv.size() < 20 || entry.spirv.size() % 4 != 0 ||
            LoadLe32(entry.spirv.data()) != 0x07230203u ||
            entry.spirv.size() > UINT32_MAX) {
            std::cerr << "invalid SPIR-V at line " << lineNumber << '\n';
            return 1;
        }
        entries.emplace_back(std::move(entry));
    }
    std::sort(entries.begin(), entries.end(), [](const Entry& left,
                                                  const Entry& right) {
        return std::tie(left.identity, left.stage) <
               std::tie(right.identity, right.stage);
    });
    for (size_t i = 1; i < entries.size(); ++i) {
        if (entries[i - 1].identity == entries[i].identity &&
            entries[i - 1].stage == entries[i].stage) {
            std::cerr << "duplicate shader identity/stage\n";
            return 1;
        }
    }

    constexpr uint32_t kHeaderBytes = 32;
    constexpr uint32_t kEntryBytes = 24;
    const uint64_t tableBytes = uint64_t(entries.size()) * kEntryBytes;
    const uint64_t dataOffset = (kHeaderBytes + tableBytes + 15u) & ~15ull;
    uint64_t dataBytes = 0;
    for (const Entry& entry : entries) {
        dataBytes += entry.spirv.size();
    }
    if (dataOffset + dataBytes > SIZE_MAX || dataBytes > UINT32_MAX) {
        std::cerr << "shader pack is too large\n";
        return 1;
    }

    std::vector<uint8_t> pack;
    pack.reserve(static_cast<size_t>(dataOffset + dataBytes));
    pack.insert(pack.end(), {'M', 'S', 'P', 'V'});
    AppendLe32(pack, 1u);
    AppendLe32(pack, static_cast<uint32_t>(entries.size()));
    AppendLe32(pack, kEntryBytes);
    AppendLe64(pack, dataOffset);
    AppendLe64(pack, dataBytes);

    uint32_t relativeOffset = 0;
    for (const Entry& entry : entries) {
        AppendLe64(pack, entry.identity);
        AppendLe32(pack, entry.stage);
        AppendLe32(pack, entry.flags);
        AppendLe32(pack, relativeOffset);
        AppendLe32(pack, static_cast<uint32_t>(entry.spirv.size()));
        relativeOffset += static_cast<uint32_t>(entry.spirv.size());
    }
    pack.resize(static_cast<size_t>(dataOffset), 0);
    for (const Entry& entry : entries) {
        pack.insert(pack.end(), entry.spirv.begin(), entry.spirv.end());
    }

    std::error_code error;
    fs::create_directories(outputPath.parent_path(), error);
    std::ofstream output(outputPath, std::ios::binary | std::ios::trunc);
    if (error || !output) {
        std::cerr << "cannot create shader pack\n";
        return 1;
    }
    output.write(reinterpret_cast<const char*>(pack.data()),
                 static_cast<std::streamsize>(pack.size()));
    if (!output.good()) {
        std::cerr << "cannot write shader pack\n";
        return 1;
    }
    std::cout << "MCLA SPIR-V pack: " << entries.size() << " shaders, "
              << dataBytes << " shader bytes, " << pack.size()
              << " total bytes\n";
    return 0;
}
