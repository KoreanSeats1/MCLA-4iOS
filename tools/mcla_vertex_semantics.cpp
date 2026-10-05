#include <algorithm>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

struct VertexFetch {
    uint32_t address = 0;
    uint32_t fetchSlot = 0;
    uint32_t strideBytes = 0;
    uint32_t offsetBytes = 0;
    uint32_t format = 0;
};

struct DeclarationElement {
    uint32_t stream = 0;
    uint32_t offset = 0;
    uint32_t type = 0;
    uint32_t usage = 0;
    uint32_t usageIndex = 0;
};

struct Semantic {
    uint32_t usage = 0;
    uint32_t usageIndex = 0;

    auto operator<=>(const Semantic&) const = default;
};

struct Evidence {
    std::map<Semantic, uint32_t> observations;
    uint32_t unmatchedObservations = 0;
};

struct ShaderEvidence {
    std::map<uint32_t, Evidence> byAddress;
    std::set<std::string> declarations;
    uint32_t observations = 0;
};

#pragma pack(push, 1)
struct MapHeader {
    char magic[4];
    uint32_t version;
    uint32_t shaderCount;
    uint32_t referenceCount;
};

struct MapEntry {
    uint64_t identity;
    uint32_t firstReference;
    uint32_t referenceCount;
};
#pragma pack(pop)

static_assert(sizeof(MapHeader) == 16);
static_assert(sizeof(MapEntry) == 16);

uint16_t LoadBe16(const uint8_t* bytes) {
    return uint16_t(bytes[0]) << 8 | uint16_t(bytes[1]);
}

uint32_t LoadBe32(const uint8_t* bytes) {
    return uint32_t(bytes[0]) << 24 | uint32_t(bytes[1]) << 16 |
           uint32_t(bytes[2]) << 8 | uint32_t(bytes[3]);
}

uint32_t LoadLe32(const uint8_t* bytes) {
    return uint32_t(bytes[0]) | uint32_t(bytes[1]) << 8 |
           uint32_t(bytes[2]) << 16 | uint32_t(bytes[3]) << 24;
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

bool IsExecOpcode(uint32_t opcode) {
    return (opcode >= 1 && opcode <= 7) || opcode == 13 || opcode == 14;
}

std::vector<VertexFetch> DecodeVertexFetches(const std::vector<uint8_t>& ucode) {
    std::vector<VertexFetch> fetches;
    const size_t dwordCount = ucode.size() / sizeof(uint32_t);
    if (dwordCount < 3) {
        return fetches;
    }

    struct ExecRef {
        uint32_t address;
        uint32_t count;
        uint32_t sequence;
    };
    std::vector<ExecRef> execs;
    size_t controlFlowLimit = dwordCount;
    for (size_t i = 0; i + 2 < controlFlowLimit; i += 3) {
        const uint32_t d0 = LoadBe32(ucode.data() + 4 * i);
        const uint32_t d1 = LoadBe32(ucode.data() + 4 * (i + 1));
        const uint32_t d2 = LoadBe32(ucode.data() + 4 * (i + 2));
        const uint32_t word0[2] = {d0, (d1 >> 16) | (d2 << 16)};
        const uint32_t word1[2] = {d1 & 0xFFFFu, d2 >> 16};
        for (size_t half = 0; half < 2; ++half) {
            if (!IsExecOpcode((word1[half] >> 12) & 0xFu)) {
                continue;
            }
            const uint32_t address = word0[half] & 0xFFFu;
            if (!address) {
                continue;
            }
            if (size_t(address) * 3 < controlFlowLimit) {
                controlFlowLimit = size_t(address) * 3;
            }
            execs.push_back({address, (word0[half] >> 12) & 7u,
                             (word0[half] >> 16) & 0xFFFu});
        }
    }

    for (const ExecRef& exec : execs) {
        const uint32_t count = std::min(exec.count, 6u);
        for (uint32_t i = 0; i < count; ++i) {
            if (((exec.sequence >> (2 * i)) & 1u) == 0) {
                continue;
            }
            const uint32_t address = exec.address + i;
            const size_t base = size_t(address) * 3;
            if (base + 2 >= dwordCount) {
                continue;
            }
            const uint32_t word0 = LoadBe32(ucode.data() + 4 * base);
            if ((word0 & 0x1Fu) != 0) {
                continue;
            }
            const uint32_t word1 = LoadBe32(ucode.data() + 4 * (base + 1));
            const uint32_t word2 = LoadBe32(ucode.data() + 4 * (base + 2));
            fetches.push_back(VertexFetch{
                .address = address,
                .fetchSlot = (word0 >> 20) & 0x7Fu,
                .strideBytes = (word2 & 0xFFu) * 4,
                .offsetBytes = ((word2 >> 8) & 0x7FFFFFu) * 4,
                .format = (word1 >> 16) & 0x3Fu,
            });
        }
    }
    return fetches;
}

std::vector<DeclarationElement> DecodeDeclaration(
    const std::vector<uint8_t>& bytes) {
    std::vector<DeclarationElement> elements;
    for (size_t offset = 0; offset + 12 <= bytes.size(); offset += 12) {
        const uint8_t* record = bytes.data() + offset;
        const uint32_t stream = LoadBe16(record);
        if (stream == 0xFFu) {
            break;
        }
        elements.push_back(DeclarationElement{
            .stream = stream,
            .offset = LoadBe16(record + 2),
            .type = LoadBe32(record + 4),
            .usage = record[9],
            .usageIndex = record[10],
        });
    }
    return elements;
}

std::string JsonString(const std::string& line, const std::string& key) {
    const std::string prefix = "\"" + key + "\":\"";
    const size_t begin = line.find(prefix);
    if (begin == std::string::npos) {
        return {};
    }
    const size_t valueBegin = begin + prefix.size();
    const size_t end = line.find('"', valueBegin);
    return end == std::string::npos ? std::string{}
                                    : line.substr(valueBegin, end - valueBegin);
}

bool ParseHex64(const std::string& text, uint64_t& value) {
    if (text.size() != 16) {
        return false;
    }
    std::istringstream input(text);
    input >> std::hex >> value;
    return input && input.eof();
}

std::string Hex64(uint64_t value) {
    std::ostringstream output;
    output << std::hex << std::uppercase << std::setw(16)
           << std::setfill('0') << value;
    return output.str();
}

const char* UsageName(uint32_t usage) {
    switch (usage) {
        case 0: return "POSITION";
        case 1: return "BLENDWEIGHT";
        case 2: return "BLENDINDICES";
        case 3: return "NORMAL";
        case 4: return "PSIZE";
        case 5: return "TEXCOORD";
        case 6: return "TANGENT";
        case 7: return "BINORMAL";
        case 10: return "COLOR";
        default: return "UNKNOWN";
    }
}

uint32_t PackReference(uint32_t address, const Semantic& semantic) {
    return (address & 0xFFFu) | ((semantic.usage & 0xFu) << 12) |
           ((semantic.usageIndex & 0xFu) << 16);
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "usage: mcla_vertex_semantics <native-capture-dir> "
                     "<output-dir>\n";
        return 2;
    }

    const fs::path captureRoot = argv[1];
    const fs::path outputRoot = argv[2];
    std::ifstream manifest(captureRoot / "manifest.jsonl");
    if (!manifest) {
        std::cerr << "cannot open capture manifest under " << captureRoot
                  << "\n";
        return 1;
    }
    std::error_code error;
    fs::create_directories(outputRoot, error);
    if (error) {
        std::cerr << "cannot create output directory: " << error.message()
                  << "\n";
        return 1;
    }

    std::map<uint64_t, ShaderEvidence> shaders;
    std::set<std::pair<uint64_t, std::string>> observedPairs;
    std::set<uint64_t> attemptedDirectMetadata;
    std::set<uint64_t> directMetadataShaders;
    uint32_t manifestRecords = 0;
    uint32_t invalidRecords = 0;
    uint32_t decodedFetches = 0;
    uint32_t matchedFetches = 0;
    uint32_t ambiguousFetches = 0;
    uint32_t implausibleSlots = 0;
    uint32_t formatDisagreements = 0;

    std::string line;
    while (std::getline(manifest, line)) {
        ++manifestRecords;
        const std::string vsText = JsonString(line, "vs");
        const std::string declarationText = JsonString(line, "decl");
        uint64_t identity = 0;
        if (vsText == "0000000000000000" || declarationText.empty() ||
            !ParseHex64(vsText, identity) ||
            !observedPairs.emplace(identity, declarationText).second) {
            continue;
        }

        std::vector<uint8_t> ucode;
        std::vector<uint8_t> declarationBytes;
        if (!ReadFile(captureRoot / "shaders" / ("vs-" + vsText + ".bin"),
                      ucode) ||
            !ReadFile(captureRoot / "declarations" /
                          ("decl-" + declarationText + ".bin"),
                      declarationBytes)) {
            ++invalidRecords;
            continue;
        }
        const std::vector<VertexFetch> fetches = DecodeVertexFetches(ucode);
        ShaderEvidence& shader = shaders[identity];
        shader.declarations.insert(declarationText);
        ++shader.observations;

        // Preferred path: these packed values come directly from the live
        // VertexShader descriptor and are the same authoritative table MCLA's
        // 0x82423A38 vfetch patcher consumes. The declaration/microcode join
        // below remains only as a backward-compatible fallback for older
        // captures that predate descriptor metadata.
        if (attemptedDirectMetadata.insert(identity).second) {
            std::vector<uint8_t> direct;
            if (ReadFile(captureRoot / "metadata" /
                             ("vs-elements-" + vsText + ".bin"),
                         direct) &&
                !direct.empty() && direct.size() % 4 == 0) {
                for (size_t offset = 0; offset < direct.size(); offset += 4) {
                    const uint32_t packed = LoadLe32(direct.data() + offset);
                    const uint32_t address = packed & 0xFFFu;
                    const Semantic semantic{(packed >> 12) & 0xFu,
                                            (packed >> 16) & 0xFu};
                    ++shader.byAddress[address].observations[semantic];
                }
                directMetadataShaders.insert(identity);
            }
        }
        if (directMetadataShaders.contains(identity)) {
            decodedFetches += uint32_t(fetches.size());
            for (const VertexFetch& fetch : fetches) {
                if (shader.byAddress.contains(fetch.address)) {
                    ++matchedFetches;
                }
            }
            continue;
        }

        const std::vector<DeclarationElement> elements =
            DecodeDeclaration(declarationBytes);

        for (const VertexFetch& fetch : fetches) {
            ++decodedFetches;
            Evidence& evidence = shader.byAddress[fetch.address];
            if (fetch.fetchSlot > 95u || fetch.fetchSlot < 80u) {
                ++implausibleSlots;
                ++evidence.unmatchedObservations;
                continue;
            }
            const uint32_t stream = 95u - fetch.fetchSlot;
            std::vector<const DeclarationElement*> candidates;
            for (const DeclarationElement& element : elements) {
                if (element.stream == stream &&
                    element.offset == fetch.offsetBytes) {
                    candidates.push_back(&element);
                }
            }
            if (candidates.size() > 1 && fetch.format) {
                std::erase_if(candidates, [&](const DeclarationElement* element) {
                    return (element->type & 0x3Fu) != fetch.format;
                });
            }
            if (candidates.size() != 1) {
                if (candidates.size() > 1) {
                    ++ambiguousFetches;
                }
                ++evidence.unmatchedObservations;
                continue;
            }
            const DeclarationElement& match = *candidates.front();
            if (fetch.format && (match.type & 0x3Fu) != fetch.format) {
                ++formatDisagreements;
            }
            ++evidence.observations[{match.usage, match.usageIndex}];
            ++matchedFetches;
        }
    }

    std::ofstream tsv(outputRoot / "vertex-elements.tsv",
                      std::ios::binary | std::ios::trunc);
    tsv << "vertex_shader\tinstruction\tusage\tusage_index\tsemantic\t"
           "observations\tunmatched\tconflict\tsource\n";

    std::vector<MapEntry> entries;
    std::vector<uint32_t> references;
    uint32_t resolvedShaders = 0;
    uint32_t partialShaders = 0;
    uint32_t conflictingAddresses = 0;
    uint32_t unresolvedAddresses = 0;
    for (const auto& [identity, shader] : shaders) {
        MapEntry entry{identity, uint32_t(references.size()), 0};
        bool partial = false;
        const bool authoritative = directMetadataShaders.contains(identity);
        for (const auto& [address, evidence] : shader.byAddress) {
            const bool conflict = evidence.observations.size() > 1;
            if (conflict) {
                ++conflictingAddresses;
                partial = true;
            }
            if (evidence.observations.empty()) {
                ++unresolvedAddresses;
                partial = true;
                tsv << Hex64(identity) << '\t' << address
                    << "\t-\t-\tUNRESOLVED\t0\t"
                    << evidence.unmatchedObservations << "\t0\t"
                    << (directMetadataShaders.contains(identity)
                            ? "shader_descriptor"
                            : "declaration_inference")
                    << '\n';
                continue;
            }

            auto best = std::max_element(
                evidence.observations.begin(), evidence.observations.end(),
                [](const auto& left, const auto& right) {
                    return left.second < right.second;
                });
            const Semantic selected = best->first;
            // Never put declaration-derived guesses into the binary consumed
            // by a renderer. They remain visible in the TSV to help target a
            // later device capture, but only MCLA's own shader-descriptor
            // table is authoritative enough to ship.
            if (!conflict && authoritative) {
                references.push_back(PackReference(address, selected));
                ++entry.referenceCount;
            }
            for (const auto& [semantic, count] : evidence.observations) {
                tsv << Hex64(identity) << '\t' << address << '\t'
                    << semantic.usage << '\t' << semantic.usageIndex << '\t'
                    << UsageName(semantic.usage) << semantic.usageIndex << '\t'
                    << count << '\t' << evidence.unmatchedObservations << '\t'
                    << (conflict ? 1 : 0) << '\t'
                    << (authoritative
                            ? "shader_descriptor"
                            : "declaration_inference")
                    << '\n';
            }
        }
        if (entry.referenceCount) {
            entries.push_back(entry);
            ++resolvedShaders;
            partialShaders += partial ? 1u : 0u;
        }
    }

    std::ofstream binary(outputRoot / "mcla_vertex_elements.map",
                         std::ios::binary | std::ios::trunc);
    const MapHeader header{{'M', 'V', 'E', 'M'}, 1u,
                           uint32_t(entries.size()),
                           uint32_t(references.size())};
    binary.write(reinterpret_cast<const char*>(&header), sizeof(header));
    binary.write(reinterpret_cast<const char*>(entries.data()),
                 std::streamsize(entries.size() * sizeof(MapEntry)));
    binary.write(reinterpret_cast<const char*>(references.data()),
                 std::streamsize(references.size() * sizeof(uint32_t)));
    if (!tsv.good() || !binary.good()) {
        std::cerr << "failed while writing semantic map\n";
        return 1;
    }

    std::ofstream summary(outputRoot / "summary.txt",
                          std::ios::binary | std::ios::trunc);
    summary << "manifest_records=" << manifestRecords << '\n'
            << "invalid_records=" << invalidRecords << '\n'
            << "unique_vertex_shader_declaration_pairs="
            << observedPairs.size() << '\n'
            << "vertex_shaders_observed=" << shaders.size() << '\n'
            << "authoritative_shader_descriptor_tables="
            << directMetadataShaders.size() << '\n'
            << "fallback_inferred_shader_tables="
            << (shaders.size() - directMetadataShaders.size()) << '\n'
            << "vertex_shaders_in_authoritative_binary_map="
            << resolvedShaders
            << '\n'
            << "partially_resolved_vertex_shaders=" << partialShaders << '\n'
            << "decoded_vertex_fetches=" << decodedFetches << '\n'
            << "matched_vertex_fetches=" << matchedFetches << '\n'
            << "implausible_fetch_slots=" << implausibleSlots << '\n'
            << "ambiguous_vertex_fetches=" << ambiguousFetches << '\n'
            << "format_disagreements=" << formatDisagreements << '\n'
            << "conflicting_instruction_addresses=" << conflictingAddresses
            << '\n'
            << "unresolved_instruction_addresses=" << unresolvedAddresses
            << '\n'
            << "packed_authoritative_element_references="
            << references.size() << '\n';

    std::cout << "resolved " << references.size() << " vertex elements across "
              << resolvedShaders << " shaders; " << conflictingAddresses
              << " conflicts, " << unresolvedAddresses << " unresolved\n";
    return 0;
}
