#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr uint32_t kShaderContainerMagic = 0x102A1100u;

struct ShaderMetadata {
    uint32_t vertexElements = 0;
    uint32_t vertexInterpolators = 0;
    uint32_t pixelInterpolators = 0;
    uint32_t pixelOutputs = 0;
    bool hasVertex = false;
    bool hasPixel = false;
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

bool WriteFile(const fs::path& path, const std::vector<uint8_t>& bytes) {
    std::error_code error;
    fs::create_directories(path.parent_path(), error);
    if (error) {
        return false;
    }
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) {
        return false;
    }
    output.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
    return output.good();
}

void AppendBe32(std::vector<uint8_t>& bytes, uint32_t value) {
    bytes.push_back(static_cast<uint8_t>(value >> 24));
    bytes.push_back(static_cast<uint8_t>(value >> 16));
    bytes.push_back(static_cast<uint8_t>(value >> 8));
    bytes.push_back(static_cast<uint8_t>(value));
}

void AppendBe16(std::vector<uint8_t>& bytes, uint16_t value) {
    bytes.push_back(static_cast<uint8_t>(value >> 8));
    bytes.push_back(static_cast<uint8_t>(value));
}

void StoreBe32(std::vector<uint8_t>& bytes, size_t offset, uint32_t value) {
    bytes.at(offset + 0) = static_cast<uint8_t>(value >> 24);
    bytes.at(offset + 1) = static_cast<uint8_t>(value >> 16);
    bytes.at(offset + 2) = static_cast<uint8_t>(value >> 8);
    bytes.at(offset + 3) = static_cast<uint8_t>(value);
}

uint32_t LoadLe32(const uint8_t* bytes) {
    return uint32_t(bytes[0]) | uint32_t(bytes[1]) << 8 |
           uint32_t(bytes[2]) << 16 | uint32_t(bytes[3]) << 24;
}

uint32_t LoadBe32(const uint8_t* bytes) {
    return uint32_t(bytes[0]) << 24 | uint32_t(bytes[1]) << 16 |
           uint32_t(bytes[2]) << 8 | uint32_t(bytes[3]);
}

void StoreBe32Raw(uint8_t* bytes, uint32_t value) {
    bytes[0] = static_cast<uint8_t>(value >> 24);
    bytes[1] = static_cast<uint8_t>(value >> 16);
    bytes[2] = static_cast<uint8_t>(value >> 8);
    bytes[3] = static_cast<uint8_t>(value);
}

size_t AlignUp(size_t value, size_t alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
}

uint32_t PatchNoOpVertexFetches(std::vector<uint8_t>& microcode) {
    // XenosRecomp currently prints an invalid empty swizzle for a vfetch whose
    // four destination components are all KEEP. Such an instruction has no
    // architectural write. Mark it as an unsupported fetch opcode in the
    // synthetic compiler input so the compiler emits no operation, preserving
    // the guest behavior without touching the captured source microcode.
    const size_t dwordCount = microcode.size() / 4;
    size_t controlFlowLimit = dwordCount;
    struct ExecRef {
        uint32_t address;
        uint32_t count;
        uint32_t sequence;
    };
    std::vector<ExecRef> execs;
    for (size_t i = 0; i + 2 < controlFlowLimit; i += 3) {
        const uint32_t d0 = LoadBe32(microcode.data() + i * 4);
        const uint32_t d1 = LoadBe32(microcode.data() + (i + 1) * 4);
        const uint32_t d2 = LoadBe32(microcode.data() + (i + 2) * 4);
        const uint32_t word0[2] = {d0, (d1 >> 16) | (d2 << 16)};
        const uint32_t word1[2] = {d1 & 0xFFFFu, d2 >> 16};
        for (size_t half = 0; half < 2; ++half) {
            const uint32_t opcode = (word1[half] >> 12) & 0xFu;
            if (!((opcode >= 1 && opcode <= 6) || opcode == 13 ||
                  opcode == 14)) {
                continue;
            }
            const uint32_t address = word0[half] & 0xFFFu;
            if (address && static_cast<size_t>(address) * 3 < controlFlowLimit) {
                controlFlowLimit = static_cast<size_t>(address) * 3;
            }
            execs.push_back({address, (word0[half] >> 12) & 7u,
                             (word0[half] >> 16) & 0xFFFu});
        }
    }

    uint32_t patched = 0;
    for (const ExecRef& exec : execs) {
        for (uint32_t i = 0; i < std::min(exec.count, 6u); ++i) {
            if (((exec.sequence >> (i * 2)) & 1u) == 0) {
                continue;
            }
            const size_t base = static_cast<size_t>(exec.address + i) * 3;
            if (base + 2 >= dwordCount) {
                continue;
            }
            uint32_t word0 = LoadBe32(microcode.data() + base * 4);
            const uint32_t word1 =
                LoadBe32(microcode.data() + (base + 1) * 4);
            if ((word0 & 0x1Fu) == 0 && (word1 & 0xFFFu) == 0xFFFu) {
                word0 = (word0 & ~0x1Fu) | 31u;
                StoreBe32Raw(microcode.data() + base * 4, word0);
                ++patched;
            }
        }
    }
    return patched;
}

std::optional<std::string> JsonString(std::string_view line,
                                      std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\":\"";
    const size_t start = line.find(needle);
    if (start == std::string_view::npos) {
        return std::nullopt;
    }
    const size_t value = start + needle.size();
    const size_t end = line.find('"', value);
    if (end == std::string_view::npos) {
        return std::nullopt;
    }
    return std::string(line.substr(value, end - value));
}

std::optional<uint32_t> JsonUint(std::string_view line,
                                 std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\":";
    const size_t start = line.find(needle);
    if (start == std::string_view::npos) {
        return std::nullopt;
    }
    size_t cursor = start + needle.size();
    uint64_t value = 0;
    bool found = false;
    while (cursor < line.size() && line[cursor] >= '0' &&
           line[cursor] <= '9') {
        found = true;
        value = value * 10 + uint32_t(line[cursor] - '0');
        if (value > UINT32_MAX) {
            return std::nullopt;
        }
        ++cursor;
    }
    return found ? std::optional<uint32_t>(static_cast<uint32_t>(value))
                 : std::nullopt;
}

bool MergeMetadata(std::map<std::string, ShaderMetadata>& metadata,
                   std::string_view line, std::string& error) {
    const auto vs = JsonString(line, "vs");
    const auto ps = JsonString(line, "ps");
    if (!vs || !ps) {
        return true;
    }

    if (const auto elements = JsonUint(line, "vs_elements")) {
        const auto interpolators = JsonUint(line, "vs_interpolators");
        if (!interpolators) {
            error = "manifest record has incomplete vertex metadata";
            return false;
        }
        auto& entry = metadata[*vs];
        if (entry.hasVertex &&
            (entry.vertexElements != *elements ||
             entry.vertexInterpolators != *interpolators)) {
            error = "conflicting vertex metadata for " + *vs;
            return false;
        }
        entry.vertexElements = *elements;
        entry.vertexInterpolators = *interpolators;
        entry.hasVertex = true;
    }

    if (const auto interpolators = JsonUint(line, "ps_interpolators")) {
        const auto outputs = JsonUint(line, "ps_outputs");
        if (!outputs) {
            error = "manifest record has incomplete pixel metadata";
            return false;
        }
        auto& entry = metadata[*ps];
        if (entry.hasPixel &&
            (entry.pixelInterpolators != *interpolators ||
             entry.pixelOutputs != *outputs)) {
            error = "conflicting pixel metadata for " + *ps;
            return false;
        }
        entry.pixelInterpolators = *interpolators;
        entry.pixelOutputs = *outputs;
        entry.hasPixel = true;
    }
    return true;
}

bool ReadPackedDwords(const fs::path& path, uint32_t expectedCount,
                      std::vector<uint32_t>& values, std::string& error) {
    values.clear();
    if (expectedCount == 0) {
        return true;
    }
    std::vector<uint8_t> bytes;
    if (!ReadFile(path, bytes)) {
        error = "missing metadata file: " + path.string();
        return false;
    }
    if (bytes.size() != static_cast<size_t>(expectedCount) * 4) {
        error = "metadata size mismatch: " + path.string();
        return false;
    }
    values.reserve(expectedCount);
    for (uint32_t i = 0; i < expectedCount; ++i) {
        values.push_back(LoadLe32(bytes.data() + static_cast<size_t>(i) * 4));
    }
    return true;
}

void AppendSyntheticConstantTable(std::vector<uint8_t>& bytes,
                                  uint16_t registerCount) {
    // XenosRecomp names float constants through the source D3DX constant
    // table. Runtime-captured microcode no longer carries that source table,
    // so expose the complete stage constant bank as one array. This preserves
    // direct and relative cN addressing without inventing title symbols.
    constexpr std::string_view kName = "g_MCLAConstants";
    constexpr uint32_t kConstantTableBytes = 7 * sizeof(uint32_t);
    constexpr uint32_t kConstantInfoBytes = 20;
    constexpr uint32_t kNameOffset =
        kConstantTableBytes + kConstantInfoBytes;
    AppendBe32(bytes, kNameOffset + static_cast<uint32_t>(kName.size()) + 1);
    AppendBe32(bytes, 0x1Cu);
    AppendBe32(bytes, 0u);      // creator
    AppendBe32(bytes, 0u);      // version
    AppendBe32(bytes, 1u);      // constants
    AppendBe32(bytes, 0x1Cu);   // constantInfo
    AppendBe32(bytes, 0u);      // flags
    AppendBe32(bytes, 0u);      // target

    AppendBe32(bytes, kNameOffset);
    AppendBe16(bytes, 2u);      // D3DXRS_FLOAT4
    AppendBe16(bytes, 0u);      // register index
    AppendBe16(bytes, registerCount);
    AppendBe16(bytes, 0u);      // reserved
    AppendBe32(bytes, 0u);      // typeInfo (not consulted by XenosRecomp)
    AppendBe32(bytes, 0u);      // defaultValue
    bytes.insert(bytes.end(), kName.begin(), kName.end());
    bytes.push_back(0);
}

void AppendProvisionalIntegerDefinitions(std::vector<uint8_t>& bytes) {
    // DefinitionTable header. Runtime shader objects expose the executable
    // microcode and descriptor ABI, but not the original FXC definition
    // table. Declare every loop register so the recovered program is
    // compilable. A value of one preserves a single loop iteration and keeps
    // this corpus useful for pipeline bring-up; these provisional values are
    // explicitly not a substitute for capturing the title's real integer
    // constants before native takeover.
    for (uint32_t i = 0; i < 4; ++i) {
        AppendBe32(bytes, 0u);
    }
    AppendBe32(bytes, 0u);  // size (not consumed by XenosRecomp)
    AppendBe32(bytes, 0u);  // no float definitions

    AppendBe16(bytes, 8992u);  // integer register file base
    AppendBe16(bytes, 32u);
    AppendBe32(bytes, 0u);     // second definition-header dword
    for (uint32_t i = 0; i < 32; ++i) {
        AppendBe32(bytes, 0x01010101u);
    }
    AppendBe32(bytes, 0u);  // integer-definition terminator
}

std::vector<uint8_t> BuildContainer(bool pixel,
                                    const std::vector<uint8_t>& microcode,
                                    const std::vector<uint32_t>& elements,
                                    const std::vector<uint32_t>& interpolators,
                                    uint32_t pixelOutputs) {
    constexpr size_t kHeaderBytes = 9 * sizeof(uint32_t);
    constexpr size_t kConstantTableOffset = kHeaderBytes;

    std::vector<uint8_t> bytes(kHeaderBytes, 0);
    // The ALU encoding exposes an eight-bit constant address in both stages.
    // MCLA flushes all 256 registers in BOTH banks. The build pipeline also
    // widens XenosRecomp's GTA-specific pixel-array guard to match this ABI.
    // Returning zero for c224..255 destroys post-processing (e.g. c255 is
    // the four-tap downsample multiplier).
    AppendSyntheticConstantTable(bytes, 256u);
    bytes.resize(AlignUp(bytes.size(), 4), 0);
    const size_t definitionTableOffset = bytes.size();
    AppendProvisionalIntegerDefinitions(bytes);
    const size_t shaderOffset = AlignUp(bytes.size(), 16);
    bytes.resize(shaderOffset, 0);

    AppendBe32(bytes, 0u);  // physicalOffset: microcode starts at physical base
    AppendBe32(bytes, static_cast<uint32_t>(microcode.size()));
    AppendBe32(bytes, 0u);  // field8
    AppendBe32(bytes, 0u);  // fieldC / SV_Position register
    AppendBe32(bytes, 0u);  // field10
    AppendBe32(bytes, static_cast<uint32_t>(interpolators.size()) << 5);
    AppendBe32(bytes, 0u);  // field18
    if (pixel) {
        AppendBe32(bytes, pixelOutputs);
        for (uint32_t value : interpolators) {
            AppendBe32(bytes, value);
        }
    } else {
        AppendBe32(bytes, static_cast<uint32_t>(elements.size()));
        AppendBe32(bytes, 0u);  // field20
        for (uint32_t value : elements) {
            AppendBe32(bytes, value);
        }
        for (uint32_t value : interpolators) {
            AppendBe32(bytes, value);
        }
    }

    const size_t virtualSize = AlignUp(bytes.size(), 16);
    bytes.resize(virtualSize, 0);
    std::vector<uint8_t> compilerMicrocode = microcode;
    if (!pixel) {
        PatchNoOpVertexFetches(compilerMicrocode);
    }
    bytes.insert(bytes.end(), compilerMicrocode.begin(),
                 compilerMicrocode.end());

    StoreBe32(bytes, 0, kShaderContainerMagic | (pixel ? 0u : 1u));
    StoreBe32(bytes, 4, static_cast<uint32_t>(virtualSize));
    StoreBe32(bytes, 8, static_cast<uint32_t>(microcode.size()));
    StoreBe32(bytes, 12, static_cast<uint32_t>(kHeaderBytes));
    StoreBe32(bytes, 16, static_cast<uint32_t>(kConstantTableOffset));
    StoreBe32(bytes, 20, static_cast<uint32_t>(definitionTableOffset));
    StoreBe32(bytes, 24, static_cast<uint32_t>(shaderOffset));
    StoreBe32(bytes, 28, 0u);
    StoreBe32(bytes, 32, 0u);
    return bytes;
}

std::string IdentityFromShaderFilename(const fs::path& path, bool& pixel) {
    const std::string stem = path.stem().string();
    if (stem.size() != 19 || stem[2] != '-' ||
        (stem.rfind("vs-", 0) != 0 && stem.rfind("ps-", 0) != 0)) {
        return {};
    }
    pixel = stem[0] == 'p';
    const std::string identity = stem.substr(3);
    if (!std::all_of(identity.begin(), identity.end(), [](char c) {
            return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F');
        })) {
        return {};
    }
    return identity;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "usage: mcla_shader_containers <native-capture-dir> "
                     "<output-dir>\n";
        return 2;
    }
    const fs::path captureRoot = argv[1];
    const fs::path outputRoot = argv[2];

    std::ifstream manifest(captureRoot / "manifest.jsonl");
    if (!manifest) {
        std::cerr << "cannot read capture manifest\n";
        return 1;
    }
    std::map<std::string, ShaderMetadata> metadata;
    std::string line;
    std::string error;
    while (std::getline(manifest, line)) {
        if (!MergeMetadata(metadata, line, error)) {
            std::cerr << error << '\n';
            return 1;
        }
    }

    std::error_code fsError;
    fs::create_directories(outputRoot, fsError);
    if (fsError) {
        std::cerr << "cannot create output directory: " << fsError.message()
                  << '\n';
        return 1;
    }
    std::ofstream mapFile(outputRoot / "identities.tsv",
                          std::ios::binary | std::ios::trunc);
    mapFile << "stage\tidentity\tcontainer\tmicrocode_bytes\telements\tinterpolators\toutputs\n";

    uint32_t vertexWritten = 0;
    uint32_t pixelWritten = 0;
    uint32_t skippedNoMetadata = 0;
    uint32_t failed = 0;
    for (const auto& entry : fs::directory_iterator(captureRoot / "shaders")) {
        if (!entry.is_regular_file() || entry.path().extension() != ".bin") {
            continue;
        }
        bool pixel = false;
        const std::string identity =
            IdentityFromShaderFilename(entry.path(), pixel);
        if (identity.empty()) {
            continue;
        }
        const auto metadataIt = metadata.find(identity);
        if (metadataIt == metadata.end() ||
            (pixel ? !metadataIt->second.hasPixel
                   : !metadataIt->second.hasVertex)) {
            ++skippedNoMetadata;
            continue;
        }

        const ShaderMetadata& shaderMetadata = metadataIt->second;
        std::vector<uint8_t> microcode;
        if (!ReadFile(entry.path(), microcode) || microcode.empty() ||
            microcode.size() % 12 != 0 || microcode.size() > UINT32_MAX) {
            std::cerr << "invalid microcode: " << entry.path() << '\n';
            ++failed;
            continue;
        }

        std::vector<uint32_t> elements;
        std::vector<uint32_t> interpolators;
        const fs::path metadataRoot = captureRoot / "metadata";
        if (!pixel) {
            if (!ReadPackedDwords(metadataRoot /
                                      ("vs-elements-" + identity + ".bin"),
                                  shaderMetadata.vertexElements, elements,
                                  error) ||
                !ReadPackedDwords(metadataRoot /
                                      ("vs-interpolators-" + identity + ".bin"),
                                  shaderMetadata.vertexInterpolators,
                                  interpolators, error)) {
                std::cerr << error << '\n';
                ++failed;
                continue;
            }
        } else if (!ReadPackedDwords(
                       metadataRoot /
                           ("ps-interpolators-" + identity + ".bin"),
                       shaderMetadata.pixelInterpolators, interpolators,
                       error)) {
            std::cerr << error << '\n';
            ++failed;
            continue;
        }

        const std::vector<uint8_t> container = BuildContainer(
            pixel, microcode, elements, interpolators,
            shaderMetadata.pixelOutputs);
        const std::string filename =
            std::string(pixel ? "ps-" : "vs-") + identity + ".bin";
        if (!WriteFile(outputRoot / filename, container)) {
            std::cerr << "cannot write " << filename << '\n';
            ++failed;
            continue;
        }
        mapFile << (pixel ? "pixel" : "vertex") << '\t' << identity << '\t'
                << filename << '\t' << microcode.size() << '\t'
                << elements.size() << '\t' << interpolators.size() << '\t'
                << (pixel ? shaderMetadata.pixelOutputs : 0) << '\n';
        pixel ? ++pixelWritten : ++vertexWritten;
    }

    std::ofstream summary(outputRoot / "summary.txt",
                          std::ios::binary | std::ios::trunc);
    summary << "vertex_containers=" << vertexWritten << '\n'
            << "pixel_containers=" << pixelWritten << '\n'
            << "skipped_without_authoritative_metadata=" << skippedNoMetadata
            << '\n'
            << "failed=" << failed << '\n';
    std::cout << "MCLA shader containers: " << vertexWritten << " vertex, "
              << pixelWritten << " pixel, " << skippedNoMetadata
              << " skipped without authoritative metadata, " << failed
              << " failed\n";
    return failed == 0 ? 0 : 1;
}
