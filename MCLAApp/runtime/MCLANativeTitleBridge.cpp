#include "MCLADiagnostics.h"
#include "MCLANativeTitleBridge.h"
#include "MCLANativeRenderer.h"

#include "shader_identity.h"

#include <rex/memory.h>
#include <rex/runtime.h>
#include <rex/logging.h>
#include <rex/system/xmemory.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <memory>
#include <mutex>
#include <sstream>
#include <thread>
#include <unordered_set>
#include <vector>

namespace {

bool ShaderCaptureEnabled() {
    if (!mcla::DiagnosticsEnabled()) return false;
#if MCLA_DIRECT_METAL
    static const bool enabled = std::getenv("MCLA_SHADER_CAPTURE") != nullptr;
    return enabled;
#else
    return true;
#endif
}

// Confirmed MCLA Complete Edition device-layout offsets from LARecomp's
// native_gfx guest decoder. These are deliberately not GTA IV offsets.
constexpr uint32_t kDevFetchShadowOffset = 1152;
constexpr uint32_t kFetchShadowBytes = 32 * 6 * sizeof(uint32_t);
constexpr uint32_t kDevIndexBufferOffset = 12436;
constexpr uint32_t kDevPixelShaderOffset = 12692;
constexpr uint32_t kDevVertexShaderOffset = 12696;
constexpr uint32_t kDevVertexDeclarationOffset = 11820;
constexpr uint32_t kDevDeclStrideMirrorOffset = 11832;
constexpr uint32_t kDevStreamStrideTableOffset = 12528;
constexpr uint32_t kDeclOffsetElementCount = 24;
constexpr uint32_t kDeclOffsetMaxStream = 28;
constexpr uint32_t kDeclOffsetElements = 52;
constexpr uint32_t kMaximumDeclarationElements = 64;
constexpr uint32_t kDeclarationRecordBytes = 12;
constexpr uint32_t kStreamCount = 16;
constexpr uint32_t kMaxUcodeBytes = 64 * 1024;
constexpr uint32_t kMaximumShaderElements = 64;
constexpr uint32_t kMaximumShaderInterpolators = 31;
constexpr size_t kQueueCapacity = 8192;
static_assert(std::has_single_bit(kQueueCapacity));

enum class CommandType : uint8_t {
    kDrawIndexed,
    kDraw,
    kInlineDraw,
    kClear,
    kBeginTiling,
    kEndTiling,
    kResolve,
    kFrameEnd,
    kSwap,
};

struct CapturePayload {
    std::vector<uint8_t> vertexShader;
    std::vector<uint8_t> pixelShader;
    // Host-little-endian copies of the packed VertexElement / Interpolator
    // dwords from MCLA's shader descriptors. These are the authoritative
    // semantics consumed by the title's own vfetch patcher.
    std::vector<uint8_t> vertexElements;
    std::vector<uint8_t> vertexInterpolators;
    std::vector<uint8_t> pixelInterpolators;
    std::vector<uint8_t> declaration;
    std::array<uint8_t, kFetchShadowBytes> fetchShadow{};
    std::array<uint8_t, kStreamCount> streamStrides{};
    std::array<uint8_t, kStreamCount> patchedStreamStrides{};
};

struct TitleCommand {
    CommandType type = CommandType::kDraw;
    uint8_t indexed = 0;
    uint16_t reserved = 0;
    bool automaticCapture = false;
    uint32_t device = 0;
    uint32_t primitive = 0;
    uint32_t count = 0;
    uint32_t start = 0;
    int32_t baseVertex = 0;
    uint32_t flags = 0;
    uint32_t argument0 = 0;
    uint32_t argument1 = 0;
    uint32_t argument2 = 0;
    uint32_t vertexShaderObject = 0;
    uint32_t pixelShaderObject = 0;
    uint32_t vertexShaderBytes = 0;
    uint32_t pixelShaderBytes = 0;
    uint32_t vertexShaderAddress = 0;
    uint32_t pixelShaderAddress = 0;
    uint32_t vertexShaderDescriptor = 0;
    uint32_t pixelShaderDescriptor = 0;
    uint32_t vertexElementTableAddress = 0;
    uint32_t vertexElementCount = 0;
    uint32_t vertexInterpolatorTableAddress = 0;
    uint32_t vertexInterpolatorCount = 0;
    uint32_t pixelInterpolatorTableAddress = 0;
    uint32_t pixelInterpolatorCount = 0;
    uint32_t pixelOutputs = 0;
    uint64_t vertexShaderIdentity = 0;
    uint64_t pixelShaderIdentity = 0;
    uint64_t fetchFingerprint = 0;
    uint32_t validVertexFetches = 0;
    uint32_t indexAddress = 0;
    uint32_t indexFormat = 0;
    uint32_t declarationAddress = 0;
    uint32_t declarationElementCount = 0;
    uint32_t declarationMaxStream = 0;
    uint64_t declarationFingerprint = 0;
    std::shared_ptr<CapturePayload> capture;
};

// Dmitry Vyukov's bounded MPMC sequence scheme. Draw hooks must never wait for
// the renderer: if it falls behind, the shadow stream drops a packet and the
// generic correctness path continues. The same transport remains usable when
// the renderer takes presentation ownership later.
struct QueueCell {
    std::atomic<size_t> sequence{0};
    TitleCommand command{};
};

struct NativeShaderPackEntry {
    uint32_t offset = 0;
    uint32_t size = 0;
    uint32_t flags = 0;
};

bool IsGuestRangeReadable(uint32_t address, uint64_t size) {
    if (address < 0x1000u || size == 0 ||
        uint64_t(address) + size > 0x100000000ull) {
        return false;
    }
    auto* runtime = rex::Runtime::instance();
    auto* memory = runtime ? runtime->memory() : nullptr;
    auto* heap = memory ? memory->LookupHeap(address) : nullptr;
    if (!heap) {
        return false;
    }
    const uint32_t last = uint32_t(uint64_t(address) + size - 1);
    return heap->QueryRangeAccess(address, last) !=
           rex::memory::PageAccess::kNoAccess;
}

uint32_t LoadBe32Unchecked(const uint8_t* base, uint32_t address) {
    uint32_t value = 0;
    std::memcpy(&value,
                rex::memory::GuestPtr(const_cast<uint8_t*>(base), address), 4);
    return __builtin_bswap32(value);
}

uint32_t LoadLe32(const uint8_t* bytes) {
    return uint32_t(bytes[0]) | uint32_t(bytes[1]) << 8 |
           uint32_t(bytes[2]) << 16 | uint32_t(bytes[3]) << 24;
}

uint64_t LoadLe64(const uint8_t* bytes) {
    return uint64_t(LoadLe32(bytes)) |
           uint64_t(LoadLe32(bytes + 4)) << 32;
}

bool LoadBe32(const uint8_t* base, uint32_t address, uint32_t& value) {
    if (!base || !IsGuestRangeReadable(address, sizeof(uint32_t))) {
        return false;
    }
    value = LoadBe32Unchecked(base, address);
    return true;
}

struct UcodeRef {
    uint32_t address = 0;
    uint32_t size = 0;
    uint32_t descriptor = 0;
};

UcodeRef ReadPixelShaderUcode(const uint8_t* base, uint32_t object) {
    uint32_t subOffset = 0;
    uint32_t objectBase = 0;
    if (!LoadBe32(base, object + 64, subOffset) ||
        !LoadBe32(base, object + 24, objectBase) ||
        uint64_t(object) + subOffset + 48 > 0x100000000ull) {
        return {};
    }
    const uint32_t sub = object + subOffset;
    uint32_t relativeAddress = 0;
    uint32_t size = 0;
    if (!LoadBe32(base, sub + 40, relativeAddress) ||
        !LoadBe32(base, sub + 44, size) || size == 0 ||
        size > kMaxUcodeBytes) {
        return {};
    }
    const uint64_t address = uint64_t(relativeAddress) + objectBase;
    if (address > UINT32_MAX || !IsGuestRangeReadable(uint32_t(address), size)) {
        return {};
    }
    return {uint32_t(address), size, sub + 40};
}

UcodeRef ReadVertexShaderUcode(const uint8_t* base, uint32_t object,
                               uint32_t pixelShaderObject) {
    uint32_t flags = 0;
    uint32_t variant = 0;
    if (!pixelShaderObject && LoadBe32(base, object + 872, flags) &&
        (flags & 0x20u)) {
        variant = 1;
    }
    uint32_t variantOffset = 0;
    uint32_t objectBase = 0;
    if (!LoadBe32(base, object + 896 + 8 * variant, variantOffset) ||
        !variantOffset || !LoadBe32(base, object + 32, objectBase) ||
        uint64_t(object) + variantOffset + 880 > 0x100000000ull) {
        return {};
    }
    uint32_t relativeAddress = 0;
    uint32_t size = 0;
    if (!LoadBe32(base, object + variantOffset + 872, relativeAddress) ||
        !LoadBe32(base, object + variantOffset + 876, size) || size == 0 ||
        size > kMaxUcodeBytes) {
        return {};
    }
    const uint64_t address = uint64_t(relativeAddress) + objectBase;
    if (address > UINT32_MAX || !IsGuestRangeReadable(uint32_t(address), size)) {
        return {};
    }
    return {uint32_t(address), size, object + variantOffset + 872};
}

void ReadShaderMetadata(const uint8_t* base, const UcodeRef& vertex,
                        const UcodeRef& pixel, TitleCommand& command) {
    command.vertexShaderDescriptor = vertex.descriptor;
    command.pixelShaderDescriptor = pixel.descriptor;

    // XenosRecomp's VertexShader layout begins at the descriptor used above:
    // Shader[6 dwords], field18, vertexElementCount, field20, flexible dwords.
    // field18 is an index into that flexible array. MCLA's patcher at
    // 0x82423A38 performs the same address calculation: descriptor +
    // (field18 + 9) * 4.
    if (vertex.descriptor) {
        uint32_t interpolatorInfo = 0;
        uint32_t field18 = 0;
        uint32_t elementCount = 0;
        if (LoadBe32(base, vertex.descriptor + 20, interpolatorInfo) &&
            LoadBe32(base, vertex.descriptor + 24, field18) &&
            LoadBe32(base, vertex.descriptor + 28, elementCount) &&
            field18 <= 1024 && elementCount <= kMaximumShaderElements) {
            const uint32_t interpolatorCount =
                (interpolatorInfo >> 5) & 0x1Fu;
            const uint64_t elementAddress =
                uint64_t(vertex.descriptor) + uint64_t(field18 + 9) * 4;
            const uint64_t interpolatorAddress =
                elementAddress + uint64_t(elementCount) * 4;
            if (elementAddress <= UINT32_MAX &&
                interpolatorAddress <= UINT32_MAX &&
                IsGuestRangeReadable(uint32_t(elementAddress),
                                     uint64_t(elementCount) * 4) &&
                (interpolatorCount == 0 ||
                 IsGuestRangeReadable(uint32_t(interpolatorAddress),
                                      uint64_t(interpolatorCount) * 4))) {
                command.vertexElementTableAddress = uint32_t(elementAddress);
                command.vertexElementCount = elementCount;
                command.vertexInterpolatorTableAddress =
                    uint32_t(interpolatorAddress);
                command.vertexInterpolatorCount = interpolatorCount;
            }
        }
    }

    // PixelShader is Shader[6 dwords], field18, outputs, then packed
    // Interpolator dwords. XenosRecomp reads these from descriptor +32.
    if (pixel.descriptor) {
        uint32_t interpolatorInfo = 0;
        uint32_t outputs = 0;
        if (LoadBe32(base, pixel.descriptor + 20, interpolatorInfo) &&
            LoadBe32(base, pixel.descriptor + 28, outputs)) {
            const uint32_t interpolatorCount =
                (interpolatorInfo >> 5) & 0x1Fu;
            const uint32_t interpolatorAddress = pixel.descriptor + 32;
            if (interpolatorCount <= kMaximumShaderInterpolators &&
                (interpolatorCount == 0 ||
                 IsGuestRangeReadable(interpolatorAddress,
                                      uint64_t(interpolatorCount) * 4))) {
                command.pixelInterpolatorTableAddress = interpolatorAddress;
                command.pixelInterpolatorCount = interpolatorCount;
                command.pixelOutputs = outputs;
            }
        }
    }
}

uint64_t Mix(uint64_t hash, uint32_t value) {
    hash ^= value;
    hash *= 0x100000001B3ull;
    return hash;
}

void CaptureDrawState(const uint8_t* base, TitleCommand& command, bool forceCapture=false) {
    if (!base || !command.device) {
        return;
    }

    LoadBe32(base, command.device + kDevPixelShaderOffset,
             command.pixelShaderObject);
    LoadBe32(base, command.device + kDevVertexShaderOffset,
             command.vertexShaderObject);

    const UcodeRef ps = command.pixelShaderObject
                            ? ReadPixelShaderUcode(base,
                                                   command.pixelShaderObject)
                            : UcodeRef{};
    const UcodeRef vs = command.vertexShaderObject
                            ? ReadVertexShaderUcode(base,
                                                    command.vertexShaderObject,
                                                    command.pixelShaderObject)
                            : UcodeRef{};
    command.pixelShaderBytes = ps.size;
    command.vertexShaderBytes = vs.size;
    command.pixelShaderAddress = ps.address;
    command.vertexShaderAddress = vs.address;
    if (ps.size) {
        const auto* bytes = rex::memory::GuestPtr<const uint8_t*>(
            const_cast<uint8_t*>(base), ps.address);
        command.pixelShaderIdentity =
            mcla::native_gfx::ShaderIdentity(bytes, ps.size);
    }
    if (vs.size) {
        const auto* bytes = rex::memory::GuestPtr<const uint8_t*>(
            const_cast<uint8_t*>(base), vs.address);
        command.vertexShaderIdentity =
            mcla::native_gfx::ShaderIdentity(bytes, vs.size);
    }

    // Runtime draw submission needs the shader identities, not a duplicate
    // diagnostic snapshot/fingerprint of every fetch and declaration. Keep
    // the full corpus collector available only for explicit oracle runs.
    if (!mcla::DiagnosticsEnabled() || (!ShaderCaptureEnabled() && !forceCapture)) return;
    ReadShaderMetadata(base, vs, ps, command);

    // Preserve a stable identity for the complete MCLA fetch shadow. A later
    // Apple draw consumer can use this to deduplicate decoded declarations;
    // today it also proves that native packets carry title state rather than
    // merely mirroring draw counters.
    const uint32_t fetch = command.device + kDevFetchShadowOffset;
    if (IsGuestRangeReadable(fetch, kFetchShadowBytes)) {
        uint64_t fingerprint = 0xCBF29CE484222325ull;
        uint32_t valid = 0;
        for (uint32_t i = 0; i < kFetchShadowBytes / 4; ++i) {
            const uint32_t word = LoadBe32Unchecked(base, fetch + i * 4);
            fingerprint = Mix(fingerprint, word);
            // Each 6-dword group may contain three 2-dword vertex fetches.
            // Type 3 in the low two bits is a valid vertex binding.
            if ((i % 2) == 0 && (word & 3u) == 3u) {
                ++valid;
            }
        }
        command.fetchFingerprint = fingerprint;
        command.validVertexFetches = valid;
    }

    if (LoadBe32(base, command.device + kDevVertexDeclarationOffset,
                 command.declarationAddress) &&
        command.declarationAddress) {
        LoadBe32(base,
                 command.declarationAddress + kDeclOffsetElementCount,
                 command.declarationElementCount);
        LoadBe32(base, command.declarationAddress + kDeclOffsetMaxStream,
                 command.declarationMaxStream);
        if (command.declarationElementCount <= kMaximumDeclarationElements) {
            const uint32_t bytes = command.declarationElementCount *
                                   kDeclarationRecordBytes;
            const uint32_t records = command.declarationAddress +
                                     kDeclOffsetElements;
            if (bytes && IsGuestRangeReadable(records, bytes)) {
                uint64_t fingerprint = 0xCBF29CE484222325ull;
                for (uint32_t i = 0; i < bytes; ++i) {
                    const auto* byte = rex::memory::GuestPtr<const uint8_t*>(
                        const_cast<uint8_t*>(base), records + i);
                    fingerprint ^= *byte;
                    fingerprint *= 0x100000001B3ull;
                }
                command.declarationFingerprint = fingerprint;
            }
        }
    }

    if (command.indexed) {
        uint32_t indexObject = 0;
        if (LoadBe32(base, command.device + kDevIndexBufferOffset,
                     indexObject) &&
            indexObject) {
            uint32_t descriptor = 0;
            uint32_t address = 0;
            if (LoadBe32(base, indexObject, descriptor) &&
                LoadBe32(base, indexObject + 24, address)) {
                command.indexFormat = (descriptor & 0x80000000u) ? 32u : 16u;
                // MCLA's guest virtual-to-physical conversion from its own
                // D3D draw builder; a plain mask is one page wrong for 0xE0.
                command.indexAddress =
                    (address & 0x1FFFFFFFu) +
                    (((address >> 20) + 512u) & 0x1000u);
            }
        }
    }
}

class NativeTitleBridge {
 public:
    NativeTitleBridge() {
        for (size_t i = 0; i < queue_.size(); ++i) {
            queue_[i].sequence.store(i, std::memory_order_relaxed);
        }
    }

    ~NativeTitleBridge() { Shutdown(); }

    void SetCaptureRoot(const char* path) {
        std::lock_guard lock(captureMutex_);
        captureRoot_ = path && path[0] ? std::filesystem::path(path)
                                      : std::filesystem::path();
        captureKeys_.clear();
        shaderKeys_.clear();
    }

    bool SetMetadataPath(const char* path) {
        if (!path || !path[0]) {
            return false;
        }
        std::ifstream input(path, std::ios::binary | std::ios::ate);
        if (!input) {
            return false;
        }
        const std::streamsize fileSize = input.tellg();
        if (fileSize < 16) {
            return false;
        }
        input.seekg(0);
        std::vector<uint8_t> file(static_cast<size_t>(fileSize));
        if (!input.read(reinterpret_cast<char*>(file.data()), fileSize) ||
            std::memcmp(file.data(), "MVEM", 4) != 0 ||
            LoadLe32(file.data() + 4) != 1u) {
            return false;
        }
        const uint32_t shaderCount = LoadLe32(file.data() + 8);
        const uint32_t referenceCount = LoadLe32(file.data() + 12);
        const uint64_t entriesEnd = 16ull + uint64_t(shaderCount) * 16;
        const uint64_t referencesEnd =
            entriesEnd + uint64_t(referenceCount) * 4;
        if (referencesEnd != file.size()) {
            return false;
        }

        std::unordered_map<uint64_t, std::vector<uint32_t>> decoded;
        decoded.reserve(shaderCount);
        const uint8_t* references = file.data() + entriesEnd;
        uint32_t decodedElements = 0;
        for (uint32_t i = 0; i < shaderCount; ++i) {
            const uint8_t* entry = file.data() + 16 + size_t(i) * 16;
            const uint64_t identity = LoadLe64(entry);
            const uint32_t first = LoadLe32(entry + 8);
            const uint32_t count = LoadLe32(entry + 12);
            if (!identity || first > referenceCount ||
                count > referenceCount - first) {
                return false;
            }
            std::vector<uint32_t> elements;
            elements.reserve(count);
            for (uint32_t j = 0; j < count; ++j) {
                const uint32_t packed =
                    LoadLe32(references + size_t(first + j) * 4);
                if ((packed & 0xFFF00000u) != 0 ||
                    ((packed >> 12) & 0xFu) > 13u) {
                    return false;
                }
                elements.push_back(packed);
            }
            if (!decoded.emplace(identity, std::move(elements)).second) {
                return false;
            }
            decodedElements += count;
        }

        // The app installs this map before the title thread starts, so the
        // renderer worker and lookup API may read it lock-free afterward.
        metadataElements_ = std::move(decoded);
        metadataShaderCount_.store(uint32_t(metadataElements_.size()),
                                   std::memory_order_release);
        metadataElementCount_.store(decodedElements,
                                    std::memory_order_release);
        return true;
    }

    uint32_t CopyVertexElements(uint64_t identity, uint32_t* output,
                                uint32_t capacity) const {
        const auto found = metadataElements_.find(identity);
        if (found == metadataElements_.end()) {
            return 0;
        }
        const uint32_t count = uint32_t(found->second.size());
        if (output && capacity) {
            std::copy_n(found->second.data(), std::min(count, capacity),
                        output);
        }
        return count;
    }

    bool SetShaderPackPath(const char* path) {
        if (!path || !path[0]) {
            return false;
        }
        std::ifstream input(path, std::ios::binary | std::ios::ate);
        if (!input) {
            return false;
        }
        const std::streamsize fileSize = input.tellg();
        if (fileSize < 32 || uint64_t(fileSize) > UINT32_MAX) {
            return false;
        }
        input.seekg(0);
        std::vector<uint8_t> file(static_cast<size_t>(fileSize));
        if (!input.read(reinterpret_cast<char*>(file.data()), fileSize) ||
            std::memcmp(file.data(), "MSPV", 4) != 0 ||
            LoadLe32(file.data() + 4) != 1u) {
            return false;
        }
        const uint32_t entryCount = LoadLe32(file.data() + 8);
        const uint32_t entryStride = LoadLe32(file.data() + 12);
        const uint64_t dataOffset = LoadLe64(file.data() + 16);
        const uint64_t dataSize = LoadLe64(file.data() + 24);
        const uint64_t tableEnd = 32ull + uint64_t(entryCount) * entryStride;
        if (entryStride != 24 || tableEnd > dataOffset ||
            dataOffset + dataSize != file.size()) {
            return false;
        }

        std::unordered_map<uint64_t, NativeShaderPackEntry> vertex;
        std::unordered_map<uint64_t, NativeShaderPackEntry> pixel;
        vertex.reserve(entryCount);
        pixel.reserve(entryCount);
        uint32_t provisional = 0;
        for (uint32_t i = 0; i < entryCount; ++i) {
            const uint8_t* packed = file.data() + 32 + size_t(i) * 24;
            const uint64_t identity = LoadLe64(packed);
            const uint32_t stage = LoadLe32(packed + 8);
            const uint32_t flags = LoadLe32(packed + 12);
            const uint32_t offset = LoadLe32(packed + 16);
            const uint32_t size = LoadLe32(packed + 20);
            if (!identity || stage > 1 || flags > 1 || size < 20 ||
                (size & 3u) != 0 || offset > dataSize ||
                size > dataSize - offset ||
                LoadLe32(file.data() + size_t(dataOffset + offset)) !=
                    0x07230203u) {
                return false;
            }
            NativeShaderPackEntry entry{
                .offset = uint32_t(dataOffset + offset),
                .size = size,
                .flags = flags,
            };
            auto& destination = stage ? pixel : vertex;
            if (!destination.emplace(identity, entry).second) {
                return false;
            }
            provisional += (flags & 1u) != 0;
        }

        // Installed before the title thread starts; the consumer and copy API
        // may read the immutable maps and backing bytes lock-free afterward.
        shaderPackBytes_ = std::move(file);
        vertexSpirv_ = std::move(vertex);
        pixelSpirv_ = std::move(pixel);
        shaderPackVertexCount_.store(uint32_t(vertexSpirv_.size()),
                                     std::memory_order_release);
        shaderPackPixelCount_.store(uint32_t(pixelSpirv_.size()),
                                    std::memory_order_release);
        shaderPackProvisionalCount_.store(provisional,
                                          std::memory_order_release);
        shaderPackByteCount_.store(uint32_t(shaderPackBytes_.size()),
                                   std::memory_order_release);
        return true;
    }

    uint32_t CopyShaderSpirv(uint64_t identity, bool pixelShader,
                             void* output, uint32_t capacityBytes) const {
        const auto& shaders = pixelShader ? pixelSpirv_ : vertexSpirv_;
        const auto found = shaders.find(identity);
        if (found == shaders.end()) {
            return 0;
        }
        const NativeShaderPackEntry& entry = found->second;
        if (output && capacityBytes) {
            std::memcpy(output, shaderPackBytes_.data() + entry.offset,
                        std::min(entry.size, capacityBytes));
        }
        return entry.size;
    }

    void AttachCapture(const uint8_t* base, TitleCommand& command, bool missingOnly=false) {
        if (!mcla::DiagnosticsEnabled() || (!ShaderCaptureEnabled() && !missingOnly)) return;
        if (!base || (!command.vertexShaderIdentity &&
                      !command.pixelShaderIdentity)) {
            return;
        }

        uint64_t key = command.vertexShaderIdentity;
        key ^= command.pixelShaderIdentity + 0x9E3779B97F4A7C15ull +
               (key << 6) + (key >> 2);
        key ^= command.declarationFingerprint + 0x517CC1B727220A95ull +
               (key << 6) + (key >> 2);
        {
            std::lock_guard lock(captureMutex_);
            // Normal play captures only rejected shader combinations, at most
            // 64 per session. Existing full-oracle capture remains opt-in.
            if (missingOnly && captureKeys_.size()>=64) return;
            if (captureRoot_.empty() || !captureKeys_.insert(key).second) {
                return;
            }
        }

        auto payload = std::make_shared<CapturePayload>();
        const auto copyGuest = [&](uint32_t address, uint32_t size,
                                   std::vector<uint8_t>& destination) {
            if (!address || !size || !IsGuestRangeReadable(address, size)) {
                return;
            }
            const auto* source = rex::memory::GuestPtr<const uint8_t*>(
                const_cast<uint8_t*>(base), address);
            destination.assign(source, source + size);
        };
        const auto copyGuestDwordsToLittleEndian =
            [&](uint32_t address, uint32_t count,
                std::vector<uint8_t>& destination) {
                if (!address || !count ||
                    !IsGuestRangeReadable(address, uint64_t(count) * 4)) {
                    return;
                }
                destination.resize(size_t(count) * 4);
                for (uint32_t i = 0; i < count; ++i) {
                    const uint32_t value =
                        LoadBe32Unchecked(base, address + i * 4);
                    uint8_t* output = destination.data() + i * 4;
                    output[0] = uint8_t(value);
                    output[1] = uint8_t(value >> 8);
                    output[2] = uint8_t(value >> 16);
                    output[3] = uint8_t(value >> 24);
                }
            };
        copyGuest(command.vertexShaderAddress, command.vertexShaderBytes,
                  payload->vertexShader);
        copyGuest(command.pixelShaderAddress, command.pixelShaderBytes,
                  payload->pixelShader);
        copyGuestDwordsToLittleEndian(command.vertexElementTableAddress,
                                      command.vertexElementCount,
                                      payload->vertexElements);
        copyGuestDwordsToLittleEndian(command.vertexInterpolatorTableAddress,
                                      command.vertexInterpolatorCount,
                                      payload->vertexInterpolators);
        copyGuestDwordsToLittleEndian(command.pixelInterpolatorTableAddress,
                                      command.pixelInterpolatorCount,
                                      payload->pixelInterpolators);
        if (IsGuestRangeReadable(command.device + kDevFetchShadowOffset,
                                 kFetchShadowBytes)) {
            const auto* source = rex::memory::GuestPtr<const uint8_t*>(
                const_cast<uint8_t*>(base),
                command.device + kDevFetchShadowOffset);
            std::memcpy(payload->fetchShadow.data(), source,
                        payload->fetchShadow.size());
        }
        if (command.declarationAddress &&
            command.declarationElementCount <= kMaximumDeclarationElements) {
            copyGuest(command.declarationAddress + kDeclOffsetElements,
                      command.declarationElementCount *
                          kDeclarationRecordBytes,
                      payload->declaration);
        }
        if (IsGuestRangeReadable(command.device + kDevStreamStrideTableOffset,
                                 kStreamCount)) {
            const auto* source = rex::memory::GuestPtr<const uint8_t*>(
                const_cast<uint8_t*>(base),
                command.device + kDevStreamStrideTableOffset);
            std::memcpy(payload->streamStrides.data(), source,
                        payload->streamStrides.size());
        }
        if (IsGuestRangeReadable(command.device + kDevDeclStrideMirrorOffset,
                                 kStreamCount)) {
            const auto* source = rex::memory::GuestPtr<const uint8_t*>(
                const_cast<uint8_t*>(base),
                command.device + kDevDeclStrideMirrorOffset);
            std::memcpy(payload->patchedStreamStrides.data(), source,
                        payload->patchedStreamStrides.size());
        }
        command.automaticCapture = missingOnly;
        command.capture = std::move(payload);
    }

    bool Submit(const TitleCommand& command, bool wake) {
        EnsureWorker();
        QueueCell* cell = nullptr;
        size_t position = enqueuePosition_.load(std::memory_order_relaxed);
        for (;;) {
            cell = &queue_[position & (kQueueCapacity - 1)];
            const size_t sequence =
                cell->sequence.load(std::memory_order_acquire);
            const intptr_t difference = intptr_t(sequence) - intptr_t(position);
            if (difference == 0) {
                if (enqueuePosition_.compare_exchange_weak(
                        position, position + 1, std::memory_order_relaxed)) {
                    break;
                }
            } else if (difference < 0) {
                dropped_.fetch_add(1, std::memory_order_relaxed);
                return false;
            } else {
                position = enqueuePosition_.load(std::memory_order_relaxed);
            }
        }
        cell->command = command;
        cell->sequence.store(position + 1, std::memory_order_release);
        submitted_.fetch_add(1, std::memory_order_relaxed);
        const uint32_t depth = uint32_t(
            position + 1 - dequeuePosition_.load(std::memory_order_relaxed));
        uint32_t watermark = highWatermark_.load(std::memory_order_relaxed);
        while (watermark < depth &&
               !highWatermark_.compare_exchange_weak(
                   watermark, depth, std::memory_order_relaxed)) {
        }
        if (wake) {
            wake_.notify_one();
        }
        return true;
    }

    void GetReport(MCLANativeTitleBridgeReport& report) const {
        report.submitted = submitted_.load(std::memory_order_relaxed);
        report.processed = processed_.load(std::memory_order_relaxed);
        report.dropped = dropped_.load(std::memory_order_relaxed);
        report.drawIndexed = drawIndexed_.load(std::memory_order_relaxed);
        report.draw = draw_.load(std::memory_order_relaxed);
        report.inlineDraw = inlineDraw_.load(std::memory_order_relaxed);
        report.clears = clears_.load(std::memory_order_relaxed);
        report.resolves = resolves_.load(std::memory_order_relaxed);
        report.frameEnds = frameEnds_.load(std::memory_order_relaxed);
        report.swaps = swaps_.load(std::memory_order_relaxed);
        report.uniqueShaderPairs =
            uniqueShaderPairCount_.load(std::memory_order_relaxed);
        report.captureRecords = captureRecords_.load(std::memory_order_relaxed);
        report.capturedShaders = capturedShaders_.load(std::memory_order_relaxed);
        report.captureFailures = captureFailures_.load(std::memory_order_relaxed);
        report.metadataHits = metadataHits_.load(std::memory_order_relaxed);
        report.metadataMisses = metadataMisses_.load(std::memory_order_relaxed);
        report.shaderPackHits = shaderPackHits_.load(std::memory_order_relaxed);
        report.shaderPackMisses =
            shaderPackMisses_.load(std::memory_order_relaxed);
        report.shaderMatchedDraws =
            shaderMatchedDraws_.load(std::memory_order_relaxed);
        report.shaderIncompleteDraws =
            shaderIncompleteDraws_.load(std::memory_order_relaxed);
        report.metadataShaders =
            metadataShaderCount_.load(std::memory_order_acquire);
        report.metadataElements =
            metadataElementCount_.load(std::memory_order_acquire);
        report.lastMetadataElements =
            lastMetadataElements_.load(std::memory_order_relaxed);
        report.shaderPackVertexShaders =
            shaderPackVertexCount_.load(std::memory_order_acquire);
        report.shaderPackPixelShaders =
            shaderPackPixelCount_.load(std::memory_order_acquire);
        report.shaderPackProvisionalShaders =
            shaderPackProvisionalCount_.load(std::memory_order_acquire);
        report.shaderPackBytes =
            shaderPackByteCount_.load(std::memory_order_acquire);
        report.lastVertexSpirvBytes =
            lastVertexSpirvBytes_.load(std::memory_order_relaxed);
        report.lastPixelSpirvBytes =
            lastPixelSpirvBytes_.load(std::memory_order_relaxed);
        report.lastVertexShader =
            lastVertexShader_.load(std::memory_order_relaxed);
        report.lastPixelShader =
            lastPixelShader_.load(std::memory_order_relaxed);
        report.lastDevice = lastDevice_.load(std::memory_order_relaxed);
        report.lastValidVertexFetches =
            lastValidVertexFetches_.load(std::memory_order_relaxed);
        const size_t enqueue = enqueuePosition_.load(std::memory_order_relaxed);
        const size_t dequeue = dequeuePosition_.load(std::memory_order_relaxed);
        report.queueDepth = uint32_t(enqueue - dequeue);
        report.queueHighWatermark =
            highWatermark_.load(std::memory_order_relaxed);
    }

    void Shutdown() {
        if (!running_.exchange(false, std::memory_order_acq_rel)) {
            return;
        }
        wake_.notify_all();
        if (worker_.joinable()) {
            worker_.join();
        }
    }

 private:
    static std::string Hex64(uint64_t value) {
        std::ostringstream stream;
        stream << std::hex << std::uppercase << std::setw(16)
               << std::setfill('0') << value;
        return stream.str();
    }

    bool WriteBlobIfNew(const std::filesystem::path& path,
                        const std::vector<uint8_t>& bytes,
                        uint64_t shaderKey = 0, bool* created = nullptr) {
        if (created) {
            *created = false;
        }
        if (bytes.empty()) {
            return true;
        }
        if (shaderKey) {
            std::lock_guard lock(captureMutex_);
            if (!shaderKeys_.insert(shaderKey).second) {
                return true;
            }
        }
        std::error_code error;
        std::filesystem::create_directories(path.parent_path(), error);
        if (error) {
            return false;
        }
        if (std::filesystem::exists(path, error) && !error) {
            return true;
        }
        // An interrupted capture must not leave a partial final shader blob
        // that later runs mistake for an already completed capture.
        const std::filesystem::path temporary = path.string()+".tmp";
        std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
        if (!output) {
            return false;
        }
        output.write(reinterpret_cast<const char*>(bytes.data()),
                     std::streamsize(bytes.size()));
        output.close();
        bool ok = !output.fail();
        if (ok) {
            std::filesystem::rename(temporary,path,error);
            ok = !error;
        }
        if (!ok) {
            std::filesystem::remove(temporary,error);
            if (shaderKey) { std::lock_guard lock(captureMutex_); shaderKeys_.erase(shaderKey); }
        }
        if (created) {
            *created = ok;
        }
        return ok;
    }

    bool PersistCapture(const TitleCommand& command) {
        if (!command.capture) {
            return true;
        }
        std::filesystem::path root;
        {
            std::lock_guard lock(captureMutex_);
            root = captureRoot_;
        }
        if (root.empty()) {
            return false;
        }

        std::error_code error;
        std::filesystem::create_directories(root / "shaders", error);
        std::filesystem::create_directories(root / "declarations", error);
        std::filesystem::create_directories(root / "fetch", error);
        std::filesystem::create_directories(root / "metadata", error);
        if (error) {
            return false;
        }

        bool ok = true;
        if (command.vertexShaderIdentity) {
            bool created = false;
            ok &= WriteBlobIfNew(
                root / "shaders" /
                    ("vs-" + Hex64(command.vertexShaderIdentity) + ".bin"),
                command.capture->vertexShader,
                command.vertexShaderIdentity ^ 0x5653000000000000ull,
                &created);
            if (created) {
                capturedShaders_.fetch_add(1, std::memory_order_relaxed);
            }
        }
        if (command.pixelShaderIdentity) {
            bool created = false;
            ok &= WriteBlobIfNew(
                root / "shaders" /
                    ("ps-" + Hex64(command.pixelShaderIdentity) + ".bin"),
                command.capture->pixelShader,
                command.pixelShaderIdentity ^ 0x5053000000000000ull,
                &created);
            if (created) {
                capturedShaders_.fetch_add(1, std::memory_order_relaxed);
            }
        }
        if (command.vertexShaderIdentity) {
            const std::string identity = Hex64(command.vertexShaderIdentity);
            ok &= WriteBlobIfNew(
                root / "metadata" / ("vs-elements-" + identity + ".bin"),
                command.capture->vertexElements,
                command.vertexShaderIdentity ^ 0x56454C454D000000ull);
            ok &= WriteBlobIfNew(
                root / "metadata" /
                    ("vs-interpolators-" + identity + ".bin"),
                command.capture->vertexInterpolators,
                command.vertexShaderIdentity ^ 0x5653494E54000000ull);
        }
        if (command.pixelShaderIdentity) {
            ok &= WriteBlobIfNew(
                root / "metadata" /
                    ("ps-interpolators-" +
                     Hex64(command.pixelShaderIdentity) + ".bin"),
                command.capture->pixelInterpolators,
                command.pixelShaderIdentity ^ 0x5053494E54000000ull);
        }
        if (command.declarationFingerprint &&
            !command.capture->declaration.empty()) {
            ok &= WriteBlobIfNew(
                root / "declarations" /
                    ("decl-" + Hex64(command.declarationFingerprint) + ".bin"),
                command.capture->declaration);
        }
        if (command.fetchFingerprint) {
            const std::vector<uint8_t> fetch(
                command.capture->fetchShadow.begin(),
                command.capture->fetchShadow.end());
            ok &= WriteBlobIfNew(
                root / "fetch" /
                    ("fetch-" + Hex64(command.fetchFingerprint) + ".bin"),
                fetch);
        }

        std::ofstream manifest(root / "manifest.jsonl",
                               std::ios::binary | std::ios::app);
        if (!manifest) {
            return false;
        }
        manifest << "{\"vs\":\"" << Hex64(command.vertexShaderIdentity)
                 << "\",\"ps\":\"" << Hex64(command.pixelShaderIdentity)
                 << "\",\"vs_bytes\":" << command.vertexShaderBytes
                 << ",\"ps_bytes\":" << command.pixelShaderBytes
                 << ",\"vs_elements\":" << command.vertexElementCount
                 << ",\"vs_interpolators\":"
                 << command.vertexInterpolatorCount
                 << ",\"ps_interpolators\":"
                 << command.pixelInterpolatorCount
                 << ",\"ps_outputs\":" << command.pixelOutputs
                 << ",\"decl\":\"" << Hex64(command.declarationFingerprint)
                 << "\",\"decl_elements\":"
                 << command.declarationElementCount
                 << ",\"decl_max_stream\":" << command.declarationMaxStream
                 << ",\"fetch\":\"" << Hex64(command.fetchFingerprint)
                 << "\",\"valid_vfetch\":" << command.validVertexFetches
                 << ",\"primitive\":" << command.primitive
                 << ",\"count\":" << command.count
                 << ",\"start\":" << command.start
                 << ",\"base_vertex\":" << command.baseVertex
                 << ",\"indexed\":" << unsigned(command.indexed)
                 << ",\"index_address\":" << command.indexAddress
                 << ",\"index_bits\":" << command.indexFormat
                 << ",\"stride_table\":\"";
        for (uint8_t byte : command.capture->streamStrides) {
            manifest << std::hex << std::setw(2) << std::setfill('0')
                     << unsigned(byte);
        }
        manifest << "\",\"patched_strides\":\"";
        for (uint8_t byte : command.capture->patchedStreamStrides) {
            manifest << std::hex << std::setw(2) << std::setfill('0')
                     << unsigned(byte);
        }
        manifest << "\"}\n";
        ok &= manifest.good();
        if (ok) {
            captureRecords_.fetch_add(1, std::memory_order_relaxed);
        }
        if (command.automaticCapture)
            REXLOG_INFO("MCLA shader gap capture saved={} vs={:016X} ps={:016X} vs_bytes={} ps_bytes={} root={}",
                ok,command.vertexShaderIdentity,command.pixelShaderIdentity,
                command.capture->vertexShader.size(),command.capture->pixelShader.size(),root.string());
        return ok;
    }

    void EnsureWorker() {
        std::call_once(startOnce_, [this]() {
            running_.store(true, std::memory_order_release);
            worker_ = std::thread([this]() { WorkerMain(); });
        });
    }

    bool TryPop(TitleCommand& command) {
        QueueCell* cell = nullptr;
        size_t position = dequeuePosition_.load(std::memory_order_relaxed);
        for (;;) {
            cell = &queue_[position & (kQueueCapacity - 1)];
            const size_t sequence =
                cell->sequence.load(std::memory_order_acquire);
            const intptr_t difference =
                intptr_t(sequence) - intptr_t(position + 1);
            if (difference == 0) {
                if (dequeuePosition_.compare_exchange_weak(
                        position, position + 1, std::memory_order_relaxed)) {
                    break;
                }
            } else if (difference < 0) {
                return false;
            } else {
                position = dequeuePosition_.load(std::memory_order_relaxed);
            }
        }
        command = cell->command;
        cell->sequence.store(position + kQueueCapacity,
                             std::memory_order_release);
        return true;
    }

    void Process(const TitleCommand& command) {
        if (command.capture && !PersistCapture(command)) {
            captureFailures_.fetch_add(1, std::memory_order_relaxed);
        }
        switch (command.type) {
            case CommandType::kDrawIndexed:
                drawIndexed_.fetch_add(1, std::memory_order_relaxed);
                break;
            case CommandType::kDraw:
                draw_.fetch_add(1, std::memory_order_relaxed);
                break;
            case CommandType::kInlineDraw:
                inlineDraw_.fetch_add(1, std::memory_order_relaxed);
                break;
            case CommandType::kClear:
                clears_.fetch_add(1, std::memory_order_relaxed);
                break;
            case CommandType::kResolve:
            case CommandType::kEndTiling:
                resolves_.fetch_add(1, std::memory_order_relaxed);
                break;
            case CommandType::kFrameEnd:
                frameEnds_.fetch_add(1, std::memory_order_relaxed);
                break;
            case CommandType::kSwap:
                swaps_.fetch_add(1, std::memory_order_relaxed);
                break;
            case CommandType::kBeginTiling:
                break;
        }
        if (command.type == CommandType::kDrawIndexed ||
            command.type == CommandType::kDraw ||
            command.type == CommandType::kInlineDraw) {
            lastVertexShader_.store(command.vertexShaderIdentity,
                                    std::memory_order_relaxed);
            lastPixelShader_.store(command.pixelShaderIdentity,
                                   std::memory_order_relaxed);
            lastDevice_.store(command.device, std::memory_order_relaxed);
            lastValidVertexFetches_.store(command.validVertexFetches,
                                          std::memory_order_relaxed);
            if (command.vertexShaderIdentity) {
                const auto metadata =
                    metadataElements_.find(command.vertexShaderIdentity);
                if (metadata != metadataElements_.end()) {
                    metadataHits_.fetch_add(1, std::memory_order_relaxed);
                    lastMetadataElements_.store(
                        uint32_t(metadata->second.size()),
                        std::memory_order_relaxed);
                } else {
                    metadataMisses_.fetch_add(1, std::memory_order_relaxed);
                    lastMetadataElements_.store(0,
                                                std::memory_order_relaxed);
                }
            }
            bool completeShaderPair = command.vertexShaderIdentity != 0;
            if (command.vertexShaderIdentity) {
                const auto shader =
                    vertexSpirv_.find(command.vertexShaderIdentity);
                if (shader != vertexSpirv_.end()) {
                    shaderPackHits_.fetch_add(1, std::memory_order_relaxed);
                    lastVertexSpirvBytes_.store(shader->second.size,
                                                std::memory_order_relaxed);
                } else {
                    shaderPackMisses_.fetch_add(1, std::memory_order_relaxed);
                    lastVertexSpirvBytes_.store(0,
                                                std::memory_order_relaxed);
                    completeShaderPair = false;
                }
            }
            if (command.pixelShaderIdentity) {
                const auto shader =
                    pixelSpirv_.find(command.pixelShaderIdentity);
                if (shader != pixelSpirv_.end()) {
                    shaderPackHits_.fetch_add(1, std::memory_order_relaxed);
                    lastPixelSpirvBytes_.store(shader->second.size,
                                               std::memory_order_relaxed);
                } else {
                    shaderPackMisses_.fetch_add(1, std::memory_order_relaxed);
                    lastPixelSpirvBytes_.store(0,
                                               std::memory_order_relaxed);
                    completeShaderPair = false;
                }
            } else {
                lastPixelSpirvBytes_.store(0, std::memory_order_relaxed);
            }
            if (completeShaderPair) {
                shaderMatchedDraws_.fetch_add(1, std::memory_order_relaxed);
            } else {
                shaderIncompleteDraws_.fetch_add(1,
                                                 std::memory_order_relaxed);
            }
            if (command.vertexShaderIdentity || command.pixelShaderIdentity) {
                // The pair set is renderer-owned and touched only by this
                // consumer thread, so title draw hooks never take its lock.
                uint64_t key = command.vertexShaderIdentity;
                key ^= command.pixelShaderIdentity + 0x9E3779B97F4A7C15ull +
                       (key << 6) + (key >> 2);
                shaderPairs_.insert(key);
                uniqueShaderPairCount_.store(shaderPairs_.size(),
                                             std::memory_order_relaxed);
            }
        }
        processed_.fetch_add(1, std::memory_order_relaxed);
    }

    void WorkerMain() {
        for (;;) {
            TitleCommand command;
            bool consumed = false;
            while (TryPop(command)) {
                consumed = true;
                Process(command);
            }
            if (!running_.load(std::memory_order_acquire)) {
                while (TryPop(command)) {
                    Process(command);
                }
                return;
            }
            if (!consumed) {
                std::unique_lock lock(wakeMutex_);
                wake_.wait_for(lock, std::chrono::milliseconds(4));
            }
        }
    }

    std::array<QueueCell, kQueueCapacity> queue_{};
    std::atomic<size_t> enqueuePosition_{0};
    std::atomic<size_t> dequeuePosition_{0};
    std::once_flag startOnce_;
    std::atomic<bool> running_{false};
    std::thread worker_;
    std::mutex wakeMutex_;
    std::condition_variable wake_;
    std::unordered_set<uint64_t> shaderPairs_;
    std::unordered_map<uint64_t, std::vector<uint32_t>> metadataElements_;
    std::vector<uint8_t> shaderPackBytes_;
    std::unordered_map<uint64_t, NativeShaderPackEntry> vertexSpirv_;
    std::unordered_map<uint64_t, NativeShaderPackEntry> pixelSpirv_;
    std::mutex captureMutex_;
    std::filesystem::path captureRoot_;
    std::unordered_set<uint64_t> captureKeys_;
    std::unordered_set<uint64_t> shaderKeys_;

    std::atomic<uint64_t> submitted_{0};
    std::atomic<uint64_t> processed_{0};
    std::atomic<uint64_t> dropped_{0};
    std::atomic<uint64_t> drawIndexed_{0};
    std::atomic<uint64_t> draw_{0};
    std::atomic<uint64_t> inlineDraw_{0};
    std::atomic<uint64_t> clears_{0};
    std::atomic<uint64_t> resolves_{0};
    std::atomic<uint64_t> frameEnds_{0};
    std::atomic<uint64_t> swaps_{0};
    std::atomic<uint64_t> uniqueShaderPairCount_{0};
    std::atomic<uint64_t> captureRecords_{0};
    std::atomic<uint64_t> capturedShaders_{0};
    std::atomic<uint64_t> captureFailures_{0};
    std::atomic<uint64_t> metadataHits_{0};
    std::atomic<uint64_t> metadataMisses_{0};
    std::atomic<uint64_t> shaderPackHits_{0};
    std::atomic<uint64_t> shaderPackMisses_{0};
    std::atomic<uint64_t> shaderMatchedDraws_{0};
    std::atomic<uint64_t> shaderIncompleteDraws_{0};
    std::atomic<uint32_t> metadataShaderCount_{0};
    std::atomic<uint32_t> metadataElementCount_{0};
    std::atomic<uint32_t> lastMetadataElements_{0};
    std::atomic<uint32_t> shaderPackVertexCount_{0};
    std::atomic<uint32_t> shaderPackPixelCount_{0};
    std::atomic<uint32_t> shaderPackProvisionalCount_{0};
    std::atomic<uint32_t> shaderPackByteCount_{0};
    std::atomic<uint32_t> lastVertexSpirvBytes_{0};
    std::atomic<uint32_t> lastPixelSpirvBytes_{0};
    std::atomic<uint64_t> lastVertexShader_{0};
    std::atomic<uint64_t> lastPixelShader_{0};
    std::atomic<uint32_t> lastDevice_{0};
    std::atomic<uint32_t> lastValidVertexFetches_{0};
    std::atomic<uint32_t> highWatermark_{0};
};

NativeTitleBridge& Bridge() {
    static NativeTitleBridge bridge;
    return bridge;
}

void SubmitSimple(CommandType type, uint32_t device, uint32_t flags = 0,
                  uint32_t argument0 = 0, uint32_t argument1 = 0,
                  uint32_t argument2 = 0, bool wake = false) {
#if MCLA_DIRECT_METAL
    // The worker records corpus diagnostics, not Metal commands. Normal
    // handwritten-Metal play has no diagnostic consumer for these packets.
    if (!ShaderCaptureEnabled()) return;
#endif
    TitleCommand command;
    command.type = type;
    command.device = device;
    command.flags = flags;
    command.argument0 = argument0;
    command.argument1 = argument1;
    command.argument2 = argument2;
    Bridge().Submit(command, wake);
}

}  // namespace

void MCLANativeTitleBridgeDraw(const uint8_t* base, uint32_t device,
                               uint32_t primitive, uint32_t count,
                               uint32_t start, int32_t baseVertex,
                               bool indexed) {
    TitleCommand command;
    command.type = indexed ? CommandType::kDrawIndexed : CommandType::kDraw;
    command.indexed = indexed ? 1 : 0;
    command.device = device;
    command.primitive = primitive;
    command.count = count;
    command.start = start;
    command.baseVertex = baseVertex;
    CaptureDrawState(base, command);
#if MCLA_NATIVE_TITLE
    if (ShaderCaptureEnabled()) Bridge().AttachCapture(base, command);
    // Persist only newly encountered shader/declaration combinations. This
    // diagnostic consumer does not submit GPU work or invoke the generic CP.
    if (command.capture) Bridge().Submit(command, true);
    const bool missing = MCLANativeDraw(base, device, primitive, count, start, baseVertex, indexed,
                   0, 0, command.vertexShaderIdentity, command.pixelShaderIdentity);
    if (missing && !ShaderCaptureEnabled()) {
        CaptureDrawState(base,command,true);
        Bridge().AttachCapture(base,command,true);
        if (command.capture) Bridge().Submit(command,true);
    }
    return;
#endif
    Bridge().AttachCapture(base, command);
    Bridge().Submit(command, false);
}

void MCLANativeTitleBridgeInlineDraw(const uint8_t* base, uint32_t device,
                                     uint32_t primitive, uint32_t count,
                                     uint32_t stride, uint32_t buffer) {
    TitleCommand command;
    command.type = CommandType::kInlineDraw;
    command.device = device;
    command.primitive = primitive;
    command.count = count;
    command.argument0 = stride;
    command.argument1 = buffer;
    CaptureDrawState(base, command);
#if MCLA_NATIVE_TITLE
    if (ShaderCaptureEnabled()) Bridge().AttachCapture(base, command);
    if (command.capture) Bridge().Submit(command, true);
    const bool missing = MCLANativeDraw(base, device, primitive, count, 0, 0, false,
                   stride, buffer, command.vertexShaderIdentity, command.pixelShaderIdentity);
    if (missing && !ShaderCaptureEnabled()) {
        CaptureDrawState(base,command,true);
        Bridge().AttachCapture(base,command,true);
        if (command.capture) Bridge().Submit(command,true);
    }
    return;
#endif
    Bridge().AttachCapture(base, command);
    Bridge().Submit(command, false);
}

void MCLANativeTitleBridgeClear(const uint8_t*, uint32_t device,
                                uint32_t flags, uint32_t color, float depth,
                                uint32_t stencil) {
    SubmitSimple(CommandType::kClear, device, flags, color,
                 std::bit_cast<uint32_t>(depth), stencil);
}

void MCLANativeTitleBridgeBeginTiling(uint32_t device, uint32_t flags,
                                      uint32_t tiles) {
    SubmitSimple(CommandType::kBeginTiling, device, flags, tiles);
}

void MCLANativeTitleBridgeEndTiling(uint32_t device, uint32_t flags,
                                    uint32_t destinationTexture) {
    SubmitSimple(CommandType::kEndTiling, device, flags, destinationTexture);
}

void MCLANativeTitleBridgeResolve(uint32_t device, uint32_t flags,
                                  uint32_t sourceRect,
                                  uint32_t destinationTexture,
                                  uint32_t destinationPoint,
                                  uint32_t clearColor) {
#if MCLA_DIRECT_METAL
    if (!ShaderCaptureEnabled()) return;
#endif
    TitleCommand command;
    command.type = CommandType::kResolve;
    command.device = device;
    command.flags = flags;
    command.argument0 = sourceRect;
    command.argument1 = destinationTexture;
    command.argument2 = destinationPoint;
    command.start = clearColor;
    Bridge().Submit(command, false);
}

void MCLANativeTitleBridgeFrameEnd(uint32_t device) {
    SubmitSimple(CommandType::kFrameEnd, device, 0, 0, 0, 0, true);
}

void MCLANativeTitleBridgeSwap(uint32_t device) {
    SubmitSimple(CommandType::kSwap, device, 0, 0, 0, 0, true);
}

void MCLANativeTitleBridgeGetReport(MCLANativeTitleBridgeReport* report) {
    if (report) {
        Bridge().GetReport(*report);
    }
}

void MCLANativeTitleBridgeSetCaptureRoot(const char* path) {
    Bridge().SetCaptureRoot(path);
}

bool MCLANativeTitleBridgeSetMetadataPath(const char* path) {
    return Bridge().SetMetadataPath(path);
}

bool MCLANativeTitleBridgeSetShaderPackPath(const char* path) {
    return Bridge().SetShaderPackPath(path);
}

uint32_t MCLANativeTitleBridgeCopyShaderSpirv(uint64_t shaderIdentity,
                                              bool pixelShader,
                                              void* output,
                                              uint32_t capacityBytes) {
    return Bridge().CopyShaderSpirv(shaderIdentity, pixelShader, output,
                                    capacityBytes);
}

uint32_t MCLANativeTitleBridgeCopyVertexElements(uint64_t shaderIdentity,
                                                 uint32_t* output,
                                                 uint32_t capacity) {
    return Bridge().CopyVertexElements(shaderIdentity, output, capacity);
}

void MCLANativeTitleBridgeShutdown() { Bridge().Shutdown(); }
