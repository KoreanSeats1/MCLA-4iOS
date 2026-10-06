#include "MCLADiagnostics.h"
// Hand-written MCLA title renderer. No command processor, Vulkan or MoltenVK.
// Title decoding/math is adapted from the isolated Theft4/ReXGlue foundation.
#include "MCLAMetalRenderer.h"
#include "MCLAConstantSnapshot.h"
#include "MCLADrawReuse.h"
#include "MCLAEncoderState.h"
#include "MCLAResourceBindingReuse.h"
#include "MCLAGeometryScratch.h"
#include "MCLAVertexFixup.h"
#include "MCLAPackedTexture.h"
#include "MCLATextureSwizzle.h"
#include "MCLAVisualExperiments.h"
#include "MCLAControlOverhaul.h"
#include "MCLAMetalVertexColor.h"
#include "MCLAFastHash.h"
#include "MCLAThreadCPUTiming.h"
#include "MCLAGPUPassTrace.h"
#include "MCLAResourceCacheIndex.h"
#include "MCLAMetalTextureKey.h"
#include "MCLAMetalTextureValidation.h"
#include "MCLAMetalSampler.h"
#include "MCLAMetalPixelCenter.h"
#include "MCLAMetalPixelHistory.h"
#include "MCLAMetalRasterState.h"
#include "MCLAMetalPresentation.h"
#include "MCLAGraphicsFoundation.h"
#include "MCLABootstrapSubsystems.h"
#include "MCLAMetalHelpers.h"
#include "MCLANativeRenderer.h"
#include "MCLAQuadVertexFetch.h"
#include "MCLARuntimeBootstrap.h"
#include "mcla_metal_shader_info.h"
#include "native_buffer_metadata.h"
#include "native_color_output.h"
#include "native_frame_scheduling.h"
#include "native_shader_booleans.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstring>
#include <map>
#include <mutex>
#include <rex/graphics/gta4_native/surface_view.h>
#include <rex/graphics/gta4_native/title_commands.h>
#include <rex/graphics/pipeline/texture/conversion.h>
#include <rex/graphics/pipeline/texture/info.h>
#include <rex/graphics/pipeline/texture/util.h>
#include <rex/logging.h>
#include <rex/memory.h>
#include <rex/system/function_dispatcher.h>
#include <rex/system/interfaces/graphics.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#if MCLA_SMAA_LAB
#include <postfx/smaa/AreaTex.h>
#include <postfx/smaa/SearchTex.h>
#endif

namespace {
namespace ng = rex::graphics::gta4_native;
namespace gx = rex::graphics;
namespace xn = rex::graphics::xenos;
constexpr unsigned kFlights = 3;
uint32_t R(const uint8_t *p, size_t o = 0) {
  uint32_t v;
  memcpy(&v, p + o, 4);
  return __builtin_bswap32(v);
}
float F(const uint8_t *p, size_t o) { return std::bit_cast<float>(R(p, o)); }
void SwapWords(uint8_t *out, const uint8_t *in, size_t n) {
  for (size_t i = 0; i + 4 <= n; i += 4) {
    uint32_t v = R(in, i);
    memcpy(out + i, &v, 4);
  }
}
uint32_t SwapConstantRegisters(uint8_t *out, const uint8_t *in,
                               const uint64_t masks[4]) {
  uint32_t copied = 0;
  for (unsigned bank = 0; bank < 4; ++bank)
    for (uint64_t remaining = masks[bank]; remaining;
         remaining &= remaining - 1) {
      const unsigned reg = bank * 64 + std::countr_zero(remaining);
      SwapWords(out + reg * 16, in + reg * 16, 16);
      ++copied;
    }
  return copied;
}
uint64_t Hash(const void *p, size_t n, uint64_t h = 14695981039346656037ull) {
  return mcla::metal::FastHash(p, n, h);
}
uint32_t Semantic(uint8_t usage, uint8_t index) {
  if ((usage == 0 || usage == 9) && index < 4)
    return index;
  if (usage == 3 && index < 4)
    return 4 + index;
  if (usage == 6 && index < 4)
    return 8 + index;
  if (usage == 7 && index == 0)
    return 12;
  if (usage == 5)
    return index < 4 ? 13 + index : 16 + index;
  if (usage == 10)
    return index ? 32 : 17;
  if (usage == 2)
    return 18;
  if (usage == 1)
    return 19;
  return UINT32_MAX;
}
MTLVertexFormat VertexFormat(uint32_t t, uint32_t numeric, bool packedColorCorrection) {
  switch (t) {
  case 0x2C83A4:
    return MTLVertexFormatFloat;
  case 0x2C23A5:
    return MTLVertexFormatFloat2;
  case 0x2A23B9:
    return MTLVertexFormatFloat3;
  case 0x1A23A6:
    return MTLVertexFormatFloat4;
  case 0x182886:
    return mcla::metal::PackedColorVertexFormat(numeric, packedColorCorrection);
  case 0x1A2286:
  case 0x1A2386:
    return MTLVertexFormatUChar4;
  case 0x1A2086:
  case 0x1A2186:
    return MTLVertexFormatUChar4Normalized;
  case 0x2C2359:
    return MTLVertexFormatShort2;
  case 0x1A235A:
    return MTLVertexFormatShort4;
  case 0x2C2159:
    return MTLVertexFormatShort2Normalized;
  case 0x1A215A:
    return MTLVertexFormatShort4Normalized;
  case 0x2C2059:
    return MTLVertexFormatUShort2Normalized;
  case 0x1A205A:
    return MTLVertexFormatUShort4Normalized;
  case 0x2C235F:
    return MTLVertexFormatHalf2;
  case 0x1A2360:
    return MTLVertexFormatHalf4;
  case 0x1A2187:
    return MTLVertexFormatInt1010102Normalized;
  case 0x2C82A1:
  case 0x2A2287:
  case 0x2A2187:
  case 0x2A2190:
  case 0x2A2390:
    return MTLVertexFormatUInt;
  default:
    return MTLVertexFormatInvalid;
  }
}
unsigned HalfCount(uint32_t t) {
  switch (t) {
  case 0x2C2359:
  case 0x2C2159:
  case 0x2C2059:
  case 0x2C235F:
    return 2;
  case 0x1A235A:
  case 0x1A215A:
  case 0x1A205A:
  case 0x1A2360:
    return 4;
  default:
    return 0;
  }
}
MTLPixelFormat Format(uint32_t f) {
  switch (f) {
  case 2:
  case 8:
  case 9:
  case 59:
    return MTLPixelFormatR8Unorm;
  case 10:
  case 49:
  case 60:
    return MTLPixelFormatRG8Unorm;
  case 3:
  case 6:
  case 7:
  case 18:
  case 19:
  case 20:
  case 58:
    return f == 7 ? MTLPixelFormatRGB10A2Unorm : MTLPixelFormatRGBA8Unorm;
  case 30:
    return MTLPixelFormatR16Float;
  case 31:
    return MTLPixelFormatRG16Float;
  case 32:
    return MTLPixelFormatRGBA16Float;
  case 36:
    return MTLPixelFormatR32Float;
  case 22:
  case 23:
    return MTLPixelFormatDepth32Float_Stencil8;
  default:
    return MTLPixelFormatInvalid;
  }
}
// Resolve destinations produced by the title stay in Metal texture storage
// and are sampled through their Xenos fetch descriptors; they don't need to
// retain the guest's packed byte layout. Expand 1:5:5:5 to a renderable RGBA8
// target, preserving its normalized color/alpha semantics while avoiding a
// packed format that Apple GPUs can't use as a color attachment.
MTLPixelFormat ResolveFormat(uint32_t f) {
  return f == uint32_t(xn::TextureFormat::k_1_5_5_5)
             ? MTLPixelFormatRGBA8Unorm
             : Format(f);
}
unsigned PixelBytes(MTLPixelFormat f) {
  switch (f) {
  case MTLPixelFormatR8Unorm:
    return 1;
  case MTLPixelFormatRG8Unorm:
  case MTLPixelFormatR16Float:
    return 2;
  case MTLPixelFormatRGBA16Float:
    return 8;
  default:
    return 4;
  }
}
MTLPixelFormat SurfaceFormat(uint32_t f, bool depth) {
  if (depth)
    return MTLPixelFormatDepth32Float_Stencil8;
  switch (f) {
  case 0x18280186:
  case 0x18287F86:
    return MTLPixelFormatRGBA8Unorm;
  case 0x1A2201BF:
  case 0x1A22AB60:
    return MTLPixelFormatRGBA16Float;
  case 0x2DA2ABA4:
    return MTLPixelFormatR32Float;
  case 0x2D22AB9F:
  case 0x2D20AB8D:
    return MTLPixelFormatRG16Float;
  default:
    return MTLPixelFormatInvalid;
  }
}
MTLBlendFactor BlendFactor(uint32_t f) {
  switch (f) {
  case 0:
    return MTLBlendFactorZero;
  case 1:
    return MTLBlendFactorOne;
  case 4:
    return MTLBlendFactorSourceColor;
  case 5:
    return MTLBlendFactorOneMinusSourceColor;
  case 6:
    return MTLBlendFactorSourceAlpha;
  case 7:
    return MTLBlendFactorOneMinusSourceAlpha;
  case 8:
    return MTLBlendFactorDestinationColor;
  case 9:
    return MTLBlendFactorOneMinusDestinationColor;
  case 10:
    return MTLBlendFactorDestinationAlpha;
  case 11:
    return MTLBlendFactorOneMinusDestinationAlpha;
  case 12:
    return MTLBlendFactorBlendColor;
  case 13:
    return MTLBlendFactorOneMinusBlendColor;
  case 14:
    return MTLBlendFactorBlendAlpha;
  case 15:
    return MTLBlendFactorOneMinusBlendAlpha;
  case 16:
    return MTLBlendFactorSourceAlphaSaturated;
  default:
    return MTLBlendFactorOne;
  }
}
MTLBlendOperation BlendOp(uint32_t op) {
  static const MTLBlendOperation ops[] = {
      MTLBlendOperationAdd, MTLBlendOperationSubtract, MTLBlendOperationMin,
      MTLBlendOperationMax, MTLBlendOperationReverseSubtract};
  return ops[std::min(op, 4u)];
}
MTLStencilOperation StencilOp(uint32_t op) {
  static const MTLStencilOperation ops[] = {
      MTLStencilOperationKeep,           MTLStencilOperationZero,
      MTLStencilOperationReplace,        MTLStencilOperationIncrementClamp,
      MTLStencilOperationDecrementClamp, MTLStencilOperationInvert,
      MTLStencilOperationIncrementWrap,  MTLStencilOperationDecrementWrap};
  return ops[op & 7];
}

// BC1/2/3 -> RGBA8 avoids relying on desktop-only compressed texture formats.
void DecodeBC(const uint8_t *p, unsigned format, uint8_t *dst, size_t pitch) {
  const uint8_t *c = p + (format == 18 ? 0 : 8);
  uint16_t a = c[0] | (c[1] << 8), b = c[2] | (c[3] << 8);
  uint8_t colors[4][4]{};
  auto rgb = [](uint16_t x, uint8_t *o) {
    o[0] = ((x >> 11) * 255 + 15) / 31;
    o[1] = (((x >> 5) & 63) * 255 + 31) / 63;
    o[2] = ((x & 31) * 255 + 15) / 31;
    o[3] = 255;
  };
  rgb(a, colors[0]);
  rgb(b, colors[1]);
  for (int k = 0; k < 3; ++k) {
    if (a > b || format != 18) {
      colors[2][k] = (2 * colors[0][k] + colors[1][k]) / 3;
      colors[3][k] = (colors[0][k] + 2 * colors[1][k]) / 3;
    } else
      colors[2][k] = (colors[0][k] + colors[1][k]) / 2;
  }
  colors[2][3] = 255;
  colors[3][3] = (a > b || format != 18) ? 255 : 0;
  uint32_t indices = c[4] | c[5] << 8 | c[6] << 16 | uint32_t(c[7]) << 24;
  uint8_t alpha[8] = {p[0], p[1]};
  uint64_t abits = 0;
  if (format == 20) {
    for (int k = 0; k < 6; ++k)
      abits |= uint64_t(p[k + 2]) << (8 * k);
    if (alpha[0] > alpha[1]) {
      for (int k = 2; k < 8; ++k)
        alpha[k] = ((8 - k) * alpha[0] + (k - 1) * alpha[1]) / 7;
    } else {
      for (int k = 2; k < 6; ++k)
        alpha[k] = ((6 - k) * alpha[0] + (k - 1) * alpha[1]) / 5;
      alpha[6] = 0;
      alpha[7] = 255;
    }
  }
  for (int y = 0; y < 4; ++y)
    for (int x = 0; x < 4; ++x) {
      int i = y * 4 + x;
      auto o = dst + y * pitch + x * 4;
      memcpy(o, colors[(indices >> (i * 2)) & 3], 4);
      if (format == 19)
        o[3] = ((p[i / 2] >> (4 * (i % 2))) & 15) * 17;
      if (format == 20)
        o[3] = alpha[(abits >> (i * 3)) & 7];
    }
}

struct Upload {
  id<MTLBuffer> buffer = nil;
  size_t offset = 0;
  uint8_t *cpu = nullptr;
  uint64_t address() const { return buffer.gpuAddress + offset; }
};
struct Flight {
  id<MTLCounterSampleBuffer> counters = nil;
  dispatch_semaphore_t available = dispatch_semaphore_create(1);
  std::vector<id<MTLBuffer>> blocks;
  size_t block = 0, offset = 0;
};
struct Shader {
  const MCLAMetalShaderInfo *info = nullptr;
  id<MTLLibrary> library = nil;
  std::map<uint32_t, id<MTLFunction>> functions;
};
struct Texture {
  id<MTLTexture> image = nil;
  std::array<uint32_t, 6> fetch{};
  bool produced = false;
  uint32_t sceneFlags = 0;
  uint64_t frame = 0;
  std::vector<mcla::metal::TextureBlockSample> samples;
  uint64_t verifiedFrame = UINT64_MAX;
  // Diagnostic only: a touched mip is not proof of full region/slice coverage.
  uint64_t touchedMips = 0;
};
struct Surface {
  id<MTLTexture> image = nil;
  ng::SurfaceDescriptor desc{};
};

uint64_t SurfaceStorageKey(const ng::SurfaceDescriptor &desc,
                           MTLPixelFormat format) {
  const std::array<uint32_t, 5> fields{
      desc.address & 2047u, desc.base & 16383u, desc.width, desc.height,
      uint32_t(format)};
  return Hash(fields.data(), sizeof(fields));
}
struct Buffer {
  id<MTLBuffer> buffer = nil;
  uint32_t address = 0, size = 0;
  uint64_t frame = 0;
};
struct IndexBuffer {
  id<MTLBuffer> buffer = nil;
  uint32_t count = 0;
  uint64_t frame = 0;
};
struct VertexUpload {
  id<MTLBuffer> buffer = nil;
  size_t offset = 0;
  explicit operator bool() const { return buffer != nil; }
};
struct DynamicVertexUpload {
  VertexUpload upload{};
  std::vector<uint8_t> shadow;
  size_t validationOffset = 0;
};
struct PreparedPipeline {
  id<MTLRenderPipelineState> pipeline=nil;
  std::array<bool,17> needed{};
};
struct DisplayTiming {
  std::mutex mutex;
  std::vector<double> times;
};

std::vector<uint8_t>
ExpandRectangles(const std::vector<uint8_t> &input, unsigned stride,
                 const ng::RegisterVertexDeclarationCommand &declaration) {
  if (!stride || input.size() % (3 * stride))
    return {};
  std::vector<uint8_t> out(input.size() / 3 * 4);
  unsigned position = UINT32_MAX;
  for (unsigned i = 0; i < declaration.element_count; ++i) {
    auto e = declaration.elements[i];
    if (e.stream == 0 && Semantic(e.usage, e.usage_index) == 0 &&
        e.offset + 8 <= stride)
      position = e.offset;
  }
  for (size_t rect = 0; rect < input.size() / (3 * stride); ++rect) {
    const uint8_t *v[3] = {input.data() + rect * 3 * stride,
                           input.data() + (rect * 3 + 1) * stride,
                           input.data() + (rect * 3 + 2) * stride};
    unsigned first = 0;
    float longest = -1;
    if (position != UINT32_MAX)
      for (unsigned k = 0; k < 3; ++k) {
        float a[2], b[2];
        memcpy(a, v[(k + 1) % 3] + position, 8);
        memcpy(b, v[(k + 2) % 3] + position, 8);
        float length =
            (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]);
        if (length > longest) {
          longest = length;
          first = k;
        }
      }
    auto a = v[first], b = v[(first + 1) % 3], c = v[(first + 2) % 3];
    auto dst = out.data() + rect * 4 * stride;
    memcpy(dst, a, stride);
    memcpy(dst + stride, b, stride);
    memcpy(dst + 2 * stride, c, stride);
    memcpy(dst + 3 * stride, c, stride);
    for (unsigned i = 0; i < declaration.element_count; ++i) {
      auto e = declaration.elements[i];
      if (e.stream)
        continue;
      unsigned n = e.type == 0x2C83A4   ? 1
                   : e.type == 0x2C23A5 ? 2
                   : e.type == 0x2A23B9 ? 3
                   : e.type == 0x1A23A6 ? 4
                                        : 0;
      if (e.usage == 5 && n == 1 && e.offset + 8 <= stride)
        n = 2;
      if (e.offset + n * 4 > stride)
        continue;
      for (unsigned j = 0; j < n; ++j) {
        size_t off = e.offset + j * 4;
        float x, y, z;
        memcpy(&x, a + off, 4);
        memcpy(&y, b + off, 4);
        memcpy(&z, c + off, 4);
        float value = y - x + z;
        memcpy(dst + 3 * stride + off, &value, 4);
      }
    }
  }
  return out;
}

class MetalRenderer final : public rex::system::IGraphicsSystem {
  rex::memory::Memory *memory_ = nullptr;
  id<MTLDevice> device_ = nil;
  id<MTLCommandQueue> queue_ = nil;
  id<MTLCommandBuffer> commands_ = nil;
  id<MTLRenderCommandEncoder> encoder_ = nil;
  CAMetalLayer *layer_ = nil;
  id<MTLLibrary> helpers_ = nil;
  id<MTLLibrary> fsr_ = nil;
  id<MTLSamplerState> fsrSampler_ = nil;
  bool frameFSREnabled_ = true;
  std::array<id<MTLTexture>,kFlights> fsrTargets_{};
#if MCLA_SMAA_LAB
  id<MTLLibrary> smaa_ = nil;
  id<MTLTexture> smaaArea_ = nil;
  id<MTLTexture> smaaSearch_ = nil;
  id<MTLSamplerState> smaaLinear_ = nil;
  id<MTLSamplerState> smaaPoint_ = nil;
  std::array<std::array<id<MTLTexture>,3>,kFlights> smaaTargets_{};
  std::array<id<MTLRenderPipelineState>,3> smaaPipelines_{};
  bool smaaEnabled_ = false;
  uint64_t smaaFrames_ = 0;
#endif
  std::array<Flight, kFlights> flights_;
  std::shared_ptr<mcla::metal::GPUPassTrace> gpuPassTrace_;
  bool gpuCountersSupported_ = false;
  int gpuPassTraceStatus_ = 0;
  unsigned slot_ = 0;
  std::map<uint64_t, Shader> shaders_;
  std::unordered_map<uint32_t, uint64_t> shaderHandles_;
  std::unordered_map<uint32_t, ng::RegisterVertexDeclarationCommand>
      declarations_;
  std::array<ng::SetVertexStreamCommand, 17> streams_{};
  std::unordered_map<uint64_t, Buffer> buffers_;
  mcla::metal::ResourceCacheIndex bufferIndex_;
  std::unordered_map<uint64_t, IndexBuffer> indexBuffers_;
  mcla::metal::ResourceCacheIndex indexBufferIndex_;
  std::unordered_map<uint64_t, DynamicVertexUpload> dynamicVertexUploads_;
  std::unordered_map<uint64_t, Upload> dynamicIndexUploads_;
  mcla::metal::GeometryScratch<uint8_t> vertexScratch_{4*1024*1024};
  mcla::metal::GeometryScratch<uint32_t> indexScratch_{1024*1024};
  mcla::metal::GeometryScratch<uint32_t> expandedIndexScratch_{1024*1024};
  bool reuseGeometryScratch_ = true;
  struct ConstantBank {
    mcla::metal::ConstantSnapshot snapshot;
    Upload upload;
  };
  std::array<ConstantBank,2> constantBanks_;
  uint64_t constantBankReuses_ = 0, constantBankUploads_ = 0;
  // Guest texture wrapper objects are extremely short lived in MCLA. Keep
  // GPU-produced resolves addressable by their authoritative wrapper, but
  // share decoded guest-memory textures by their fetch/content identity.
  // Otherwise a busy scene creates thousands of identical MTLTextures while
  // Metal validation walks every allocation on every draw.
  std::unordered_map<uint32_t, Texture> textures_;
  std::unordered_map<uint64_t, Texture> sourceTextures_;
  mcla::metal::ResourceCacheIndex sourceTextureIndex_;
  struct TextureBinding {
    uint64_t frame = UINT64_MAX;
    uint64_t serial = 0;
    uint32_t handle = 0;
    std::array<uint32_t, 6> fetch{};
    id<MTLTexture> image = nil;
    bool produced = false;
    uint32_t sceneFlags = 0;
    uint64_t textureID = 0, samplerID = 0;
    unsigned kind = 0;
    bool material = false;
  };
  std::array<TextureBinding, 26> textureBindings_{};
  uint64_t textureBindingSerial_ = 0;
  uint64_t textureBindingHits_ = 0;
  uint64_t textureBindingLookups_ = 0;
  std::unordered_map<uint64_t, Surface> surfaces_;
  std::unordered_map<uint64_t, id<MTLRenderPipelineState>> pipelines_;
  std::unordered_map<uint64_t, PreparedPipeline> prepared_;
  uint64_t declarationRevision_ = 0, resourceRevision_ = 0;
  std::unordered_map<uint32_t,uint64_t> declarationVersions_;
  uint64_t currentDeclarationVersion_ = 0;
  mcla::metal::ExactDrawKey<20> lastPipelineKey_;
  PreparedPipeline lastPrepared_{};
  struct AttachmentReuse {
    uint32_t handle = 0;
    uint64_t revision = UINT64_MAX;
    std::array<uint8_t,44> bytes{};
    ng::SurfaceDescriptor desc{};
    id<MTLTexture> image = nil;
  };
  std::array<AttachmentReuse,5> attachmentReuse_{};
  struct VertexReuse {
    mcla::metal::ExactDrawKey<10> key;
    VertexUpload upload;
  };
  std::array<VertexReuse,17> vertexReuse_{};
  std::array<VertexUpload,17> boundVertices_{};
  mcla::metal::ExactDrawKey<9> lastIndexKey_;
  Upload lastIndexUpload_{};
  uint32_t lastIndexCount_ = 0;
  struct TextureGroup {
    mcla::metal::ExactDrawKey<95> key;
    mcla::metal::TextureGroupSnapshot usedSlots;
    Upload heaps;
    std::array<uint8_t,520> indices{};
    std::array<uint8_t,104> lods{};
  } textureGroup_;
  Upload boundHeaps_{};
  mcla::metal::ExactByteSnapshot<1056> sharedConstantsSnapshot_;
  Upload sharedConstantsUpload_{};
  mcla::metal::ExactDrawKey<3> boundPushAddresses_;
  bool optimizeBindings_ = true;
  uint64_t sharedConstantUploads_=0, sharedConstantReuses_=0,
           pushAddressCalls_=0, pushAddressSkips_=0;
  uint64_t attachmentReuses_=0, pipelineReuses_=0, vertexReuses_=0,
           indexReuses_=0, textureGroupReuses_=0, vertexBindSkips_=0;
  std::unordered_map<uint64_t, id<MTLDepthStencilState>> depths_;
  std::unordered_map<uint64_t, id<MTLSamplerState>> samplers_;
  // Resources referenced only through GPU addresses in the small argument
  // heaps must be declared resident. Metal requires that declaration once per
  // render encoder, not once per draw. Busy MCLA scenes bind thousands of
  // draws with heavily repeated textures, so deduplicate by GPU resource ID.
  std::unordered_set<uint64_t> encoderReadResources_;
  uint64_t resourceDeclarations_ = 0;
  uint64_t resourceDeclarationSkips_ = 0;
  uint64_t constantRegistersUploaded_ = 0;
  std::array<id<MTLTexture>, 4> colors_{};
  std::array<ng::SurfaceDescriptor,4> drawSurfaces_{};
  ng::SurfaceDescriptor drawDepthSurface_{};
  std::array<uint8_t,5*256> heapTemplate_{};
  id<MTLTexture> depth_ = nil;
  id<MTLRenderPipelineState> boundPipeline_ = nil;
  id<MTLDepthStencilState> boundDepthState_ = nil;
  mcla::metal::EncoderState<uint32_t,7> preparedDepthKey_;
  id<MTLDepthStencilState> preparedDepthState_ = nil;
  mcla::metal::EncoderState<uint32_t,2> stencilReferences_;
  mcla::metal::EncoderState<uint32_t,1> winding_, culling_;
  mcla::metal::EncoderState<float,3> depthBias_;
  mcla::metal::EncoderState<double,6> viewport_;
  mcla::metal::EncoderState<NSUInteger,4> scissor_;
  mcla::metal::EncoderState<float,4> blendColor_;
  bool optimizeDrawState_ = true;
  uint64_t dynamicStateCalls_ = 0, dynamicStateSkips_ = 0,
           depthLookupReuses_ = 0;
  template <class T, size_t N>
  bool UpdateDynamic(mcla::metal::EncoderState<T,N>& cache,
                     const std::array<T,N>& value) {
    const bool changed = !optimizeDrawState_ || cache.Update(value);
    if (changed) ++dynamicStateCalls_; else ++dynamicStateSkips_;
    return changed;
  }
  id<MTLTexture> fallback_[4] = {nil, nil, nil, nil};
  id<MTLSamplerState> fallbackSampler_ = nil;
  uint32_t vs_ = 0, ps_ = 0, decl_ = 0, index_ = 0, currentPrimitive_ = 0;
  uint64_t frames_ = 0, draws_ = 0, failed_ = 0, resolves_ = 0;
  std::map<std::string,uint64_t> failuresByReason_;
  std::unordered_map<uint32_t, uint64_t> invalidResolveFormats_;
  std::atomic<uint64_t> completed_{0}, gpuErrors_{0};
  double epoch_ = 0;
  double lastPresentSubmitTime_ = 0;
  double frameSlotWaitMS_ = 0, frameCommandMS_ = 0;
  uint64_t frameUploadBytes_ = 0;
  double frameInvalidationMS_ = 0, frameCacheMaintenanceMS_ = 0;
  uint64_t frameInvalidationCalls_ = 0, frameInvalidatedKeys_ = 0;
  uint64_t frameCacheEvictions_ = 0, frameAliasRemovals_ = 0;
  std::array<uint64_t,3> evictionsSinceLog_{};
  unsigned cacheMaintenanceTurn_ = 0;
  std::shared_ptr<DisplayTiming> displayTiming_=std::make_shared<DisplayTiming>();
  std::mutex timingMutex_;
  std::vector<double> gpuMS_, presentTimes_;
  bool capture_ = false;
  bool profile_ = false;
  bool baseProfile_ = false;
  bool performanceCaptureWasActive_ = false;
  mcla::metal::ThreadCPUSample submissionThreadStart_{};
  float submissionThreadWallMS_ = -1, submissionThreadCPUMS_ = -1;
  std::array<double,9> frameProfileWallMS_{}, frameProfileCPUMS_{};
  uint32_t frameProfileSamples_ = 0;
  uint64_t passCaptureFrame_ = UINT64_MAX;
  uint64_t hudTraceFrame_ = UINT64_MAX;
  bool hudSafeFrameProbe_ = true;
  unsigned passCaptureCount_ = 0;
  size_t passCaptureBytes_ = 0;
  // Opt-in, process-local A/B controls. Normal launches never read this file
  // and never substitute inputs. Tokens switch only between whole frames.
  bool renderProbe_ = false;
  NSString *probeMode_ = @"baseline";
  uint64_t probeToken_ = 0, probeOverrides_ = 0;
  id<MTLTexture> probeNeutralCollector_ = nil;
  id<MTLSamplerState> probeNeutralSampler_ = nil;
  std::unordered_set<uint64_t> probeCapturedInputs_;
  std::unordered_set<uint64_t> probeLoggedMips_;
  mcla::metal::PixelHistory pixelHistory_;
  std::array<double,9> profileMS_{};
  uint64_t decodedTextures_=0;
  uint64_t textureChecks_ = 0, staleTextures_ = 0, textureFallbacks_ = 0;
  std::unordered_map<std::string,uint64_t> textureFailureReasons_;
  uint64_t gammaBindings_ = 0;
  uint64_t resolveShapeFallbacks_ = 0;
  uint64_t profileSamples_=0;
  unsigned filterMode_=0;
  unsigned bloomMode_=0;
  float bloomStrength_=0.65f;
  mcla::metal::PresentationClock presentationClock_;
  bool Fail(const char *why) {
    ++failed_;
    if (++failuresByReason_[why] <= 3)
      REXLOG_ERROR("MCLA METAL rejected {} vs={:016X} ps={:016X}", why,
                   shaderHandles_[vs_], shaderHandles_[ps_]);
    return false;
  }
  const uint8_t *P(uint32_t a, size_t bytes = 4) {
    if (a < 4096 || uint64_t(a) + bytes > 0x100000000ull)
      return nullptr;
    auto h = memory_->LookupHeap(a);
    if (!h || h->QueryRangeAccess(a, uint32_t(a + bytes - 1)) ==
                  rex::memory::PageAccess::kNoAccess)
      return nullptr;
    return memory_->TranslateVirtual<const uint8_t *>(a);
  }
  const uint8_t *ReadableTextureBlock(uint32_t address, uint32_t size) {
    if (!size || uint64_t(address) + size > 0x20000000ull) return nullptr;
    // Physical allocations may belong to any one of the three alias heaps.
    for (uint32_t alias : {0xA0000000u, 0xC0000000u, 0xE0000000u}) {
      if (P(alias | address, size))
        return memory_->TranslatePhysical<const uint8_t *>(address);
    }
    return nullptr;
  }
  bool Begin() {
    if (commands_)
      return true;
    auto &f = flights_[slot_];
    const double waitStart = CACurrentMediaTime();
    dispatch_semaphore_wait(f.available, DISPATCH_TIME_FOREVER);
    frameSlotWaitMS_ += (CACurrentMediaTime() - waitStart) * 1000;
    f.block = 0;
    f.offset = 0;
    dynamicVertexUploads_.clear();
    dynamicIndexUploads_.clear();
    for (auto& bank : constantBanks_) bank.snapshot.Reset();
    sharedConstantsSnapshot_.Reset();
    sharedConstantsUpload_ = {};
    commands_ = [queue_ commandBuffer];
    if (!commands_) {
      dispatch_semaphore_signal(f.available);
      return false;
    }
    commands_.label = @"MCLA handwritten Metal frame";
    gpuPassTrace_.reset();gpuPassTraceStatus_=0;
    if(MCLAGraphicsPerformanceCaptureActive() && frames_%30==0) {
      if(!gpuCountersSupported_)gpuPassTraceStatus_=-1;
      else {
        if(!f.counters)f.counters=mcla::metal::GPUPassTrace::CreateBuffer(device_);
        if(f.counters) {
          gpuPassTrace_=std::make_shared<mcla::metal::GPUPassTrace>(device_,f.counters,frames_+1);
          gpuPassTraceStatus_=1;
        } else gpuPassTraceStatus_=-2;
      }
    }
    return true;
  }
  id<MTLRenderCommandEncoder> RenderEncoder(MTLRenderPassDescriptor* pass,
      const char* kind,bool guest=false) {
    if(gpuPassTrace_)gpuPassTrace_->Render(pass,kind,guest);
    return [commands_ renderCommandEncoderWithDescriptor:pass];
  }
  id<MTLBlitCommandEncoder> BlitEncoder(const char* kind) {
    if(!gpuPassTrace_)return [commands_ blitCommandEncoder];
    auto pass=[MTLBlitPassDescriptor blitPassDescriptor];
    gpuPassTrace_->Blit(pass,kind);
    return [commands_ blitCommandEncoderWithDescriptor:pass];
  }
  void EndEncoder() {
    if (encoder_) {
      [encoder_ endEncoding];
      encoder_ = nil;
    }
    boundPipeline_ = nil;
    boundDepthState_ = nil;
    stencilReferences_.Reset(); winding_.Reset(); culling_.Reset();
    depthBias_.Reset(); viewport_.Reset(); scissor_.Reset(); blendColor_.Reset();
    boundVertices_ = {};
    boundHeaps_ = {};
    textureGroup_.key.Reset();
    textureGroup_.usedSlots.Reset();
    boundPushAddresses_.Reset();
    encoderReadResources_.clear();
    colors_ = {};
    depth_ = nil;
  }
  void DeclareRead(id<MTLResource> resource) {
    if (!encoder_ || !resource) return;
    // The Objective-C resource object is stable for the encoder lifetime;
    // pointer identity also works on SDKs where gpuResourceID is exposed only
    // on concrete MTLBuffer/MTLTexture protocols rather than MTLResource.
    const uint64_t identity = uint64_t(reinterpret_cast<uintptr_t>(
        (__bridge void*)resource));
    if (!encoderReadResources_.insert(identity).second) {
      ++resourceDeclarationSkips_;
      return;
    }
    ++resourceDeclarations_;
    [encoder_ useResource:resource
                    usage:MTLResourceUsageRead
                   stages:MTLRenderStageVertex | MTLRenderStageFragment];
  }
  bool ProbeMode(NSString *mode) const {
    return renderProbe_ && [probeMode_ isEqualToString:mode];
  }
  void PollRenderProbe() {
    if (!renderProbe_ || frames_ % 30) return;
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/mcla-render-probe.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length > 4096) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return;
    id mode = json[@"mode"], token = json[@"capture"];
    if (![mode isKindOfClass:NSString.class] ||
        ![token isKindOfClass:NSNumber.class] || [token longLongValue] <= 0 ||
        [token unsignedLongLongValue] == probeToken_) return;
    if (![@[@"baseline", @"resolved-base-mip", @"neutral-road-shadow",
            @"full-source-color-uv", @"pixel-history"] containsObject:mode]) return;
    probeMode_ = [mode copy];
    probeToken_ = [token unsignedLongLongValue];
    probeOverrides_ = 0;
    probeCapturedInputs_.clear();
    probeLoggedMips_.clear();
    pixelHistory_.Reset(json);
    passCaptureFrame_ = frames_ + 60; // Let two seconds of history settle.
    // A deterministic startup capture is useful for the short aerial-map
    // transition. Only the explicit probe launch honors this override; normal
    // play keeps the request-driven, two-second settling behavior above.
    if (NSString *requested = NSProcessInfo.processInfo.environment[@"MCLA_METAL_PROBE_CAPTURE_FRAME"]) {
      const NSInteger frame = requested.integerValue;
      if (frame > NSInteger(frames_) && frame < NSInteger(frames_) + 3600)
        passCaptureFrame_ = uint64_t(frame);
    }
    passCaptureCount_ = 0;
    passCaptureBytes_ = 0;
    hudTraceFrame_ = passCaptureFrame_;
    REXLOG_INFO("MCLA METAL PROBE mode={} token={} start={} capture_frame={}",
        probeMode_.UTF8String, probeToken_, frames_, passCaptureFrame_);
    NSDictionary *ack = @{@"mode":probeMode_, @"capture":@(probeToken_),
        @"start_frame":@(frames_), @"capture_frame":@(passCaptureFrame_)};
    NSString *ackPath = [[path stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"mcla-render-probe-ack.json"];
    [[NSJSONSerialization dataWithJSONObject:ack options:0 error:nil]
        writeToFile:ackPath atomically:YES];
  }
  void CapturePass(id<MTLTexture> target, const char *phase, uint64_t shader,
                   NSUInteger level = 0) {
    const bool depth = target.pixelFormat == MTLPixelFormatDepth32Float_Stencil8 ||
                       target.pixelFormat == MTLPixelFormatDepth32Float;
    if (frames_ != passCaptureFrame_ || !target || passCaptureCount_ >= 32 ||
        level >= target.mipmapLevelCount ||
        (!renderProbe_ && (target.width < 320 || target.height < 180)) ||
        (target.pixelFormat != MTLPixelFormatRGBA8Unorm &&
         target.pixelFormat != MTLPixelFormatRGBA16Float &&
         !(renderProbe_ && (depth || target.pixelFormat == MTLPixelFormatR32Float)))) return;
    const NSUInteger width = std::max<NSUInteger>(1, target.width >> level);
    const NSUInteger height = std::max<NSUInteger>(1, target.height >> level);
    const size_t pixelBytes = depth ? 4 : PixelBytes(target.pixelFormat);
    const size_t row = (width * pixelBytes + 255) & ~size_t(255);
    const size_t bytes = row * height;
    if (bytes > 128 * 1024 * 1024 - passCaptureBytes_) return;
    EndEncoder();
    if (!Begin()) return;
    auto buffer = [device_ newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    if (!buffer) return;
    auto blit = BlitEncoder("probe-readback");
    [blit copyFromTexture:target sourceSlice:0 sourceLevel:level
            sourceOrigin:MTLOriginMake(0,0,0)
              sourceSize:MTLSizeMake(width,height,1)
                toBuffer:buffer destinationOffset:0 destinationBytesPerRow:row
       destinationBytesPerImage:bytes
                     options:target.pixelFormat == MTLPixelFormatDepth32Float_Stencil8
                         ? MTLBlitOptionDepthFromDepthStencil : MTLBlitOptionNone];
    [blit endEncoding];
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/mcla-pass-capture"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *name = [NSString stringWithFormat:@"f%llu-d%llu-ps%016llX-%s-%u",
        (unsigned long long)frames_, (unsigned long long)draws_,
        (unsigned long long)shader, phase, passCaptureCount_++];
    if (renderProbe_)
      name = [NSString stringWithFormat:@"probe-%llu-%@-%@-m%lu",
          (unsigned long long)probeToken_, probeMode_, name, (unsigned long)level];
    NSString *path = [root stringByAppendingPathComponent:name];
    const size_t tightRow = width * pixelBytes;
    const bool half = target.pixelFormat == MTLPixelFormatRGBA16Float;
    NSString *format = depth || target.pixelFormat == MTLPixelFormatR32Float
                           ? @"r32f" : half ? @"rgba16f" : @"rgba8";
    NSString *mode = probeMode_;
    const uint64_t token = probeToken_, frame = frames_;
    passCaptureBytes_ += bytes;
    [commands_ addCompletedHandler:^(id<MTLCommandBuffer> cb) {
      if (cb.status != MTLCommandBufferStatusCompleted) return;
      NSMutableData *pixels = [NSMutableData dataWithLength:tightRow * height];
      for (NSUInteger y=0;y<height;++y)
        memcpy((uint8_t *)pixels.mutableBytes+y*tightRow,
               (const uint8_t *)buffer.contents+y*row,tightRow);
      [pixels writeToFile:[path stringByAppendingPathExtension:@"bin"] atomically:YES];
      NSDictionary *meta = @{@"width":@(width), @"height":@(height),
          @"half":@(half), @"format":format, @"level":@(level),
          @"mode":mode, @"token":@(token), @"frame":@(frame),
          @"gpu_completed":@YES};
      [[NSJSONSerialization dataWithJSONObject:meta options:0 error:nil]
          writeToFile:[path stringByAppendingPathExtension:@"json"] atomically:YES];
    }];
  }
  void CaptureProbeInputs(const uint8_t *state, uint64_t shader) {
    if (!renderProbe_ || frames_ != passCaptureFrame_) return;
    // Exact, observed materials/producers. Do not infer semantics from slot
    // number alone: MCLA reuses the same slot for unrelated textures.
    std::vector<unsigned> slots;
    if (shader == 0x7B5A243101A8F0F9ull) slots = {0, 1, 2, 13};
    if (shader == 0x2CDEA0E25045AD9Eull || shader == 0xD7BA99C168F84D73ull)
      slots = {15};
    if (shader == 0x4AA33D052D8AAD13ull) slots = {0};
    for (unsigned slot : slots) {
      if (passCaptureCount_ >= 24) break; // Reserve space for final scene.
      const uint32_t handle = R(state, 12536 + slot * 4);
      const uint64_t identity = shader ^ (uint64_t(slot) << 48) ^
          (slot == 13 || slot == 15 ? uint64_t(handle) << 8 : 0);
      if (!probeCapturedInputs_.insert(identity).second) continue;
      xn::xe_gpu_texture_fetch_t fetch{};
      for (unsigned j = 0; j < 6; ++j)
        reinterpret_cast<uint32_t *>(&fetch)[j] = R(state, 1152 + slot * 24 + j * 4);
      auto texture = TextureFor(handle, fetch);
      if (!texture) continue;
      const auto cached = textures_.find(handle);
      REXLOG_INFO("MCLA METAL PROBE input ps={:016X} slot={} handle={:08X} size={}x{} mips={} touched={:X} lod={}..{} border={}",
          shader, slot, handle, texture.width, texture.height, texture.mipmapLevelCount,
          cached != textures_.end() ? cached->second.touchedMips : 0,
          unsigned(fetch.mip_min_level), unsigned(fetch.mip_max_level), unsigned(fetch.border_color));
      const std::string phase = "input" + std::to_string(slot);
      for (NSUInteger level = 0; level < std::min<NSUInteger>(4, texture.mipmapLevelCount); ++level)
        CapturePass(texture, phase.c_str(), shader, level);
    }
  }
  void CapturePixelHistory(const uint8_t *state, uint64_t shader,
                           uint32_t textureMask, bool before = false) {
    if (!ProbeMode(@"pixel-history") || frames_ != passCaptureFrame_) return;
    auto target = before ? Target(Describe(R(state,12432)),false) : colors_[0];
    if (!pixelHistory_.CanRecord(target)) return;
    if (before) {
      // A paired baseline prevents an intervening resolve/clear or an old
      // target's contents from being falsely blamed on this draw's shader.
      NSDictionary *record = @{@"draw":@(draws_+1), @"phase":@"before",
          @"surface":@(R(state,12432)),
          @"ps":[NSString stringWithFormat:@"%016llX",(unsigned long long)shader]};
      EndEncoder();
      pixelHistory_.Record(device_,commands_,target,record);
      return;
    }
    NSMutableArray *bindings = [NSMutableArray array];
    for (unsigned i=0; i<26; ++i) {
      if (!(textureMask & (1u << i))) continue;
      const uint32_t handle = R(state,12536+i*4);
      NSMutableArray *fetch = [NSMutableArray array];
      for (unsigned j=0;j<6;++j)
        [fetch addObject:@(R(state,1152+i*24+j*4))];
      const auto produced = textures_.find(handle);
      [bindings addObject:@{@"slot":@(i), @"handle":@(handle), @"fetch":fetch,
          @"produced":@(produced!=textures_.end() && produced->second.produced)}];
    }
    NSDictionary *record = @{@"draw":@(draws_), @"phase":@"after",
        @"ps":[NSString stringWithFormat:@"%016llX",(unsigned long long)shader],
        @"vs":[NSString stringWithFormat:@"%016llX",(unsigned long long)shaderHandles_[vs_]],
        @"surface":@(R(state,12432)), @"color_info":@(drawSurfaces_[0].address),
        @"blend":@(R(state,10584)), @"depth_control":@(R(state,10548)),
        @"textures":bindings,
        @"ps_constants_be":[[NSData dataWithBytes:state+6016 length:4096]
            base64EncodedStringWithOptions:0]};
    EndEncoder();
    pixelHistory_.Record(device_, commands_, target, record);
  }
  void InvalidateSourceTexture(uint32_t handle) {
    // A resolve or guest write can replace a binding within the same frame.
    ++textureBindingSerial_;
    const auto contentKey = sourceTextureIndex_.FindAlias(handle);
    if (!contentKey) return;
    // Any wrapper aliases now point at a snapshot that may have been changed
    // by the guest write. Remove all of them so the next fetch decodes once.
    EraseSourceTexture(*contentKey);
    ++frameInvalidatedKeys_;
  }
  void EraseSourceTexture(uint64_t key) {
    frameAliasRemovals_ += sourceTextureIndex_.Erase(key);
    sourceTextures_.erase(key);
  }
  void EraseVertexBuffer(uint64_t key) {
    frameAliasRemovals_ += bufferIndex_.Erase(key);
    buffers_.erase(key);
  }
  void EraseIndexBuffer(uint64_t key) {
    frameAliasRemovals_ += indexBufferIndex_.Erase(key);
    indexBuffers_.erase(key);
  }
  void InvalidateResource(uint32_t resource) {
    ++resourceRevision_;
    const double start=performanceCaptureWasActive_?CACurrentMediaTime():0;
    ++frameInvalidationCalls_;
    InvalidateSourceTexture(resource);
    textures_.erase(resource);
    // Guest writes/releases must invalidate immediately, unlike optional age
    // eviction. Preserve the prior conservative shared-content semantics:
    // invalidating any owner removes the cached value and ALL of its aliases.
    while (auto key=bufferIndex_.FirstOwned(resource)) {
      EraseVertexBuffer(*key);++frameInvalidatedKeys_;
    }
    while (auto key=indexBufferIndex_.FirstOwned(resource)) {
      EraseIndexBuffer(*key);++frameInvalidatedKeys_;
    }
    if(start)frameInvalidationMS_+=(CACurrentMediaTime()-start)*1000;
  }
  void MaintainResourceCaches(uint64_t frame) {
    // Preserve 1800-frame retention (~60 seconds at 30 fps). Expire from the
    // age-ordered heads; never walk all live caches. Bound work between
    // individual destructions: a Metal release itself cannot be preempted.
    const auto result=mcla::metal::MaintainResourceCacheIndices(
        {&sourceTextureIndex_,&bufferIndex_,&indexBufferIndex_},frame,
        cacheMaintenanceTurn_,[]{return CACurrentMediaTime();},
        [&](unsigned which,uint64_t key){
          if(which==0)EraseSourceTexture(key);
          else if(which==1)EraseVertexBuffer(key);
          else EraseIndexBuffer(key);
        });
    for(unsigned i=0;i<3;++i) {
      frameCacheEvictions_+=result.evicted[i];
      evictionsSinceLog_[i]+=result.evicted[i];
    }
    frameCacheMaintenanceMS_=result.milliseconds;
  }
  Upload Allocate(size_t bytes) {
    frameUploadBytes_ += bytes;
    if (!bytes || bytes > 128 * 1024 * 1024 || !Begin())
      return {};
    auto &f = flights_[slot_];
    size_t aligned = (bytes + 255) & ~size_t(255);
    while (f.block < f.blocks.size() &&
           f.offset + aligned > f.blocks[f.block].length) {
      ++f.block;
      f.offset = 0;
    }
    if (f.block == f.blocks.size()) {
      auto b = [device_
          newBufferWithLength:std::max(size_t(4 * 1024 * 1024), aligned)
                      options:MTLResourceStorageModeShared];
      if (!b)
        return {};
      f.blocks.push_back(b);
    }
    Upload u{f.blocks[f.block], f.offset,
             static_cast<uint8_t *>(f.blocks[f.block].contents) + f.offset};
    f.offset += aligned;
    return u;
  }
  Shader *GetShader(uint32_t handle) {
    auto found = shaderHandles_.find(handle);
    if (found == shaderHandles_.end())
      return nullptr;
    auto &s = shaders_[found->second];
    if (s.info)
      return &s;
    for (auto &i : kMCLAMetalShaders)
      if (i.hash == found->second) {
        s.info = &i;
        break;
      }
    if (!s.info)
      return nullptr;
    NSString *name =
        [NSString stringWithFormat:@"%s-%016llX", s.info->vertex ? "vs" : "ps",
                                   (unsigned long long)s.info->hash];
    NSURL *url = [[NSBundle mainBundle] URLForResource:name
                                         withExtension:@"metallib"
                                          subdirectory:@"MCLAMetalShaders"];
    NSError *e = nil;
    s.library = [device_ newLibraryWithURL:url error:&e];
    if (!s.library) {
      REXLOG_ERROR("MCLA METAL library {}: {}", name.UTF8String,
                   e.localizedDescription.UTF8String);
      return nullptr;
    }
    return &s;
  }
  id<MTLFunction> Function(Shader &s, uint32_t spec) {
    auto f = s.functions.find(spec);
    if (f != s.functions.end())
      return f->second;
    auto values = [MTLFunctionConstantValues new];
    [values setConstantValue:&spec type:MTLDataTypeUInt atIndex:0];
    NSError *error = nil;
    auto fn = [s.library newFunctionWithName:@"shaderMain"
                              constantValues:values
                                       error:&error];
    if (!fn)
      REXLOG_ERROR("MCLA METAL function: {}",
                   error.localizedDescription.UTF8String);
    s.functions[spec] = fn;
    return fn;
  }
  ng::SurfaceDescriptor Describe(uint32_t h) {
    ng::SurfaceDescriptor d{};
    auto p = P(h, 44);
    if (!p)
      return d;
    d.handle = h;
    d.flags = R(p);
    d.base = R(p, 24);
    d.address = R(p, 28);
    d.packed_dimensions = R(p, 36);
    d.format = R(p, 40);
    d.width = (d.packed_dimensions >> 18) + 1;
    d.height = ((d.packed_dimensions >> 3) & 32767) + 1;
    d.sample_type = ng::DecodeSurfaceSampleType(d.base);
    MCLANativeCanonicalSurface(d);
    return d;
  }
  id<MTLTexture> Target(ng::SurfaceDescriptor desc, bool depth) {
    if (!desc.handle)
      return nil;
    auto format = SurfaceFormat(desc.format, depth);
    if (format == MTLPixelFormatInvalid || desc.width > 8192 ||
        desc.height > 8192)
      return nil;
    // Placement aliases of the same topology share storage, rather than
    // silently losing color/depth when the title switches wrapper objects.
    auto &s = surfaces_[SurfaceStorageKey(desc, format)];
    if (!s.image) {
      uint32_t guestWidth, guestHeight;
      MCLAGraphicsGuestVideoSize(&guestWidth, &guestHeight);
      const auto extent = mcla::metal::SceneExtent(desc.width, desc.height,
          MCLAGraphicsRenderHeight(), guestWidth, guestHeight);
      auto td =
          [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                             width:extent.width
                                                            height:extent.height
                                                         mipmapped:NO];
      td.storageMode = MTLStorageModePrivate;
      td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead |
                 MTLTextureUsagePixelFormatView;
      s.image = [device_ newTextureWithDescriptor:td];
      s.desc = desc;
      if (s.image) {
        Begin();
        EndEncoder();
        auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
        if (depth) {
          rp.depthAttachment.texture = s.image;
          rp.depthAttachment.loadAction = MTLLoadActionClear;
          rp.depthAttachment.storeAction = MTLStoreActionStore;
          rp.depthAttachment.clearDepth = 1;
          rp.stencilAttachment.texture = s.image;
          rp.stencilAttachment.loadAction = MTLLoadActionClear;
          rp.stencilAttachment.storeAction = MTLStoreActionStore;
        } else {
          rp.colorAttachments[0].texture = s.image;
          rp.colorAttachments[0].loadAction = MTLLoadActionClear;
          rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        }
        auto e = RenderEncoder(rp,"target-initialize");
        [e endEncoding];
      }
    }
    return s.image;
  }
  id<MTLTexture> ResolveSource(ng::SurfaceDescriptor desc, bool depth) {
    if (!desc.handle)
      return nil;
    const auto requestedFormat = SurfaceFormat(desc.format, depth);
    if (requestedFormat == MTLPixelFormatInvalid)
      return nil;
    const auto exact = surfaces_.find(SurfaceStorageKey(desc, requestedFormat));
    if (exact != surfaces_.end() && exact->second.image)
      return exact->second.image;
    if (depth)
      return nil;

    // MCLA's post chain renders a 320x180 HDR pass, then describes the source
    // of an LDR resolve using another colour format. An exact format lookup
    // therefore misses even though the image was rendered. Creating a target
    // here would resolve a freshly-cleared black image, corrupting the
    // tonemap/exposure input and clipping emissive surfaces. Match LARecomp's
    // measured policy: only after an exact RESOLVE lookup misses, reuse an
    // existing colour target with the same shape and sample topology. Prefer
    // the same EDRAM placement when one exists; draws never take this path.
    Surface *shape = nullptr;
    for (auto &[key, candidate] : surfaces_) {
      if (!candidate.image ||
          candidate.image.pixelFormat == MTLPixelFormatDepth32Float_Stencil8 ||
          candidate.desc.width != desc.width ||
          candidate.desc.height != desc.height ||
          candidate.desc.sample_type != desc.sample_type)
        continue;
      if ((candidate.desc.address & 2047u) == (desc.address & 2047u) &&
          (candidate.desc.base & 16383u) == (desc.base & 16383u)) {
        shape = &candidate;
        break;
      }
      if (!shape)
        shape = &candidate;
    }
    if (!shape)
      return nil;
    ++resolveShapeFallbacks_;
    if (resolveShapeFallbacks_ <= 12)
      REXLOG_INFO("MCLA METAL resolve shape fallback size={}x{} requested={} found={} source={:08X}",
                  desc.width, desc.height, uint32_t(requestedFormat),
                  uint32_t(shape->image.pixelFormat), desc.handle);
    return shape->image;
  }
  bool Attach(const uint8_t *state) {
    const uint64_t revision = MCLANativeSurfaceRevision();
    auto attachment = [&](uint32_t handle, unsigned slot) -> AttachmentReuse& {
      auto& cached = attachmentReuse_[slot];
      // Validate readable metadata even on hits; pointer identity is not proof.
      const auto* raw = handle ? P(handle,44) : nullptr;
      if (!raw) { cached = {}; return cached; }
      if (cached.handle == handle && cached.revision == revision && cached.image &&
          !memcmp(cached.bytes.data(),raw,cached.bytes.size())) {
        ++attachmentReuses_;
        return cached;
      }
      cached.handle = handle; cached.revision = revision;
      memcpy(cached.bytes.data(),raw,cached.bytes.size());
      cached.desc = Describe(handle);
      cached.image = Target(cached.desc,slot == 4);
      return cached;
    };
    std::array<id<MTLTexture>, 4> color{};
    for (unsigned i = 0; i < 4; ++i) {
      auto& cached = attachment(R(state,12432+i*4),i);
      drawSurfaces_[i] = cached.desc;
      color[i] = cached.image;
    }
    auto& cachedDepth = attachment(R(state,12448),4);
    drawDepthSurface_ = cachedDepth.desc;
    auto depth = cachedDepth.image;
    if (encoder_ && color == colors_ && depth == depth_)
      return true;
    EndEncoder();
    if (!color[0] && !depth)
      return false;
    if (!Begin())
      return false;
    auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
    for (unsigned i = 0; i < 4; ++i)
      if (color[i]) {
        rp.colorAttachments[i].texture = color[i];
        rp.colorAttachments[i].loadAction = MTLLoadActionLoad;
        rp.colorAttachments[i].storeAction = MTLStoreActionStore;
      }
    if (depth) {
      rp.depthAttachment.texture = depth;
      rp.depthAttachment.loadAction = MTLLoadActionLoad;
      rp.depthAttachment.storeAction = MTLStoreActionStore;
      rp.stencilAttachment.texture = depth;
      rp.stencilAttachment.loadAction = MTLLoadActionLoad;
      rp.stencilAttachment.storeAction = MTLStoreActionStore;
    }
    encoder_ = RenderEncoder(rp,color[0]?"guest-color":"guest-depth",true);
    if (encoder_) {
      // Missing vertex attributes are immutable defaults for this encoder.
      // Rebinding these tiny buffers on every city draw was unnecessary.
      const float defaultFloat[4] = {0, 0, 0, 1};
      const uint32_t defaultInteger[4] = {0, 0, 0, 1};
      [encoder_ setVertexBytes:defaultFloat length:sizeof(defaultFloat) atIndex:26];
      [encoder_ setVertexBytes:defaultInteger length:sizeof(defaultInteger) atIndex:27];
    }
    for(auto t:fallback_)DeclareRead(t);
    colors_ = color;
    depth_ = depth;
    return encoder_ != nil;
  }
  id<MTLTexture> View(id<MTLTexture> image,
                      const xn::xe_gpu_texture_fetch_t &fetch) {
    if (!image)
      return nil;
    uint32_t sw = fetch.swizzle;
    auto format = gx::GetBaseFormat(fetch.format);
    const char* tiledOverride=std::getenv("MCLA_TILED_COLOR_SWIZZLE");
    const bool tiledCorrection=!tiledOverride || std::strcmp(tiledOverride,"0")!=0;
    unsigned host=mcla::metal::DecodedTextureHostSwizzle(
        unsigned(format), fetch.tiled, unsigned(fetch.endianness), sw, tiledCorrection);
    MTLTextureSwizzle c[4];
    static const MTLTextureSwizzle map[] = {
        MTLTextureSwizzleRed,   MTLTextureSwizzleGreen, MTLTextureSwizzleBlue,
        MTLTextureSwizzleAlpha, MTLTextureSwizzleZero,  MTLTextureSwizzleOne};
    const uint32_t composed=mcla::metal::ComposeTextureSwizzle(sw,host);
    for (int i = 0; i < 4; ++i)
      c[i] = map[std::min((composed >> (3 * i)) & 7, 5u)];
    if (composed == 0x688)
      return image;
    return [image
        newTextureViewWithPixelFormat:image.pixelFormat
                          textureType:image.textureType
                               levels:NSMakeRange(0, image.mipmapLevelCount)
                               slices:NSMakeRange(0, image.textureType ==
                                                             MTLTextureTypeCube
                                                         ? 6
                                                         : image.arrayLength)
                              swizzle:MTLTextureSwizzleChannelsMake(
                                          c[0], c[1], c[2], c[3])];
  }
  id<MTLTexture> TextureFor(uint32_t handle,
                            const xn::xe_gpu_texture_fetch_t &fetch) {
    if (!handle) return nil; // A guest null binding is not a decode failure.
    auto missing = [&](const char* reason) -> id<MTLTexture> {
      if (!mcla::DiagnosticsEnabled()) return nil;
      ++textureFallbacks_;
      if (textureFailureReasons_.size()<32 || textureFailureReasons_.contains(reason)) {
        auto& hits=textureFailureReasons_[reason];
        if (++hits<=4)
          REXLOG_WARN("MCLA METAL texture fallback reason={} frame={} handle={:08X} format={} base={:08X} vs={:016X} ps={:016X}",
              reason,frames_,handle,unsigned(fetch.format),uint32_t(fetch.base_address<<12),
              shaderHandles_[vs_],shaderHandles_[ps_]);
      }
      return nil;
    };
    // Resolve destinations live only in host texture storage, so their guest
    // object handle remains authoritative.
    auto produced = textures_.find(handle);
    if (produced != textures_.end() && produced->second.produced) {
      produced->second.frame = frames_;
      // Resolve conversion has already materialized Metal channel order. The
      // destination fetch swizzle describes the guest-side storage view and
      // applying it again here double-swizzles the post-FX chain (most visibly
      // as a global blue cast).
      return produced->second.image;
    }
    std::array<uint32_t, 6> raw;
    memcpy(raw.data(), &fetch, 24);
    raw=mcla::metal::TextureContentKey(raw);
    uint64_t contentKey = Hash(raw.data(), sizeof(raw));
    auto found = sourceTextures_.find(contentKey);
    // Defend the resource cache against the (extremely unlikely) 64-bit hash
    // collision without putting wrapper identity back into the key.
    while (found != sourceTextures_.end() && found->second.fetch != raw) {
      contentKey = Hash(&contentKey, sizeof(contentKey), contentKey);
      found = sourceTextures_.find(contentKey);
    }
    if (found != sourceTextures_.end() && found->second.verifiedFrame != frames_) {
      ++textureChecks_;
      found->second.verifiedFrame = frames_;
      if (!mcla::metal::TextureSamplesMatch(found->second.samples,
              [&](uint32_t a, uint32_t n) { return ReadableTextureBlock(a, n); })) {
        if (++staleTextures_ <= 12)
          REXLOG_INFO("MCLA METAL stale texture refreshed frame={} handle={:08X} base={:08X} ps={:016X}",
                      frames_, handle, uint32_t(fetch.base_address << 12),
                      shaderHandles_[ps_]);
        EraseSourceTexture(contentKey);
        ++textureBindingSerial_;
        found = sourceTextures_.end();
      }
    }
    if (found != sourceTextures_.end()) {
      if(found->second.frame!=frames_)sourceTextureIndex_.Touch(contentKey,frames_);
      found->second.frame = frames_;
      sourceTextureIndex_.BindAlias(contentKey,handle);
      return found->second.image;
    }
    gx::TextureInfo info{};
    if (!gx::TextureInfo::Prepare(fetch, &info))
      return missing("fetch-layout");
    unsigned format = uint32_t(gx::GetBaseFormat(info.format));
    auto pf = Format(format);
    if (pf == MTLPixelFormatInvalid || format == 22 || format == 23 ||
        info.width > 8191 || info.height > 8191)
      return missing("format-or-size");
    bool cube = info.dimension == xn::DataDimension::kCube,
         volume = info.dimension == xn::DataDimension::k3D;
    unsigned layers = cube ? 6 : info.is_stacked ? info.depth + 1 : 1;
    auto td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf
                                                           width:info.width + 1
                                                          height:info.height + 1
                                                       mipmapped:NO];
    td.mipmapLevelCount = info.mip_max_level + 1;
    td.storageMode = MTLStorageModeShared;
    td.usage = MTLTextureUsageShaderRead | MTLTextureUsagePixelFormatView;
    if (cube)
      td.textureType = MTLTextureTypeCube;
    else if (volume) {
      td.textureType = MTLTextureType3D;
      td.depth = info.depth + 1;
    } else if (layers > 1) {
      td.textureType = MTLTextureType2DArray;
      td.arrayLength = layers;
    }
    auto image = [device_ newTextureWithDescriptor:td];
    if (!image)
      return missing("allocation");
    ++decodedTextures_;
    auto fi = info.format_info();
    unsigned bpb = fi->bytes_per_block();
    if (!std::has_single_bit(bpb))
      return missing("block-size");
    std::vector<mcla::metal::TextureBlockSample> samples;
    auto layout = gx::texture_util::GetGuestTextureLayout(
        info.dimension, info.pitch >> 5, info.width + 1, info.height + 1,
        info.depth + 1, info.is_tiled, info.format, info.has_packed_mips,
        info.memory.base_address != 0, info.mip_max_level);
    for (unsigned mip = 0; mip <= info.mip_max_level; ++mip) {
      unsigned w, h;
      info.GetMipSize(mip, &w, &h);
      unsigned z = volume ? std::max(1u, (info.depth + 1) >> mip) : 1;
      auto extent = info.GetMipExtent(mip, true);
      unsigned ox = 0, oy = 0;
      uint32_t address = info.GetMipLocation(mip, &ox, &oy, true);
      if (address >= 0x20000000)
        return missing("mip-address");
      auto source = memory_->TranslatePhysical<const uint8_t *>(address);
      if (!source)
        return missing("mip-source");
      auto &level = mip ? layout.mips[mip] : layout.base;
      unsigned bw = (w + fi->block_width - 1) / fi->block_width,
               bh = (h + fi->block_height - 1) / fi->block_height;
      unsigned pw = std::max(w, bw * fi->block_width),
               ph = std::max(h, bh * fi->block_height);
      size_t row = size_t(pw) * PixelBytes(pf), slice = row * ph;
      if (slice * z > 128 * 1024 * 1024)
        return missing("decode-size");
      for (unsigned layer = 0; layer < layers; ++layer) {
        std::vector<uint8_t> data(slice * z);
        for (unsigned iz = 0; iz < z; ++iz)
          for (unsigned y = 0; y < bh; ++y)
            for (unsigned x = 0; x < bw; ++x) {
              int32_t off =
                  info.is_tiled
                      ? (volume
                             ? gx::texture_util::GetTiledOffset3D(
                                   x + ox, y + oy, iz, extent.block_pitch_h,
                                   extent.block_pitch_v, std::countr_zero(bpb))
                             : gx::texture_util::GetTiledOffset2D(
                                   x + ox, y + oy, extent.block_pitch_h,
                                   std::countr_zero(bpb)))
                      : int32_t(((iz * extent.block_pitch_v + y + oy) *
                                     extent.block_pitch_h +
                                 x + ox) *
                                bpb);
              if (off < 0 ||
                  uint64_t(address) +
                          size_t(layer) * level.array_slice_stride_bytes + off +
                          bpb >
                      0x20000000)
                return missing("block-address");
              auto src =
                  source + size_t(layer) * level.array_slice_stride_bytes + off;
              const uint64_t block = (uint64_t(iz) * bh + y) * bw + x;
              if (bpb <= 16 && mcla::metal::SampleTextureBlock(block, uint64_t(z) * bh * bw)) {
                mcla::metal::TextureBlockSample sample;
                sample.address = uint32_t(uint64_t(address) +
                    size_t(layer) * level.array_slice_stride_bytes + off);
                sample.size = bpb;
                std::memcpy(sample.bytes.data(), src, bpb);
                samples.push_back(sample);
              }
              auto dst = data.data() + iz * slice + y * fi->block_height * row +
                         x * fi->block_width * PixelBytes(pf);
              if (format == 3) {
                uint8_t packed[2];
                gx::texture_conversion::CopySwapBlock(info.endianness, packed, src, 2);
                mcla::metal::DecodeR5G5B5A1(packed, dst);
              } else if (format >= 18 && format <= 20) {
                uint8_t block[16];
                gx::texture_conversion::CopySwapBlock(info.endianness, block,
                                                      src, bpb);
                DecodeBC(block, format, dst, row);
              } else if (format == 49)
                gx::texture_conversion::ConvertTexelDXNToR8G8(info.endianness,
                                                              dst, src, row);
              else if (format == 60)
                gx::texture_conversion::ConvertTexelCTX1ToR8G8(info.endianness,
                                                               dst, src, row);
              else if (format == 59)
                gx::texture_conversion::ConvertTexelDXT5AToR8(info.endianness,
                                                              dst, src, row);
              else if (format == 58) {
                uint8_t bc[16];
                gx::texture_conversion::ConvertTexelDXT3AToDXT3(info.endianness,
                                                                bc, src, 16);
                DecodeBC(bc, 19, dst, row);
              } else
                gx::texture_conversion::CopySwapBlock(info.endianness, dst, src,
                                                      bpb);
            }
        [image replaceRegion:MTLRegionMake3D(0, 0, 0, w, h, z)
                 mipmapLevel:mip
                       slice:layer
                   withBytes:data.data()
                 bytesPerRow:row
               bytesPerImage:slice];
      }
    }
    auto sampled = View(image, fetch);
    if (!sampled) return missing("texture-view");
    sourceTextures_[contentKey] = {sampled, raw, false, 0, frames_,
                                   std::move(samples), frames_};
    sourceTextureIndex_.Touch(contentKey,frames_);
    sourceTextureIndex_.BindAlias(contentKey,handle);
    return sampled;
  }
  id<MTLSamplerState> Sampler(const xn::xe_gpu_texture_fetch_t &f,bool material,
                            bool baseMipProbe = false) {
    const unsigned override=material?filterMode_:0;
    const auto fields = mcla::metal::SamplerCacheFields(
        f.dword_0, f.dword_3, f.dword_4, f.dword_5, override);
    uint64_t key=Hash(fields.data(),sizeof(fields));
    key = Hash(&baseMipProbe, sizeof(baseMipProbe), key);
    auto it = samplers_.find(key);
    if (it != samplers_.end())
      return it->second;
    auto d = [MTLSamplerDescriptor new];
    d.supportArgumentBuffers = YES;
    d.minFilter = f.min_filter == xn::TextureFilter::kLinear
                      ? MTLSamplerMinMagFilterLinear
                      : MTLSamplerMinMagFilterNearest;
    d.magFilter = f.mag_filter == xn::TextureFilter::kLinear
                      ? MTLSamplerMinMagFilterLinear
                      : MTLSamplerMinMagFilterNearest;
    d.mipFilter = f.mip_filter == xn::TextureFilter::kLinear
                      ? MTLSamplerMipFilterLinear
                      : MTLSamplerMipFilterNearest;
    if(f.mip_filter==xn::TextureFilter::kBaseMap)d.mipFilter=MTLSamplerMipFilterNotMipmapped;
    d.lodMinClamp=f.mip_min_level;
    d.lodMaxClamp=std::max(unsigned(f.mip_min_level),unsigned(f.mip_max_level));
    if(override){
      d.minFilter=d.magFilter=MTLSamplerMinMagFilterLinear;
      d.mipFilter=override==1?MTLSamplerMipFilterNearest:MTLSamplerMipFilterLinear;
      d.maxAnisotropy=override==1?1:override==2?4:override==3?8:16;
    }
    if (baseMipProbe) {
      d.mipFilter = MTLSamplerMipFilterNotMipmapped;
      d.lodMinClamp = d.lodMaxClamp = 0;
    }
    mcla::metal::ApplySamplerAddressing(d, unsigned(f.clamp_x),
        unsigned(f.clamp_y), unsigned(f.clamp_z), unsigned(f.border_color));
    auto s = [device_ newSamplerStateWithDescriptor:d];
    samplers_[key] = s;
    return s;
  }
  bool BindResources(const uint8_t *state, const MCLAMetalShaderInfo* vsInfo,
                     const MCLAMetalShaderInfo* psInfo) {
    const bool sample=profile_ && ((draws_&63)==0);
    double stamp=sample?CACurrentMediaTime():0;
    uint64_t cpuStamp=sample?mcla::metal::ThreadCPUTimeNanoseconds():0;
    auto mark=[&](unsigned section){if(sample){
      const double now=CACurrentMediaTime();
      const uint64_t cpuNow=mcla::metal::ThreadCPUTimeNanoseconds();
      const double wallMS=(now-stamp)*1000;
      const double cpuMS=cpuNow>=cpuStamp?(cpuNow-cpuStamp)/1000000.0:0;
      profileMS_[section]+=wallMS;
      frameProfileWallMS_[section]+=wallMS;
      frameProfileCPUMS_[section]+=cpuMS;
      stamp=now;cpuStamp=cpuNow;
    }};
    // Reuse immutable, completion-owned uploads only after comparing every
    // register the current shader can read. No guest writes are suppressed.
    uint64_t addresses[2]{};
    for (unsigned stage = 0; stage < 2; ++stage) {
      const auto* info = stage ? psInfo : vsInfo;
      if (!info) continue;
      auto& bank = constantBanks_[stage];
      const auto* source = state + (stage ? 6016 : 1920);
      if (bank.snapshot.Matches(source, info->constants)) {
        ++constantBankReuses_;
      } else {
        auto upload = Allocate(4096);
        if (!upload.cpu) return false;
        constantRegistersUploaded_ += SwapConstantRegisters(
            upload.cpu, source, info->constants);
        bank.snapshot.Remember(source, info->constants);
        bank.upload = upload;
        ++constantBankUploads_;
      }
      addresses[stage] = bank.upload.address();
      DeclareRead(bank.upload.buffer);
    }
    const uint32_t mask = vsInfo->textures | (psInfo ? psInfo->textures : 0);
    const uint64_t groupSerial = textureBindingSerial_;
    std::array<uint64_t,95> groupKey;
    bool groupHit = false;
    if (optimizeBindings_) {
      groupHit = !renderProbe_ && textureGroup_.usedSlots.Matches(
          frames_,groupSerial,mask,state+1152,state+12536);
    } else {
      groupKey = {frames_,groupSerial,mask};
      memcpy(reinterpret_cast<uint8_t*>(groupKey.data()+3),state+1152,26*24);
      memcpy(reinterpret_cast<uint8_t*>(groupKey.data()+3)+26*24,state+12536,26*4);
      groupHit = !renderProbe_ && textureGroup_.key.Matches(groupKey);
    }
    Upload constants{};
    std::array<uint8_t,1056> sharedBytes;
    if (!optimizeBindings_) {
      constants = Allocate(1056);
      if (!constants.cpu) return false;
    }
    // Construct on the stack first, then reuse an immutable upload only after
    // comparing the complete block. Never rewrite bytes referenced by a draw.
    auto shared = optimizeBindings_ ? sharedBytes.data() : constants.cpu;
    // The texture-index portion is identical for every draw. Copy its
    // prebuilt image instead of zeroing and rewriting 130 individual words.
    static const std::array<uint8_t,1056> sharedTemplate = [] {
      std::array<uint8_t,1056> bytes{};
      for (unsigned a = 0; a < 5; ++a)
        for (unsigned i = 0; i < 26; ++i) {
          const uint32_t slot = i;
          memcpy(bytes.data() + a * 104 + i * 4, &slot, 4);
        }
      return bytes;
    }();
    mcla::metal::InitializeSharedConstants(shared,sharedTemplate.data(),groupHit);
    auto wu = [&](unsigned o, uint32_t v) { memcpy(shared + o, &v, 4); };
    auto wf = [&](unsigned o, float v) { memcpy(shared + o, &v, 4); };
    wu(528, ng::PackNativeShaderBooleans(R(state, 0x2780), R(state, 0x2790)));
    const auto& logicalTarget = colors_[0] ? drawSurfaces_[0] : drawDepthSurface_;
    const float scaleX = float(colors_[0] ? colors_[0].width : depth_.width) / logicalTarget.width;
    const float scaleY = float(colors_[0] ? colors_[0].height : depth_.height) / logicalTarget.height;
    const auto halfPixel = mcla::metal::HalfPixelOffset(
        R(state, mcla::metal::kPixelCenterRegisterOffset),
        F(state, 12648)*scaleX, F(state, 12652)*scaleY);
    wf(552, halfPixel[0]);
    wf(556, halfPixel[1]);
    for (int i = 0; i < 4; ++i)
      wu(560 + i * 4, R(state, 10272 + i * 4));
    wu(576, (R(state, 10564) & 1) != 0);
    wu(580, R(state, 10500));
    wu(740, 1);
    wf(744, 1.f/scaleX);
    wf(748, 1.f/scaleY);
    const auto pixelIdentity = shaderHandles_.find(ps_);
    const bool bloomSeed = pixelIdentity != shaderHandles_.end() &&
                           pixelIdentity->second == 0x35F41762995C91B9ull;
    for (unsigned i = 0; i < 4; ++i) {
      auto s = drawSurfaces_[i];
      auto output = ng::NativeColorOutput(s.address, s.handle != 0);
      // xrage_postfx__PSSeedRTNoZ is the light-glow seed feeding MCLA's
      // bloom/streak chain. Scale only its RGB seed, before the blur and
      // composite passes, rather than dimming the scene, UI, or exposure.
      // Alpha remains title-authored because it participates in blending.
      if (bloomSeed) {
        output.scale[0] *= bloomStrength_;
        output.scale[1] *= bloomStrength_;
        output.scale[2] *= bloomStrength_;
      }
      memcpy(shared + 864 + i * sizeof(output), &output, sizeof(output));
    }
    Upload heaps;
    if(groupHit) {
      ++textureGroupReuses_;
      heaps=textureGroup_.heaps;
      memcpy(shared,textureGroup_.indices.data(),520);
      memcpy(shared+752,textureGroup_.lods.data(),104);
    } else {
      heaps=Allocate(5*256);
      if(!heaps.cpu)return false;
      memcpy(heaps.cpu,heapTemplate_.data(),heapTemplate_.size());
    }
    mark(6);
    if(!groupHit) {
    for (uint32_t remaining=mask&0x3FFFFFF; remaining;remaining&=remaining-1) {
      unsigned i=std::countr_zero(remaining);
      id<MTLTexture> texture = nil;
      xn::xe_gpu_texture_fetch_t fetch{};
      for (unsigned j = 0; j < 6; ++j)
        reinterpret_cast<uint32_t *>(&fetch)[j] =
            R(state, 1152 + i * 24 + j * 4);
      const uint32_t handle=R(state,12536+i*4);
      auto& binding = textureBindings_[i];
      ++textureBindingLookups_;
      std::array<uint32_t, 6> fetchWords;
      memcpy(fetchWords.data(), &fetch, sizeof(fetchWords));
      const bool bindingHit = binding.frame == frames_ &&
          binding.serial == textureBindingSerial_ &&
          binding.handle == handle && binding.fetch == fetchWords;
      if (bindingHit) {
        texture = binding.image;
        ++textureBindingHits_;
      } else {
        texture = TextureFor(handle, fetch);
        const auto cached = textures_.find(handle);
        binding.frame = frames_;
        binding.serial = textureBindingSerial_;
        binding.handle = handle;
        binding.fetch = fetchWords;
        binding.image = texture;
        binding.produced = cached != textures_.end() && cached->second.produced;
        binding.sceneFlags = binding.produced ? cached->second.sceneFlags : 0;
      }
      const bool produced = binding.produced;
      if (!bindingHit) {
        binding.material = texture && texture.mipmapLevelCount > 1 &&
            !produced && fetch.mip_filter != xn::TextureFilter::kBaseMap;
        const auto type = texture.textureType;
        binding.kind = type == MTLTextureType2D ? 0 : type == MTLTextureType2DArray ? 1 :
            type == MTLTextureType3D ? 2 : 3;
        binding.textureID = texture ? texture.gpuResourceID._impl : 0;
        auto sampler = Sampler(fetch, binding.material);
        binding.samplerID = (sampler ?: fallbackSampler_).gpuResourceID._impl;
      }
      const bool material = binding.material;
      const bool baseMipProbe = produced && ProbeMode(@"resolved-base-mip");
      if (baseMipProbe && texture.mipmapLevelCount > 1) ++probeOverrides_;
      const bool neutralRoad = i == 13 && ProbeMode(@"neutral-road-shadow") &&
          pixelIdentity != shaderHandles_.end() &&
          pixelIdentity->second == 0x7B5A243101A8F0F9ull && probeNeutralCollector_;
      if (neutralRoad) {
        texture = probeNeutralCollector_;
        ++probeOverrides_;
      }
      if (renderProbe_ && frames_ == passCaptureFrame_ && produced && texture &&
          texture.mipmapLevelCount > 1 && pixelIdentity != shaderHandles_.end()) {
        const auto cached = textures_.find(handle);
        const uint64_t key = pixelIdentity->second ^ (uint64_t(handle) << 16) ^ i;
        if (cached != textures_.end() && probeLoggedMips_.size() < 64 &&
            probeLoggedMips_.insert(key).second)
          REXLOG_INFO("MCLA METAL PROBE mip_use ps={:016X} slot={} handle={:08X} levels={} touched={:X} lod={}..{} filter={} bias={}",
              pixelIdentity->second, i, handle, texture.mipmapLevelCount,
              cached->second.touchedMips, unsigned(fetch.mip_min_level),
              unsigned(fetch.mip_max_level), unsigned(fetch.mip_filter), int(fetch.lod_bias));
      }
      uint64_t samplerID = binding.samplerID;
      if (baseMipProbe || neutralRoad) {
        auto sampler = neutralRoad ? probeNeutralSampler_ : Sampler(fetch,material,true);
        samplerID = (sampler ?: fallbackSampler_).gpuResourceID._impl;
      }
        if (texture) {
          unsigned kind = neutralRoad ? 0 : binding.kind;
        uint64_t id = neutralRoad ? texture.gpuResourceID._impl : binding.textureID;
        memcpy(heaps.cpu + kind * 256 + i * 8, &id, 8);
          // Xenos sign value 3 requests its piecewise gamma-to-linear texture
          // conversion. Keep the Metal texture in host order and carry the
          // conversion bit beside the tiny argument-buffer index. Generated
          // shaders mask it before indexing and convert RGB after filtering.
          const bool gamma = ((reinterpret_cast<const uint32_t *>(&fetch)[0] >> 2) & 3u) == 3u;
          gammaBindings_ += gamma;
          const uint32_t sceneFlags = kind == 0 && produced && !neutralRoad
              ? binding.sceneFlags : 0;
          wu(kind * 104 + i * 4, i | sceneFlags | (gamma ? 0x80000000u : 0u));
          DeclareRead(texture);
      }
      memcpy(heaps.cpu + 4 * 256 + i * 8, &samplerID, 8);
      // MCLA's guest material LOD was authored for Xenos sampling. Passing it
      // through unchanged to Metal consistently selects a visibly coarser mip
      // on broad road/building surfaces, and the presentation sharpener then
      // exaggerates the resulting texel blocks. Bias only static source
      // materials toward the next more detailed mip; produced textures (UI,
      // shadows, reflections and post targets) must retain their exact LOD.
      // The first -0.75 test visibly improved clarity on device without
      // disturbing produced targets. Move another half mip toward the source
      // detail; avoid the much harsher force-base-mip diagnostic path.
      constexpr float kMaterialMetalLodCorrection = -1.25f;
      const float lodBias = float(fetch.lod_bias) / 32.f +
          (material && !(visualExperiments_ & mcla::metal::StableMaterialLOD)
               ? kMaterialMetalLodCorrection : 0.f);
      wf(752 + i * 4, lodBias);
    }
    // Encoder-local: indirect resources are already resident. Resolves and
    // writes change the serial; frame IDs protect upload-ring lifetimes.
    // TextureFor may discover stale content while building this group. Do
    // not stamp the new epoch over entries resolved earlier in the loop;
    // they must be revalidated on the next draw, just like per-slot bindings.
    if (groupSerial == textureBindingSerial_) {
      if (optimizeBindings_)
        textureGroup_.usedSlots.Remember(frames_,groupSerial,mask,state+1152,state+12536);
      else textureGroup_.key.Remember(groupKey);
    } else {
      textureGroup_.key.Reset();
      textureGroup_.usedSlots.Reset();
    }
    textureGroup_.heaps=heaps;
    memcpy(textureGroup_.indices.data(),shared,520);
    memcpy(textureGroup_.lods.data(),shared+752,104);
    }
    mark(7);
    if(boundHeaps_.buffer!=heaps.buffer || boundHeaps_.offset!=heaps.offset) {
    for (unsigned k = 0; k < 5; ++k) {
      [encoder_ setVertexBuffer:heaps.buffer
                         offset:heaps.offset + k * 256
                        atIndex:k];
      [encoder_ setFragmentBuffer:heaps.buffer
                           offset:heaps.offset + k * 256
                          atIndex:k];
    }
    boundHeaps_=heaps;
    }
    if (optimizeBindings_) {
      if (sharedConstantsSnapshot_.Matches(shared)) {
        constants = sharedConstantsUpload_;
        ++sharedConstantReuses_;
      } else {
        constants = Allocate(sharedBytes.size());
        if (!constants.cpu) return false;
        memcpy(constants.cpu,shared,sharedBytes.size());
        sharedConstantsSnapshot_.Remember(shared);
        sharedConstantsUpload_ = constants;
        ++sharedConstantUploads_;
      }
    } else ++sharedConstantUploads_;
    DeclareRead(constants.buffer);
    const std::array<uint64_t,3> push{addresses[0],addresses[1],constants.address()};
    if (!optimizeBindings_ || !boundPushAddresses_.Matches(push)) {
      [encoder_ setVertexBytes:push.data() length:sizeof(push) atIndex:8];
      [encoder_ setFragmentBytes:push.data() length:sizeof(push) atIndex:8];
      boundPushAddresses_.Remember(push);
      ++pushAddressCalls_;
    } else ++pushAddressSkips_;
    mark(8);
    return true;
  }
  VertexUpload VertexBuffer(
      unsigned stream, const ng::RegisterVertexDeclarationCommand &decl,
      const Shader &shader, uint32_t inlineAddress, uint32_t inlineSize,
      uint32_t inlineStride) {
    auto bind = streams_[stream];
    uint32_t address = inlineAddress, size = inlineSize;
    unsigned stride = inlineAddress ? inlineStride : bind.stride,
             offset = inlineAddress ? 0 : bind.offset;
    bool locked = false;
    std::array<uint64_t,10> exactVertex{};
    auto remember = [&](VertexUpload upload) {
      if (!inlineAddress && !locked) {
        vertexReuse_[stream].key.Remember(exactVertex);
        vertexReuse_[stream].upload = upload;
      }
      return upload;
    };
    if (!inlineAddress) {
      auto p = P(bind.buffer, 32);
      if (!p)
        return {};
      exactVertex={frames_,resourceRevision_,currentDeclarationVersion_,
          uint64_t(decl.declaration)<<32|bind.buffer,shader.info->hash,
          uint64_t(offset)<<32|stride};
      memcpy(exactVertex.data()+6,p,32);
      if(vertexReuse_[stream].key.Matches(exactVertex)) {
        ++vertexReuses_;
        return vertexReuse_[stream].upload;
      }
      auto meta = ng::DecodeNativeBufferMetadata(R(p), R(p, 24), R(p, 28));
      if (!meta || !meta->HasValidPayload(64 * 1024 * 1024))
        return {};
      address = meta->guest_address;
      size = meta->guest_size;
      locked = meta->guest_locked;
    }
    if (!stride)
      return {};
    // Wrapper objects churn continuously, but the same address can also be
    // rewritten for UI geometry without an explicit locked-buffer path. A
    // wrapper may use a prior proven alias; a new wrapper must prove payload
    // equality before it shares a transformed host buffer.
    std::array<uint64_t, 5> bits{
        decl.declaration, shader.info->hash, uint64_t(offset) << 32 | stride,
        uint64_t(address) << 32 | size, currentDeclarationVersion_};
    const uint64_t interpretationKey = Hash(bits.data(), sizeof(bits));
    uint64_t key = interpretationKey, wrapperKey = 0;
    if (!inlineAddress && !locked) {
      const std::array<uint64_t, 2> wrapperBits{bind.buffer,
                                                interpretationKey};
      wrapperKey = Hash(wrapperBits.data(), sizeof(wrapperBits));
      auto alias = bufferIndex_.FindAlias(wrapperKey);
      if (alias) {
        auto cached = buffers_.find(*alias);
        if (cached != buffers_.end()) {
          if(cached->second.frame!=frames_)bufferIndex_.Touch(*alias,frames_);
          cached->second.frame = frames_;
          return remember({cached->second.buffer, 0});
        }
        bufferIndex_.Erase(*alias);
      }
    }
    // A cached host snapshot does not read guest payload pages again. Unlock
    // and release invalidate it before any subsequent guest write is observed.
    auto src = P(address, size);
    if (!src) return {};
    uint64_t dynamicKey = 0;
    if (locked && !inlineAddress) {
      // Reuse a locked stream within this command buffer, but validate one
      // contiguous part on every reuse. This is the bounded shadow sweep from
      // the proven native renderer: every payload byte is eventually checked
      // without hashing a multi-megabyte buffer thousands of times per frame.
      dynamicKey = key;
      auto dynamic = dynamicVertexUploads_.find(dynamicKey);
      if (dynamic != dynamicVertexUploads_.end()) {
        auto range = ng::GetNativeBufferShadowValidationRange(
            size, dynamic->second.validationOffset);
        if (ng::NativeBufferShadowPayloadRangeMatches(
                src, dynamic->second.shadow.data(), size, range)) {
          dynamic->second.validationOffset = range.next_offset;
          return dynamic->second.upload;
        }
        dynamicVertexUploads_.erase(dynamic);
      }
    } else if (inlineAddress) {
      // Inline payloads are normally small and may reuse a guest stack address
      // for unrelated draws. Hash them completely to retain exact semantics.
      dynamicKey = Hash(src, size, interpretationKey);
      auto dynamic = dynamicVertexUploads_.find(dynamicKey);
      if (dynamic != dynamicVertexUploads_.end())
        return dynamic->second.upload;
    } else {
      // Hash once when an unfamiliar wrapper is seen. Subsequent draws through
      // that wrapper take the fast alias path above. This retains sharing for
      // immutable city meshes without reusing stale gas-station/menu vertices.
      key = Hash(src, size, interpretationKey);
      auto cached = buffers_.find(key);
      if (cached != buffers_.end()) {
        if(cached->second.frame!=frames_)bufferIndex_.Touch(key,frames_);
        cached->second.frame = frames_;
        bufferIndex_.AddOwner(key,bind.buffer);
        bufferIndex_.BindAlias(key,wrapperKey);
        return remember({cached->second.buffer, 0});
      }
    }
    auto vertexLease=vertexScratch_.Use(size,reuseGeometryScratch_);
    auto& data=vertexLease.values();
    mcla::metal::SwapVertexWords(data.data(),src,size);
    // Bounded source evidence for colored particles/light sprites. Retail Mode
    // bypasses the probe entirely; no pixel/shader color override is applied.
    if(mcla::DiagnosticsEnabled() && colorAuditCount_<colorAuditKeys_.size()) {
      for(unsigned e=0;e<decl.element_count;++e) {
        const auto& el=decl.elements[e];
        if(el.stream!=stream || el.usage!=10 || offset+el.offset>size ||
           size-(offset+el.offset)<4) continue;
        const uint64_t auditKey=shader.info->hash ^ (uint64_t(el.type)<<16) ^ el.usage_index;
        if(std::find(colorAuditKeys_.begin(),colorAuditKeys_.begin()+colorAuditCount_,auditKey)!=colorAuditKeys_.begin()+colorAuditCount_) continue;
        colorAuditKeys_[colorAuditCount_++]=auditKey;
        const unsigned at=offset+el.offset;
        uint32_t raw[3]{},host[3]{};
        unsigned samples=0;
        for(;samples<3 && at+uint64_t(samples)*stride+4<=size;++samples) {
          std::memcpy(&raw[samples],src+at+samples*stride,4);
          std::memcpy(&host[samples],data.data()+at+samples*stride,4);
          raw[samples]=__builtin_bswap32(raw[samples]);
        }
        REXLOG_INFO("MCLA COLOR SOURCE vs={:016X} ps={:016X} type={:08X} color_index={} inline={} stride={} samples={} guest={:08X},{:08X},{:08X} host_word={:08X},{:08X},{:08X}",
            shader.info->hash,shaderHandles_[ps_],el.type,unsigned(el.usage_index),inlineAddress!=0,stride,samples,
            raw[0],raw[1],raw[2],host[0],host[1],host[2]);
        if(colorAuditCount_==colorAuditKeys_.size()) break;
      }
    }
    for (unsigned e = 0; e < decl.element_count; ++e) {
      auto &el = decl.elements[e];
      if (el.stream != stream)
        continue;
      if (planVertexFixups_) {
        auto plan=mcla::metal::PlanVertexFixup(el.type,
            Semantic(el.usage,el.usage_index),shader.info->attributes,shader.info->count);
        if (visualExperiments_ & mcla::metal::PackedVertexColor) plan.swapColor=false;
        mcla::metal::ApplyVertexFixup(data.data(),src,size,offset+el.offset,stride,plan);
        continue;
      }
      unsigned half = HalfCount(el.type);
      for (size_t at = offset + el.offset; at + std::max(4u, half * 2) <= size;
           at += stride) {
        if (half) {
          for (unsigned h = 0; h < half; ++h) {
            uint16_t v;
            memcpy(&v, src + at + h * 2, 2);
            v = __builtin_bswap16(v);
            memcpy(data.data() + at + h * 2, &v, 2);
          }
        } else if (el.type == 0x1A2187) {
          uint32_t v;
          memcpy(&v, data.data() + at, 4);
          v = (v & 0x3FFFFFFF) | 0x40000000;
          memcpy(data.data() + at, &v, 4);
        } else if (el.type == 0x182886 && !(visualExperiments_ & mcla::metal::PackedVertexColor)) {
          for (unsigned a = 0; a < shader.info->count; ++a)
            if (shader.info->attributes[a].semantic ==
                    Semantic(el.usage, el.usage_index) &&
                shader.info->attributes[a].numeric == 1)
              std::swap(data[at], data[at + 2]);
        }
      }
    }
    if (mcla::native::QuadFetchScaleWord(shader.info->hash)) {
      auto expanded =
          mcla::native::ExpandQuadFetchPayload(data, offset, stride);
      if (!expanded)
        return {};
      data = std::move(*expanded);
    }
    if (inlineAddress && currentPrimitive_ == 8)
      data = ExpandRectangles(data, stride, decl);
    if (data.empty())
      return {};
    // Dynamic/locked and inline payloads may change every draw. Allocating a
    // standalone MTLBuffer for each one eventually pressures the device heap
    // during long drives. Suballocate them from the existing three-flight
    // upload ring, whose semaphore already guarantees safe reuse.
    if (inlineAddress || locked) {
      auto upload = Allocate(data.size());
      if (!upload.cpu)
        return {};
      memcpy(upload.cpu, data.data(), data.size());
      VertexUpload result{upload.buffer, upload.offset};
      DynamicVertexUpload cached{};
      cached.upload = result;
      if (locked && !inlineAddress)
        cached.shadow.assign(src, src + size);
      dynamicVertexUploads_.emplace(dynamicKey, std::move(cached));
      return result;
    }
    auto buffer = [device_ newBufferWithBytes:data.data()
                                       length:data.size()
                                      options:MTLResourceStorageModeShared];
    if (!buffer)
      return {};
    Buffer cached{buffer, address, size, frames_};
    buffers_[key] = std::move(cached);
    bufferIndex_.Touch(key,frames_);
    bufferIndex_.AddOwner(key,bind.buffer);
    bufferIndex_.BindAlias(key,wrapperKey);
    return remember({buffer, 0});
  }
  bool planVertexFixups_ = true;
  uint32_t visualExperiments_ = MCLAGraphicsVisualExperiments();
  std::array<uint64_t,128> colorAuditKeys_{};
  unsigned colorAuditCount_=0;
  bool InspectHUDDraw(const uint8_t* state,
      const ng::RegisterVertexDeclarationCommand& decl, uint32_t primitive,
      uint32_t start, uint32_t count, bool indexed, int32_t baseVertex,
      uint32_t inlineAddress, uint32_t inlineStride,
      mcla::metal::HudBounds* bounds = nullptr, uint32_t availableCount = 0) {
    if (count < 3 || count > (bounds ? 4096u : 6u)) return false;
    const ng::VertexElement* position = nullptr;
    for (unsigned i=0;i<decl.element_count;++i)
      if (decl.elements[i].usage == 0 && decl.elements[i].usage_index == 0)
        position = &decl.elements[i];
    if (!position || position->type != 0x2A23B9 || position->stream >= 17) return false;
    const auto bind = streams_[position->stream];
    const uint32_t sourceCount=availableCount ? availableCount : count;
    if (inlineAddress && uint64_t(sourceCount)*inlineStride > 64u*1024u*1024u) return false;
    uint32_t address=inlineAddress, size=inlineAddress ? sourceCount*inlineStride : 0;
    const uint32_t stride=inlineAddress ? inlineStride : bind.stride;
    uint32_t offset=inlineAddress ? 0 : bind.offset;
    if (!inlineAddress) {
      auto header=P(bind.buffer,32); if (!header) return false;
      auto metadata=ng::DecodeNativeBufferMetadata(R(header),R(header,24),R(header,28));
      if (!metadata || !metadata->HasValidPayload(64*1024*1024)) return false;
      address=metadata->guest_address; size=metadata->guest_size;
    }
    if (!stride) return false;
    auto source=P(address,size); if (!source) return false;
    const uint8_t* indices=nullptr; unsigned indexBytes=0;
    if (indexed) {
      auto header=P(index_,32); if (!header) return false;
      auto metadata=ng::DecodeNativeBufferMetadata(R(header),R(header,24),R(header,28));
      indexBytes=(R(header)&0x80000000u)?4:2;
      if (!metadata || (uint64_t(start)+count)*indexBytes > metadata->guest_size) return false;
      indices=P(metadata->guest_address,metadata->guest_size); if (!indices) return false;
    }
    std::array<std::array<float,4>,6> clips{};
    mcla::metal::HudBounds box{INFINITY, INFINITY, -INFINITY, -INFINITY};
    for (unsigned i=0;i<count;++i) {
      int64_t vertex=start+i;
      if (indexed) {
        const auto at=indices+(uint64_t(start)+i)*indexBytes;
        vertex=int64_t(baseVertex)+(indexBytes==4 ? (R(at)&0xFFFFFF) : ((unsigned(at[0])<<8)|at[1]));
      }
      if (vertex < 0) return false;
      const uint64_t at=uint64_t(offset)+position->offset+uint64_t(vertex)*stride;
      if (at+12 > size) return false;
      const float xyz[]={F(source,unsigned(at)),F(source,unsigned(at)+4),F(source,unsigned(at)+8)};
      // This shader's audited fetch/ALU sequence is p.x*c8+p.y*c9+p.z*c10+c11.
      std::array<float,4> clip{};
      for (unsigned component=0;component<4;++component)
        clip[component]=xyz[0]*F(state,1920+8*16+component*4)+
          xyz[1]*F(state,1920+9*16+component*4)+
          xyz[2]*F(state,1920+10*16+component*4)+F(state,1920+11*16+component*4);
      if (bounds) {
        if (!std::isfinite(clip[3]) || clip[3] <= 0) return false;
        const float px = F(state,12640) + (clip[0]/clip[3]+1)*.5f*F(state,12648);
        const float py = F(state,12644) + (1-clip[1]/clip[3])*.5f*F(state,12652);
        if (!std::isfinite(px) || !std::isfinite(py)) return false;
        box.left=std::min(box.left,px); box.right=std::max(box.right,px);
        box.top=std::min(box.top,py); box.bottom=std::max(box.bottom,py);
      } else clips[i]=clip;
    }
    if (bounds) { *bounds=box; return true; }
    return mcla::metal::FullScreenOverlay({clips.data(),count},primitive==8);
  }
  bool Draw(uint32_t dev, uint32_t primitive, uint32_t start, uint32_t count,
            bool indexed, int32_t baseVertex, uint32_t data = 0,
            uint32_t stride = 0) {
    currentPrimitive_ = primitive;
    const bool sample=profile_ && ((draws_&63)==0);
    double stamp=sample?CACurrentMediaTime():0;
    uint64_t cpuStamp=sample?mcla::metal::ThreadCPUTimeNanoseconds():0;
    auto mark=[&](unsigned section){if(sample){
      const double now=CACurrentMediaTime();
      const uint64_t cpuNow=mcla::metal::ThreadCPUTimeNanoseconds();
      const double wallMS=(now-stamp)*1000;
      const double cpuMS=cpuNow>=cpuStamp?(cpuNow-cpuStamp)/1000000.0:0;
      profileMS_[section]+=wallMS;
      frameProfileWallMS_[section]+=wallMS;
      frameProfileCPUMS_[section]+=cpuMS;
      stamp=now;cpuStamp=cpuNow;
    }};
    auto raw = P(dev, ng::kGuestDeviceSize);
    if (!raw)
      return Fail("device");
    auto vs = GetShader(vs_), ps = GetShader(ps_);
    if (!vs || (ps_ && !ps))
      return Fail("shader");
    const bool fullSnapshot = renderProbe_ || frames_ == passCaptureFrame_;
    auto state = MCLANativeCanonicalDevice(raw,
        fullSnapshot ? nullptr : vs->info->constants,
        fullSnapshot || !ps ? nullptr : ps->info->constants, !fullSnapshot && optimizeDrawState_);
    auto dit = declarations_.find(decl_);
    if (dit == declarations_.end())
      return Fail("declaration");
    auto &decl = dit->second;
    CaptureProbeInputs(state, ps ? ps->info->hash : 0);
    const bool capturePass = !renderProbe_ && frames_ == passCaptureFrame_ && count <= 6 &&
                             R(state,11868) == 0;
    if (capturePass)
      CapturePass(Target(Describe(R(state,12432)), false), "before", ps ? ps->info->hash : 0);
    CapturePixelHistory(state, ps ? ps->info->hash : 0, 0, true);
    if (!Attach(state))
      return Fail("attachments");
    const bool hasDepthAttachment = depth_ != nil;
    const bool hasStencilAttachment =
        hasDepthAttachment &&
        depth_.pixelFormat == MTLPixelFormatDepth32Float_Stencil8;
    mark(0);
    std::array<uint32_t,32> fastFields{};
    for(unsigned i=0;i<17;++i)fastFields[i]=data?stride:streams_[i].stride;
    for(unsigned i=0;i<4;++i)fastFields[17+i]=uint32_t(colors_[i]?colors_[i].pixelFormat:MTLPixelFormatInvalid);
    fastFields[21]=uint32_t(depth_?depth_.pixelFormat:MTLPixelFormatInvalid);
    fastFields[22]=R(state,10460);fastFields[23]=R(state,11844);
    fastFields[24]=R(state,10552);fastFields[25]=R(state,10584);
    fastFields[26]=R(state,10588);fastFields[27]=R(state,10592);
    fastFields[28]=R(state,10556)&15;fastFields[29]=data!=0;
    std::array<uint64_t,20> exactPipeline{vs->info->hash,ps?ps->info->hash:0,
                                         decl_,declarationRevision_};
    memcpy(exactPipeline.data()+4,fastFields.data(),sizeof(fastFields));
    auto prepare=[&]()->PreparedPipeline {
    if(lastPipelineKey_.Matches(exactPipeline)) { ++pipelineReuses_; return lastPrepared_; }
    uint64_t fastKey=vs->info->hash^std::rotl(ps?ps->info->hash:0,17);
    fastKey=Hash(decl.elements,decl.element_count*sizeof(ng::VertexElement),fastKey);
    fastKey=Hash(fastFields.data(),sizeof(fastFields),fastKey);
    if(auto hit=prepared_.find(fastKey);hit!=prepared_.end())return hit->second;
    auto vd = [MTLVertexDescriptor vertexDescriptor];
    uint64_t key = vs->info->hash ^ std::rotl(ps ? ps->info->hash : 0, 17);
    key = Hash(decl.elements, decl.element_count * sizeof(ng::VertexElement),
               key);
    std::array<bool, 17> needed{};
    for (unsigned i = 0; i < vs->info->count; ++i) {
      auto a = vs->info->attributes[i];
      const ng::VertexElement *e = nullptr;
      for (unsigned j = 0; j < decl.element_count; ++j)
        if (Semantic(decl.elements[j].usage, decl.elements[j].usage_index) ==
            a.semantic) {
          e = &decl.elements[j];
          break;
        }
      if(!e){
        vd.attributes[a.location].format=a.numeric==1?MTLVertexFormatUInt4:a.numeric==2?MTLVertexFormatInt4:MTLVertexFormatFloat4;
        vd.attributes[a.location].bufferIndex=a.numeric?27:26;
        vd.layouts[a.numeric?27:26].stride=16;
        vd.layouts[a.numeric?27:26].stepFunction=MTLVertexStepFunctionConstant;
        // Constant attributes fetch exactly once. Metal rejects the default
        // per-vertex stepRate (1) with a constant step function.
        vd.layouts[a.numeric?27:26].stepRate=0;
        continue;
      }
      if(e->stream>=17){Fail("attribute");return {};}
      unsigned step = data ? stride : streams_[e->stream].stride;
      if (!step)
        {Fail("stride");return {};}
      auto format = VertexFormat(e->type, a.numeric,
          mcla::metal::PackedColorShaderCorrection(vs->info->hash,
              visualExperiments_ & mcla::metal::PackedVertexColor));
      if (data && e->usage == 5 && format == MTLVertexFormatFloat &&
          a.components >= 2 && e->offset + 8 <= step)
        format = MTLVertexFormatFloat2;
      if (format == MTLVertexFormatInvalid)
        {Fail("vertex-format");return {};}
      vd.attributes[a.location].format = format;
      vd.attributes[a.location].offset = e->offset;
      vd.attributes[a.location].bufferIndex = 9 + e->stream;
      vd.layouts[9 + e->stream].stride = step;
      needed[e->stream] = true;
      uint64_t v = uint64_t(format) << 32 | step;
      key = Hash(&v, 8, key);
    }
    const uint32_t alpha = R(state, 10556),
                   spec = (alpha & 8) ? (2 | ((alpha & 7) << 8)) : 0;
    key = Hash(&spec, 4, key);
    auto pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = Function(*vs, 0);
    pd.fragmentFunction = ps ? Function(*ps, spec) : nil;
    pd.vertexDescriptor = vd;
    pd.rasterSampleCount = 1;
    const unsigned blendOffsets[] = {10552, 10584, 10588, 10592};
    uint32_t mask = ps ? R(state, 10460) : 0;
    for (unsigned i = 0; i < 4; ++i) {
      auto a = pd.colorAttachments[i];
      a.pixelFormat =
          colors_[i] ? colors_[i].pixelFormat : MTLPixelFormatInvalid;
      uint32_t bits = (mask >> (i * 4)) & 15;
      a.writeMask =
          MTLColorWriteMask(((bits & 1) ? 8 : 0) | ((bits & 2) ? 4 : 0) |
                            ((bits & 4) ? 2 : 0) | ((bits & 8) ? 1 : 0));
      uint32_t b = R(state, blendOffsets[i]);
      a.blendingEnabled = (R(state, 11844) >> 31) && colors_[i] != nil;
      a.sourceRGBBlendFactor = BlendFactor(b & 31);
      a.destinationRGBBlendFactor = BlendFactor((b >> 8) & 31);
      a.rgbBlendOperation = BlendOp((b >> 5) & 7);
      a.sourceAlphaBlendFactor = BlendFactor((b >> 16) & 31);
      a.destinationAlphaBlendFactor = BlendFactor((b >> 24) & 31);
      a.alphaBlendOperation = BlendOp((b >> 21) & 7);
      std::array<uint32_t, 4> k{uint32_t(a.pixelFormat), bits, b,
                                uint32_t(a.blendingEnabled)};
      key = Hash(k.data(), sizeof(k), key);
    }
    pd.depthAttachmentPixelFormat =
        hasDepthAttachment ? depth_.pixelFormat : MTLPixelFormatInvalid;
    pd.stencilAttachmentPixelFormat =
        hasStencilAttachment ? depth_.pixelFormat : MTLPixelFormatInvalid;
    uint32_t df = uint32_t(pd.depthAttachmentPixelFormat);
    key = Hash(&df, 4, key);
    auto pipeline = pipelines_[key];
    if (!pipeline) {
      NSError *error = nil;
      pipeline = [device_ newRenderPipelineStateWithDescriptor:pd error:&error];
      if (!pipeline) {
        if (failed_ < 24)
          REXLOG_ERROR("MCLA METAL pipeline {}",
                       error.localizedDescription.UTF8String);
        Fail("pipeline");return {};
      }
      pipelines_[key] = pipeline;
    }
    PreparedPipeline result{pipeline,needed};prepared_[fastKey]=result;return result;
    };
    auto prepared=prepare();if(!prepared.pipeline)return false;
    lastPipelineKey_.Remember(exactPipeline); lastPrepared_=prepared;
    const auto& needed=prepared.needed;
    mark(1);
    if (boundPipeline_ != prepared.pipeline) {
      [encoder_ setRenderPipelineState:prepared.pipeline];
      boundPipeline_ = prepared.pipeline;
    }
    uint32_t ds = R(state, 10548);
    std::array<uint32_t, 7> dk{ds, R(state, 11868), R(state, 11872),
                               R(state, 10492), R(state, 10496),
                               uint32_t(hasDepthAttachment),
                               uint32_t(hasStencilAttachment)};
    const bool twoSidedStencil = (ds & 128) != 0;
    id<MTLDepthStencilState> depthState = nil;
    if (optimizeDrawState_ && !preparedDepthKey_.Update(dk)) {
      depthState = preparedDepthState_;
      ++depthLookupReuses_;
    } else {
      uint64_t depthKey = Hash(dk.data(), sizeof(dk));
      depthState = depths_[depthKey];
      if (!depthState) {
        auto d = [MTLDepthStencilDescriptor new];
        // Xenos state may retain depth/stencil enables while the title switches
        // to a color-only target. Metal requires the state to match the actual
        // render-pass attachments, so make those retained bits inert until the
        // corresponding attachment is bound again.
        d.depthCompareFunction =
            hasDepthAttachment && dk[1]
                ? MTLCompareFunction((ds >> 4) & 7)
                : MTLCompareFunctionAlways;
        d.depthWriteEnabled = hasDepthAttachment && dk[1] && (ds & 4);
        if (hasStencilAttachment && dk[2]) {
          for (unsigned back = 0; back < 2; ++back) {
            auto s = [MTLStencilDescriptor new];
            const bool useBackState = back && twoSidedStencil;
            unsigned shift = useBackState ? 20 : 8;
            s.stencilCompareFunction = MTLCompareFunction((ds >> shift) & 7);
            s.stencilFailureOperation = StencilOp(ds >> (shift + 3));
            s.depthStencilPassOperation = StencilOp(ds >> (shift + 6));
            s.depthFailureOperation = StencilOp(ds >> (shift + 9));
            s.readMask = state[useBackState ? 10494 : 10498];
            s.writeMask = state[useBackState ? 10493 : 10497];
            if (back)
              d.backFaceStencil = s;
            else
              d.frontFaceStencil = s;
          }
        }
        depthState = [device_ newDepthStencilStateWithDescriptor:d];
        depths_[depthKey] = depthState;
      }
      preparedDepthState_ = depthState;
      // Retry a failed Metal allocation rather than caching a nil state.
      if (!depthState) preparedDepthKey_.Reset();
    }
    if (boundDepthState_ != depthState) {
      [encoder_ setDepthStencilState:depthState];
      boundDepthState_ = depthState;
    }
    const std::array<uint32_t,2> references{
        state[10499], state[twoSidedStencil ? 10495 : 10499]};
    if (UpdateDynamic(stencilReferences_, references))
      [encoder_ setStencilFrontReferenceValue:references[0]
                          backReferenceValue:references[1]];
    const uint32_t rasterControl = R(state, 10568);
    unsigned cull = (rasterControl & 4u) |
                    mcla::metal::GuestCullMode(rasterControl,
                                               currentPrimitive_);
    const auto winding = (cull & 4) ? MTLWindingClockwise : MTLWindingCounterClockwise;
    const auto culling = (cull & 3) == 1 ? MTLCullModeFront
                       : (cull & 3) == 2 ? MTLCullModeBack : MTLCullModeNone;
    if (UpdateDynamic(winding_, std::array<uint32_t,1>{uint32_t(winding)}))
      [encoder_ setFrontFacingWinding:winding];
    if (UpdateDynamic(culling_, std::array<uint32_t,1>{uint32_t(culling)}))
      [encoder_ setCullMode:culling];
    // CanonicalDevice remaps the title's polygon-offset shadow to these
    // slots. Reset even when disabled so a previous draw cannot leak bias.
    const auto bias = mcla::metal::GuestRasterDepthBias(
        rasterControl, (R(state, 10376) >> 16) & 1u,
        hasDepthAttachment && primitive >= 4,
        F(state, 10836), F(state, 10832),
        F(state, 10844), F(state, 10840));
    if (UpdateDynamic(depthBias_, std::array<float,3>{bias.constant,bias.slope,0}))
      [encoder_ setDepthBias:bias.constant slopeScale:bias.slope clamp:0];
    float w = F(state, 12648), h = F(state, 12652), x = F(state, 12640),
          y = F(state, 12644);
    if (!std::isfinite(w) || !std::isfinite(h) || w <= 0 || h <= 0)
      return Fail("viewport");
    const auto& logicalTarget = colors_[0] ? drawSurfaces_[0] : drawDepthSurface_;
    unsigned aw = unsigned(colors_[0] ? colors_[0].width : depth_.width),
             ah = unsigned(colors_[0] ? colors_[0].height : depth_.height);
    // The gameplay trace identifies this exact textured 2D program in the
    // late HUD pass. Its retained depth attachment means that a generic
    // "no depth" heuristic misses the minimap and speedometer. Keep this
    // authored 2D program in a centered 16:9 frame; the camera scene and
    // post-processing retain full device aspect.
    // The outline/stencil layers share the audited HUD vertex transform but
    // use different fragment/blend states. Frame and move those layers with
    // the textured fill, rather than leaving the rim at its original location.
    const bool safeFrameDraw = hudSafeFrameProbe_ &&
        logicalTarget.width == 1280 && logicalTarget.height == 720 &&
        (uint64_t(aw)*720 != uint64_t(ah)*1280) &&
        vs->info->hash == 0xF8B6972A1D56B354ULL;
    const bool fullScreenOverlay = safeFrameDraw &&
        (visualExperiments_ & mcla::metal::FullScreenFades) &&
        InspectHUDDraw(state,decl,primitive,start,count,indexed,baseVertex,data,stride);
    auto safe = safeFrameDraw && !fullScreenOverlay
        ? mcla::metal::HudSafeFrame(aw, ah)
        : mcla::metal::SafeFrame{0,0,aw,ah};
    const double viewportScaleX = double(safe.width)/logicalTarget.width;
    const double viewportScaleY = double(safe.height)/logicalTarget.height;
    if (frames_ == hudTraceFrame_)
      REXLOG_INFO("MCLA HUD TRACE draw={} vs={:016X} ps={:016X} target={}x{} logical={}x{} depth={} depth_enable={} blend={} safe={} primitive={} count={} indexed={} viewport={:.1f},{:.1f},{:.1f},{:.1f} scissor={:08X},{:08X}",
                  draws_, vs->info->hash, ps ? ps->info->hash : 0,
                  aw, ah, logicalTarget.width, logicalTarget.height,
                  hasDepthAttachment, R(state,11868), R(state,11844) >> 31,
                  safeFrameDraw,
                  primitive, count, indexed, x, y, w, h,
                  R(state,10436), R(state,10440));
    mcla::metal::HudMove hudMove{};
    if ((MCLAGraphicsVisualExperiments() & mcla::metal::RaisedDrivingHUD) &&
        logicalTarget.width == 1280 && logicalTarget.height == 720 &&
        vs->info->hash == 0xF8B6972A1D56B354ULL && !fullScreenOverlay) {
      mcla::metal::HudBounds bounds{};
      if (InspectHUDDraw(state,decl,primitive,start,count,indexed,
                               baseVertex,data,stride,&bounds))
        hudMove=mcla::metal::RaisedHudMove(bounds);
      if (frames_ == hudTraceFrame_)
        REXLOG_INFO("MCLA HUD MOVE draw={} group={} bounds={:.1f},{:.1f},{:.1f},{:.1f} scale={} dx={} dy={}",
            draws_,hudMove.name,bounds.left,bounds.top,bounds.right,bounds.bottom,hudMove.scale,hudMove.x,hudMove.y);
    }
    // UI rims can be batched with other HUD elements. Classify independent
    // triangles/quads when the complete batch spans multiple regions, keeping
    // unrelated primitives in place and preserving their original draw order.
    std::vector<mcla::metal::HudMove> hudSlices;
    const uint32_t hudStep=primitive==13 ? 4 : primitive==4 ? 3 : 0;
    if ((MCLAGraphicsVisualExperiments() & mcla::metal::RaisedDrivingHUD) &&
        logicalTarget.width==1280 && logicalTarget.height==720 &&
        vs->info->hash==0xF8B6972A1D56B354ULL && !fullScreenOverlay &&
        hudMove.x==0 && hudMove.y==0 && hudStep && count<=256 && count%hudStep==0) {
      bool anyMoved=false;
      for(uint32_t first=0;first<count;first+=hudStep) {
        mcla::metal::HudBounds bounds{};
        mcla::metal::HudMove move{};
        if(InspectHUDDraw(state,decl,primitive,start+first,hudStep,indexed,
                          baseVertex,data,stride,&bounds,count))
          move=mcla::metal::RaisedHudMove(bounds);
        anyMoved |= move.x!=0 || move.y!=0;
        hudSlices.push_back(move);
      }
      if(!anyMoved) hudSlices.clear();
    }
    safe=mcla::metal::AnchoredHudFrame(safe,aw,hudMove);
    const double hudOffsetX=hudMove.x*viewportScaleX+safe.left*(1-hudMove.scale);
    const double hudOffsetY=hudMove.y*viewportScaleY+safe.top*(1-hudMove.scale);
    const std::array<double,6> viewport{
        safe.left+(x*hudMove.scale+hudMove.x)*viewportScaleX,
        safe.top+(y*hudMove.scale+hudMove.y)*viewportScaleY,
        w*hudMove.scale*viewportScaleX, h*hudMove.scale*viewportScaleY,
        std::clamp(double(F(state, 12656)), 0., 1.),
        std::clamp(double(F(state, 12660)), 0., 1.)};
    if (UpdateDynamic(viewport_, viewport))
      [encoder_ setViewport:MTLViewport{viewport[0],viewport[1],viewport[2],
                                       viewport[3],viewport[4],viewport[5]}];
    uint32_t tl = R(state, 10436), br = R(state, 10440);
    unsigned sx = safe.left + mcla::metal::ScaleEdge(tl & 32767, logicalTarget.width, safe.width),
             sy = safe.top + mcla::metal::ScaleEdge((tl >> 16) & 32767, logicalTarget.height, safe.height),
             ex = safe.left + mcla::metal::ScaleEdge(br & 32767, logicalTarget.width, safe.width),
             ey = safe.top + mcla::metal::ScaleEdge((br >> 16) & 32767, logicalTarget.height, safe.height);
    if (hudMove.scale != 1 || hudMove.x || hudMove.y) {
      sx=mcla::metal::MovedHudEdge(sx,hudMove.scale,hudOffsetX,aw);
      ex=mcla::metal::MovedHudEdge(ex,hudMove.scale,hudOffsetX,aw);
      sy=mcla::metal::MovedHudEdge(sy,hudMove.scale,hudOffsetY,ah);
      ey=mcla::metal::MovedHudEdge(ey,hudMove.scale,hudOffsetY,ah);
    }
    if (ex <= sx || ey <= sy)
      return true;
    const std::array<NSUInteger,4> scissor{sx,sy,ex-sx,ey-sy};
    if (UpdateDynamic(scissor_, scissor))
      [encoder_ setScissorRect:MTLScissorRect{scissor[0],scissor[1],scissor[2],scissor[3]}];
    const std::array<float,4> blend{
        F(state,10464),F(state,10468),F(state,10472),F(state,10476)};
    if (UpdateDynamic(blendColor_, blend))
      [encoder_ setBlendColorRed:blend[0] green:blend[1] blue:blend[2] alpha:blend[3]];
    auto applyHudSlice=[&](const mcla::metal::HudMove& move) {
      const auto frame=mcla::metal::AnchoredHudFrame(safe,aw,move);
      const std::array<double,6> vp{
          frame.left+(x*move.scale+move.x)*viewportScaleX,
          frame.top+(y*move.scale+move.y)*viewportScaleY,
          w*move.scale*viewportScaleX,h*move.scale*viewportScaleY,viewport[4],viewport[5]};
      if(UpdateDynamic(viewport_,vp))
        [encoder_ setViewport:MTLViewport{vp[0],vp[1],vp[2],vp[3],vp[4],vp[5]}];
      const double ox=move.x*viewportScaleX+frame.left*(1-move.scale);
      const double oy=move.y*viewportScaleY+frame.top*(1-move.scale);
      auto edge=[&](unsigned value,bool horizontal) {
        unsigned original=(horizontal ? frame.left : frame.top)+mcla::metal::ScaleEdge(value,
            horizontal ? logicalTarget.width : logicalTarget.height,
            horizontal ? frame.width : frame.height);
        return mcla::metal::MovedHudEdge(original,move.scale,horizontal ? ox : oy,horizontal ? aw : ah);
      };
      unsigned left=edge(tl&32767,true),top=edge((tl>>16)&32767,false);
      unsigned right=edge(br&32767,true),bottom=edge((br>>16)&32767,false);
      if(right<=left || bottom<=top) return false;
      std::array<NSUInteger,4> sr{left,top,right-left,bottom-top};
      if(UpdateDynamic(scissor_,sr)) [encoder_ setScissorRect:MTLScissorRect{sr[0],sr[1],sr[2],sr[3]}];
      return true;
    };
    mark(2);
    for (unsigned s = 0; s < 17; ++s)
      if (needed[s]) {
        auto b =
            VertexBuffer(s, decl, *vs, data, data ? count * stride : 0, stride);
        if (!b)
          return Fail("vertex-buffer");
        const size_t offset=b.offset+(data?0:streams_[s].offset);
        if(boundVertices_[s].buffer==b.buffer && boundVertices_[s].offset==offset)
          ++vertexBindSkips_;
        else {
          [encoder_ setVertexBuffer:b.buffer offset:offset atIndex:9+s];
          boundVertices_[s]={b.buffer,offset};
        }
      }
    mark(3);
    if (!BindResources(state, vs->info, ps ? ps->info : nullptr))
      return Fail("bindings");
    mark(4);
    MTLPrimitiveType type = primitive == 1   ? MTLPrimitiveTypePoint
                            : primitive == 2 ? MTLPrimitiveTypeLine
                            : primitive == 3 ? MTLPrimitiveTypeLineStrip
                            : primitive == 6 ? MTLPrimitiveTypeTriangleStrip
                                             : MTLPrimitiveTypeTriangle;
    auto indexLease=indexScratch_.Use(0,reuseGeometryScratch_);
    auto expansionLease=expandedIndexScratch_.Use(0,reuseGeometryScratch_);
    auto& idx=indexLease.values();
    auto& expanded=expansionLease.values();
    Upload persistentIndexUpload{};
    uint32_t persistentIndexCount = 0;
    bool persistentIndexHit = false, persistentIndexCandidate = false;
    uint64_t indexWrapperKey = 0, indexContentSeed = 0;
    std::array<uint64_t,9> exactIndex{};
    if (indexed) {
      auto p = P(index_, 32);
      if (!p)
        return Fail("index-object");
      exactIndex={frames_,resourceRevision_,index_,uint64_t(start)<<32|count,primitive};
      memcpy(exactIndex.data()+5,p,32);
      if(lastIndexKey_.Matches(exactIndex)) {
        persistentIndexCandidate=persistentIndexHit=true;
        persistentIndexUpload=lastIndexUpload_;
        persistentIndexCount=lastIndexCount_;
        ++indexReuses_;
      } else {
      auto m = ng::DecodeNativeBufferMetadata(R(p), R(p, 24), R(p, 28));
      bool index32 = R(p) & 0x80000000;
      unsigned bytes = index32 ? 4 : 2;
      if (!m || (uint64_t(start) + count) * bytes > m->guest_size)
        return Fail("index-range");
      persistentIndexCandidate = !m->guest_locked;
      if (persistentIndexCandidate) {
        const std::array<uint64_t, 3> interpretation{
            uint64_t(m->guest_address) << 32 | m->guest_size,
            uint64_t(start) << 32 | count,
            uint64_t(primitive) << 32 | uint64_t(index32)};
        indexContentSeed = Hash(interpretation.data(), sizeof(interpretation),
                                0x4D434C4150494458ull);
        const std::array<uint64_t, 2> wrapper{index_, indexContentSeed};
        indexWrapperKey = Hash(wrapper.data(), sizeof(wrapper));
        auto alias = indexBufferIndex_.FindAlias(indexWrapperKey);
        if (alias) {
          auto cached = indexBuffers_.find(*alias);
          if (cached != indexBuffers_.end()) {
            if(cached->second.frame!=frames_)indexBufferIndex_.Touch(*alias,frames_);
            cached->second.frame = frames_;
            persistentIndexUpload = {cached->second.buffer, 0, nullptr};
            persistentIndexCount = cached->second.count;
            persistentIndexHit = true;
          } else {
            indexBufferIndex_.Erase(*alias);
          }
        }
      }
      if (!persistentIndexHit) {
        auto src = P(m->guest_address, m->guest_size);
        if (!src)
          return Fail("index-payload");
        idx.resize(count);
        for (unsigned i = 0; i < count; ++i) {
          unsigned off = (start + i) * bytes;
          idx[i] = index32 ? (R(src, off) & 0xFFFFFF)
                           : ((src[off] << 8) | src[off + 1]);
        }
      }
      }
    }
    if (!persistentIndexHit && primitive == 8) {
      if (!data || indexed || count % 3)
        return Fail("rectangle-layout");
      expanded.reserve(size_t(count/3)*6);
      for (unsigned i = 0; i < count / 3; ++i) {
        unsigned v = i * 4;
        expanded.insert(expanded.end(), {v, v + 1, v + 2, v + 2, v + 1, v + 3});
      }
      idx.swap(expanded);
      indexed = true;
    } else if (!persistentIndexHit && primitive == 13) {
      expanded.reserve(size_t(count/4)*6);
      for (unsigned i = 0; i + 4 <= count; i += 4) {
        auto ix = [&](unsigned j) {
          return indexed ? idx[i + j] : start + i + j;
        };
        expanded.insert(expanded.end(),
                            {ix(0), ix(1), ix(2), ix(0), ix(2), ix(3)});
      }
      idx.swap(expanded);
      indexed = true;
    } else if (!persistentIndexHit && primitive == 5) {
      expanded.reserve(count>2?size_t(count-2)*3:0);
      auto ix = [&](unsigned i) { return indexed ? idx[i] : start + i; };
      for (unsigned i = 1; i + 1 < count; ++i)
        expanded.insert(expanded.end(), {ix(0), ix(i), ix(i + 1)});
      idx.swap(expanded);
      indexed = true;
    }
    if (indexed) {
      Upload u{};
      uint32_t indexCount = 0;
      if (persistentIndexHit) {
        u = persistentIndexUpload;
        indexCount = persistentIndexCount;
      } else {
        const size_t indexBytes = idx.size() * sizeof(uint32_t);
        const uint64_t indexKey = Hash(
            idx.data(), indexBytes,
            persistentIndexCandidate ? indexContentSeed
                                     : 0x4D434C41494E4458ull);
        indexCount = uint32_t(idx.size());
        if (persistentIndexCandidate) {
          auto cached = indexBuffers_.find(indexKey);
          if (cached != indexBuffers_.end()) {
            if(cached->second.frame!=frames_)indexBufferIndex_.Touch(indexKey,frames_);
            cached->second.frame = frames_;
            u = {cached->second.buffer, 0, nullptr};
            indexCount = cached->second.count;
          } else {
            auto buffer = [device_ newBufferWithBytes:idx.data()
                                               length:indexBytes
                                              options:MTLResourceStorageModeShared];
            if (!buffer)
              return Fail("index-buffer");
            IndexBuffer entry{buffer, indexCount, frames_};
            indexBuffers_[indexKey] = std::move(entry);
            indexBufferIndex_.Touch(indexKey,frames_);
            u = {buffer, 0, nullptr};
          }
          indexBufferIndex_.AddOwner(indexKey,index_);
          indexBufferIndex_.BindAlias(indexKey,indexWrapperKey);
        } else {
          auto cached = dynamicIndexUploads_.find(indexKey);
          if (cached != dynamicIndexUploads_.end()) {
            u = cached->second;
          } else {
            u = Allocate(indexBytes);
            if (!u.cpu)
              return Fail("index-upload");
            memcpy(u.cpu, idx.data(), indexBytes);
            dynamicIndexUploads_.emplace(indexKey, u);
          }
        }
      }
      if(persistentIndexCandidate) {
        lastIndexKey_.Remember(exactIndex);
        lastIndexUpload_=u; lastIndexCount_=indexCount;
      }
      if(hudSlices.empty()) {
        [encoder_ drawIndexedPrimitives:type indexCount:indexCount indexType:MTLIndexTypeUInt32
            indexBuffer:u.buffer indexBufferOffset:u.offset instanceCount:1 baseVertex:baseVertex baseInstance:0];
      } else {
        const uint32_t sliceCount=primitive==13 ? 6 : 3;
        for(size_t i=0;i<hudSlices.size();++i)
          if(applyHudSlice(hudSlices[i]))
            [encoder_ drawIndexedPrimitives:type indexCount:sliceCount indexType:MTLIndexTypeUInt32
                indexBuffer:u.buffer indexBufferOffset:u.offset+i*sliceCount*sizeof(uint32_t)
                instanceCount:1 baseVertex:baseVertex baseInstance:0];
      }
    } else if(hudSlices.empty()) {
      [encoder_ drawPrimitives:type vertexStart:start vertexCount:count];
    } else {
      for(size_t i=0;i<hudSlices.size();++i)
        if(applyHudSlice(hudSlices[i]))
          [encoder_ drawPrimitives:type vertexStart:start+i*hudStep vertexCount:hudStep];
    }
    ++draws_;
    if(gpuPassTrace_)gpuPassTrace_->Draw(vs->info->hash,ps?ps->info->hash:0);
    mark(5);if(sample){++profileSamples_;++frameProfileSamples_;}
    CapturePixelHistory(state, ps ? ps->info->hash : 0,
                        vs->info->textures | (ps ? ps->info->textures : 0));
    if (capturePass)
      CapturePass(colors_[0], "after", ps ? ps->info->hash : 0);
    return true;
  }
  bool Clear(const ng::ClearCommand &c) {
    auto raw = P(c.device, ng::kGuestDeviceSize);
    if (!raw)
      return false;
    auto s = MCLANativeCanonicalDevice(raw);
    std::array<id<MTLTexture>, 4> colors{};
    auto logicalTarget = Describe(R(s, 12448));
    for (unsigned i = 0; i < 4; ++i)
      colors[i] = Target(Describe(R(s, 12432 + i * 4)), false);
    for (unsigned i = 0; i < 4; ++i)
      if (colors[i]) { logicalTarget = Describe(R(s, 12432 + i * 4)); break; }
    auto depth = Target(Describe(R(s, 12448)), true);
    EndEncoder();
    Begin();
    unsigned width = depth ? unsigned(depth.width) : 0,
             height = depth ? unsigned(depth.height) : 0;
    for (auto color : colors)
      if (color) {
        width = width ? std::min(width, unsigned(color.width))
                      : unsigned(color.width);
        height = height ? std::min(height, unsigned(color.height))
                        : unsigned(color.height);
      }
    if (!width || !height)
      return true;
    uint32_t guestWidth, guestHeight;
    MCLAGraphicsGuestVideoSize(&guestWidth, &guestHeight);
    const auto physicalTarget = mcla::metal::SceneExtent(logicalTarget.width,
        logicalTarget.height, MCLAGraphicsRenderHeight(), guestWidth, guestHeight);
    const bool implicitFull = c.right <= c.left || c.bottom <= c.top;
    const unsigned left = implicitFull ? 0u : std::min(width,mcla::metal::ScaleEdge(
        unsigned(std::max(c.left, 0)), logicalTarget.width, physicalTarget.width));
    const unsigned top = implicitFull ? 0u : std::min(height,mcla::metal::ScaleEdge(
        unsigned(std::max(c.top, 0)), logicalTarget.height, physicalTarget.height));
    const unsigned right = implicitFull ? width : std::min(width,mcla::metal::ScaleEdge(
        unsigned(std::max(c.right, 0)), logicalTarget.width, physicalTarget.width));
    const unsigned bottom = implicitFull ? height : std::min(height,mcla::metal::ScaleEdge(
        unsigned(std::max(c.bottom, 0)), logicalTarget.height, physicalTarget.height));
    if (right <= left || bottom <= top)
      return true;
    const bool full = left == 0 && top == 0 && right == width &&
                      bottom == height;
    const MTLClearColor clearColor = MTLClearColorMake(
        std::bit_cast<float>(c.color_bits[0]),
        std::bit_cast<float>(c.color_bits[1]),
        std::bit_cast<float>(c.color_bits[2]),
        std::bit_cast<float>(c.color_bits[3]));
    const double clearDepth = std::bit_cast<double>(c.depth_bits);
    if (!full) {
      // Xenos Clear accepts a rectangle. Treating it as a Metal load-action
      // clear wipes the paused 3D scene behind modal UI and leaves menu
      // transition poses in the retained offscreen target. Draw the requested
      // clear rectangle explicitly instead.
      const MTLScissorRect scissor{left, top, right - left, bottom - top};
      const float colorValue[4] = {float(clearColor.red),
                                   float(clearColor.green),
                                   float(clearColor.blue),
                                   float(clearColor.alpha)};
      for (unsigned i = 0; i < 4; ++i) {
        if (!(c.flags & (1u << i)) || !colors[i])
          continue;
        auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = colors[i];
        rp.colorAttachments[0].loadAction = MTLLoadActionLoad;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        const uint64_t key = 0xC100000000000000ull |
                             uint64_t(colors[i].pixelFormat);
        auto pipeline = pipelines_[key];
        if (!pipeline) {
          auto pd = [MTLRenderPipelineDescriptor new];
          pd.vertexFunction = [helpers_ newFunctionWithName:@"copyVertex"];
          pd.fragmentFunction =
              [helpers_ newFunctionWithName:@"clearColorFragment"];
          pd.colorAttachments[0].pixelFormat = colors[i].pixelFormat;
          NSError *error = nil;
          pipeline = [device_ newRenderPipelineStateWithDescriptor:pd
                                                             error:&error];
          if (!pipeline) {
            REXLOG_ERROR("MCLA METAL partial color clear: {}",
                         error.localizedDescription.UTF8String);
            return Fail("partial-color-clear-pipeline");
          }
          pipelines_[key] = pipeline;
        }
        auto e = RenderEncoder(rp,"partial-clear");
        [e setRenderPipelineState:pipeline];
        [e setScissorRect:scissor];
        [e setFragmentBytes:colorValue length:sizeof(colorValue) atIndex:0];
        [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [e endEncoding];
      }
      if (depth && (c.flags & 48)) {
        auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.depthAttachment.texture = depth;
        rp.depthAttachment.loadAction = MTLLoadActionLoad;
        rp.depthAttachment.storeAction = MTLStoreActionStore;
        rp.stencilAttachment.texture = depth;
        rp.stencilAttachment.loadAction = MTLLoadActionLoad;
        rp.stencilAttachment.storeAction = MTLStoreActionStore;
        const std::array<uint32_t, 2> fields{uint32_t(depth.pixelFormat),
                                             c.flags & 48};
        const uint64_t pipelineKey =
            Hash(fields.data(), sizeof(fields), 0xC200000000000000ull);
        auto pipeline = pipelines_[pipelineKey];
        if (!pipeline) {
          auto pd = [MTLRenderPipelineDescriptor new];
          pd.vertexFunction = [helpers_ newFunctionWithName:@"copyVertex"];
          pd.fragmentFunction =
              [helpers_ newFunctionWithName:@"clearDepthFragment"];
          pd.depthAttachmentPixelFormat = depth.pixelFormat;
          pd.stencilAttachmentPixelFormat = depth.pixelFormat;
          NSError *error = nil;
          pipeline = [device_ newRenderPipelineStateWithDescriptor:pd
                                                             error:&error];
          if (!pipeline) {
            REXLOG_ERROR("MCLA METAL partial depth clear: {}",
                         error.localizedDescription.UTF8String);
            return Fail("partial-depth-clear-pipeline");
          }
          pipelines_[pipelineKey] = pipeline;
        }
        const uint64_t depthStateKey =
            Hash(fields.data(), sizeof(fields), 0xC300000000000000ull);
        auto depthState = depths_[depthStateKey];
        if (!depthState) {
          auto d = [MTLDepthStencilDescriptor new];
          d.depthCompareFunction = MTLCompareFunctionAlways;
          d.depthWriteEnabled = (c.flags & 16) != 0;
          if (c.flags & 32) {
            auto stencil = [MTLStencilDescriptor new];
            stencil.stencilCompareFunction = MTLCompareFunctionAlways;
            stencil.stencilFailureOperation = MTLStencilOperationKeep;
            stencil.depthFailureOperation = MTLStencilOperationKeep;
            stencil.depthStencilPassOperation = MTLStencilOperationReplace;
            stencil.readMask = 0xFF;
            stencil.writeMask = 0xFF;
            d.frontFaceStencil = stencil;
            d.backFaceStencil = stencil;
          }
          depthState = [device_ newDepthStencilStateWithDescriptor:d];
          depths_[depthStateKey] = depthState;
        }
        const float depthValue = float(clearDepth);
        auto e = RenderEncoder(rp,"depth-clear");
        [e setRenderPipelineState:pipeline];
        [e setDepthStencilState:depthState];
        [e setStencilReferenceValue:c.stencil];
        [e setScissorRect:scissor];
        [e setFragmentBytes:&depthValue length:sizeof(depthValue) atIndex:0];
        [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [e endEncoding];
      }
      return true;
    }
    auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
    for (unsigned i = 0; i < 4; ++i)
      if (colors[i]) {
        auto a = rp.colorAttachments[i];
        a.texture = colors[i];
        a.loadAction =
            c.flags & (1u << i) ? MTLLoadActionClear : MTLLoadActionLoad;
        a.storeAction = MTLStoreActionStore;
        a.clearColor = clearColor;
      }
    if (depth) {
      rp.depthAttachment.texture = depth;
      rp.depthAttachment.loadAction =
          c.flags & 16 ? MTLLoadActionClear : MTLLoadActionLoad;
      rp.depthAttachment.storeAction = MTLStoreActionStore;
      rp.depthAttachment.clearDepth = clearDepth;
      rp.stencilAttachment.texture = depth;
      rp.stencilAttachment.loadAction =
          c.flags & 32 ? MTLLoadActionClear : MTLLoadActionLoad;
      rp.stencilAttachment.storeAction = MTLStoreActionStore;
      rp.stencilAttachment.clearStencil = c.stencil;
    }
    auto e = RenderEncoder(rp,"clear");
    [e endEncoding];
    return true;
  }
  bool CopyColor(id<MTLTexture> src, id<MTLTexture> dst, bool present = false,
                 float scale = 1.f, NSUInteger destinationLevel = 0,
                 NSUInteger destinationSlice = 0, NSUInteger sourceX = 0,
                 NSUInteger sourceY = 0, NSUInteger sourceWidth = 0,
                 NSUInteger sourceHeight = 0, NSUInteger destinationX = 0,
                 NSUInteger destinationY = 0, NSUInteger destinationRegionWidth = 0,
                 NSUInteger destinationRegionHeight = 0) {
    if (!src || !dst)
      return false;
    if(present && frameFSREnabled_)return Upscale(src,dst);
    EndEncoder();
    Begin();
    auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = dst;
    rp.colorAttachments[0].level = destinationLevel;
    if (dst.textureType == MTLTextureType3D)
      rp.colorAttachments[0].depthPlane = destinationSlice;
    else
      rp.colorAttachments[0].slice = destinationSlice;
    const NSUInteger destinationWidth =
        std::max<NSUInteger>(1, dst.width >> destinationLevel);
    const NSUInteger destinationHeight =
        std::max<NSUInteger>(1, dst.height >> destinationLevel);
    const bool explicitRegion = sourceWidth != 0 && sourceHeight != 0;
    sourceWidth = sourceWidth ? sourceWidth : src.width;
    sourceHeight = sourceHeight ? sourceHeight : src.height;
    const NSUInteger outputWidth =
        explicitRegion ? std::min(destinationRegionWidth ? destinationRegionWidth : sourceWidth,
                                  destinationWidth - destinationX)
                       : destinationWidth - destinationX;
    const NSUInteger outputHeight =
        explicitRegion ? std::min(destinationRegionHeight ? destinationRegionHeight : sourceHeight,
                                  destinationHeight - destinationY)
                       : destinationHeight - destinationY;
    const bool fullDestination = destinationX == 0 && destinationY == 0 &&
                                 outputWidth == destinationWidth &&
                                 outputHeight == destinationHeight;
    rp.colorAttachments[0].loadAction =
        fullDestination ? MTLLoadActionDontCare : MTLLoadActionLoad;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    auto e = RenderEncoder(rp,present?"present-copy":"resolve-color");
    auto pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [helpers_ newFunctionWithName:@"copyVertex"];
    pd.fragmentFunction = [helpers_ newFunctionWithName:@"copyFragment"];
    pd.colorAttachments[0].pixelFormat = dst.pixelFormat;
    uint64_t key = 0xC000000000000000ull | dst.pixelFormat;
    auto p = pipelines_[key];
    if (!p) {
      p = [device_ newRenderPipelineStateWithDescriptor:pd error:nil];
      pipelines_[key] = p;
    }
    [e setRenderPipelineState:p];
    [e setFragmentTexture:src atIndex:0];
    float parameters[8] = {
        scale, float(sourceX) / src.width, float(sourceY) / src.height, 0.f,
        float(sourceWidth) / src.width, float(sourceHeight) / src.height, 0.f,
        0.f};
    // A/B only: emulate the old full-source UV behavior while retaining the
    // requested destination mip and rectangle. Never applied to presentation.
    if (!present && ProbeMode(@"full-source-color-uv")) {
      parameters[1] = parameters[2] = 0;
      parameters[4] = parameters[5] = 1;
      ++probeOverrides_;
    }
    [e setFragmentBytes:parameters length:sizeof(parameters) atIndex:0];
    const MTLViewport viewport = {double(destinationX), double(destinationY),
                                  double(outputWidth), double(outputHeight),
                                  0.0, 1.0};
    [e setViewport:viewport];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [e endEncoding];
    return true;
  }
#if MCLA_SMAA_LAB
  id<MTLTexture> ApplySmaa(id<MTLTexture> source) {
    if (!smaaEnabled_ || !source || !smaa_ || !smaaArea_ || !smaaSearch_)
      return nil;
    EndEncoder();
    if (!Begin()) return nil;
    auto &targets = smaaTargets_[slot_];
    const MTLPixelFormat formats[3] = {
        MTLPixelFormatRG8Unorm, MTLPixelFormatRGBA8Unorm,
        MTLPixelFormatRGBA16Float};
    for (unsigned pass = 0; pass < 3; ++pass) {
      if (!targets[pass] || targets[pass].width != source.width ||
          targets[pass].height != source.height) {
        auto descriptor = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:formats[pass]
                                        width:source.width height:source.height mipmapped:NO];
        descriptor.storageMode = MTLStorageModePrivate;
        descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        targets[pass] = [device_ newTextureWithDescriptor:descriptor];
      }
      if (!targets[pass]) {
        REXLOG_ERROR("MCLA SMAA Lab: target allocation failed pass={}", pass);
        return nil;
      }
      if (!smaaPipelines_[pass]) {
        auto descriptor = [MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction = [helpers_ newFunctionWithName:@"copyVertex"];
        descriptor.fragmentFunction = [smaa_ newFunctionWithName:
            pass == 0 ? @"mclaSmaaEdge" :
            pass == 1 ? @"mclaSmaaWeight" : @"mclaSmaaNeighborhood"];
        descriptor.colorAttachments[0].pixelFormat = formats[pass];
        NSError *error = nil;
        smaaPipelines_[pass] = [device_ newRenderPipelineStateWithDescriptor:descriptor
                                                                       error:&error];
        if (!smaaPipelines_[pass]) {
          REXLOG_ERROR("MCLA SMAA Lab: pipeline {} failed: {}", pass,
              error.localizedDescription.UTF8String);
          return nil;
        }
      }
      auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
      rp.colorAttachments[0].texture = targets[pass];
      rp.colorAttachments[0].loadAction = MTLLoadActionClear;
      rp.colorAttachments[0].storeAction = MTLStoreActionStore;
      auto encoder = RenderEncoder(rp,"smaa-lab");
      if (!encoder) return nil;
      [encoder setRenderPipelineState:smaaPipelines_[pass]];
      const float metrics[4] = {1.f / source.width, 1.f / source.height,
                                float(source.width), float(source.height)};
      [encoder setFragmentBytes:metrics length:sizeof(metrics) atIndex:0];
      if (pass == 0) {
        [encoder setFragmentTexture:source atIndex:0];
        [encoder setFragmentSamplerState:smaaPoint_ atIndex:0];
      } else if (pass == 1) {
        [encoder setFragmentTexture:targets[0] atIndex:0];
        [encoder setFragmentTexture:smaaArea_ atIndex:1];
        [encoder setFragmentTexture:smaaSearch_ atIndex:2];
        [encoder setFragmentSamplerState:smaaLinear_ atIndex:0];
        [encoder setFragmentSamplerState:smaaLinear_ atIndex:1];
        [encoder setFragmentSamplerState:smaaPoint_ atIndex:2];
      } else {
        [encoder setFragmentTexture:source atIndex:0];
        [encoder setFragmentTexture:targets[1] atIndex:1];
        [encoder setFragmentSamplerState:smaaLinear_ atIndex:0];
        [encoder setFragmentSamplerState:smaaLinear_ atIndex:1];
      }
      [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [encoder endEncoding];
    }
    if (++smaaFrames_ == 1 || smaaFrames_ % 300 == 0)
      REXLOG_INFO("MCLA SMAA Lab ACTIVE frame={} input={}x{} passes=3 quality=high fsr={}",
          smaaFrames_, source.width, source.height, MCLAGraphicsFSREnabled());
    return targets[2];
  }
#endif
  id<MTLRenderPipelineState> FsrPipeline(unsigned pass, MTLPixelFormat format) {
    const uint64_t key=0xF000000000000000ull|(uint64_t(pass)<<32)|format;
    if(auto pipeline=pipelines_[key])return pipeline;
    auto pd=[MTLRenderPipelineDescriptor new];
    pd.vertexFunction=[helpers_ newFunctionWithName:@"copyVertex"];
    pd.fragmentFunction=[fsr_ newFunctionWithName:pass?@"mclaFsrRcas":@"mclaFsrEasu"];
    pd.colorAttachments[0].pixelFormat=format;
    NSError* error=nil;
    auto pipeline=[device_ newRenderPipelineStateWithDescriptor:pd error:&error];
    if(!pipeline)REXLOG_ERROR("MCLA FSR pipeline: {}",error.localizedDescription.UTF8String);
    else pipelines_[key]=pipeline;
    return pipeline;
  }
  bool Upscale(id<MTLTexture> src,id<MTLTexture> dst) {
    EndEncoder();if(!Begin() || !fsr_)return Fail("fsr-unavailable");
    auto& intermediate=fsrTargets_[slot_];
    if(!intermediate || intermediate.width!=dst.width || intermediate.height!=dst.height){
      auto td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:dst.width height:dst.height mipmapped:NO];
      td.storageMode=MTLStorageModePrivate;
      td.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
      intermediate=[device_ newTextureWithDescriptor:td];
    }
    if(!intermediate)return Fail("fsr-target");
    for(unsigned pass=0;pass<2;++pass){
      id<MTLTexture> input=pass?intermediate:src,output=pass?dst:intermediate;
      auto pipeline=FsrPipeline(pass,output.pixelFormat);
      if(!pipeline)return Fail("fsr-pipeline");
      auto rp=[MTLRenderPassDescriptor renderPassDescriptor];
      rp.colorAttachments[0].texture=output;
      rp.colorAttachments[0].loadAction=MTLLoadActionDontCare;
      rp.colorAttachments[0].storeAction=MTLStoreActionStore;
      auto e=RenderEncoder(rp,pass?"fsr-rcas":"fsr-easu");
      [e setRenderPipelineState:pipeline];[e setFragmentTexture:input atIndex:0];
      [e setFragmentSamplerState:fsrSampler_ atIndex:0];
      // Reference push-constant ABI starts at byte 16 (vertex reserved range).
      float constants[8]={0,0,0,0,float(src.width)/dst.width,float(src.height)/dst.height,1.f/src.width,1.f/src.height};
      // RCAS strength is exp2(-sharpnessReduction). The former 0.2 setting
      // was strong enough to turn MCLA's authored low-frequency shading and
      // mip transitions into coarse blocks. The 0.65 test removed much of
      // that harshness but was slightly soft, so retain moderate reconstruction
      // clarity without returning to the original pixel-art appearance.
      if(pass){constants[4]=constants[5]=0;constants[6]=std::exp2(-0.50f);constants[7]=0;}
      [e setFragmentBytes:constants length:sizeof(constants) atIndex:0];
      [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [e endEncoding];
    }
    return true;
  }
  bool Resolve(const ng::ResolveCommand &c) {
    bool depth = (c.flags & 7) == 4;
    auto source = ResolveSource(c.source, depth);
    if (!source)
      return Fail("resolve-source");
    xn::xe_gpu_texture_fetch_t f{};
    memcpy(&f, c.destination_fetch, 24);
    gx::TextureInfo info{};
    if (!gx::TextureInfo::Prepare(f, &info))
      return Fail("resolve-fetch");
    const uint32_t destinationFormat =
        uint32_t(gx::GetBaseFormat(info.format));
    auto pf = ResolveFormat(destinationFormat);
    if (pf == MTLPixelFormatInvalid) {
      if (++invalidResolveFormats_[destinationFormat] <= 3) {
        REXLOG_ERROR(
            "MCLA METAL unsupported resolve destination format={} raw="
            "{:08X},{:08X},{:08X},{:08X},{:08X},{:08X} size={}x{}",
            destinationFormat, c.destination_fetch[0],
            c.destination_fetch[1], c.destination_fetch[2],
            c.destination_fetch[3], c.destination_fetch[4],
            c.destination_fetch[5], info.width + 1, info.height + 1);
      }
      return Fail("resolve-format");
    }
    EndEncoder();
    Begin();
    InvalidateSourceTexture(c.destination_texture);
    auto &t = textures_[c.destination_texture];
    const bool cube = info.dimension == xn::DataDimension::kCube;
    const bool volume = info.dimension == xn::DataDimension::k3D;
    const NSUInteger layers = cube ? 6 : info.is_stacked ? info.depth + 1 : 1;
    const NSUInteger mipCount = info.mip_max_level + 1;
    const MTLTextureType textureType =
        cube ? MTLTextureTypeCube
             : volume ? MTLTextureType3D
                      : layers > 1 ? MTLTextureType2DArray : MTLTextureType2D;
    uint32_t guestWidth, guestHeight;
    MCLAGraphicsGuestVideoSize(&guestWidth, &guestHeight);
    const auto extent = textureType == MTLTextureType2D
        ? mcla::metal::SceneExtent(info.width+1, info.height+1, MCLAGraphicsRenderHeight(), guestWidth, guestHeight)
        : mcla::metal::OutputSize{info.width+1,info.height+1};
    if (!t.produced || !t.image || t.image.width != extent.width ||
        t.image.height != extent.height || t.image.pixelFormat != pf ||
        t.image.mipmapLevelCount != mipCount ||
        t.image.textureType != textureType ||
        (!volume && t.image.arrayLength != (cube ? 1 : layers))) {
      auto td = [MTLTextureDescriptor
          texture2DDescriptorWithPixelFormat:pf
                                       width:extent.width
                                      height:extent.height
                                   mipmapped:mipCount > 1];
      td.mipmapLevelCount = mipCount;
      td.storageMode = MTLStorageModePrivate;
      td.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget |
                 MTLTextureUsagePixelFormatView;
      td.textureType = textureType;
      if (volume)
        td.depth = info.depth + 1;
      else if (textureType == MTLTextureType2DArray)
        td.arrayLength = layers;
      t.image = [device_ newTextureWithDescriptor:td];
      t.produced = true;
      t.sceneFlags = textureType == MTLTextureType2D
          ? mcla::metal::SceneTextureFlags(info.width+1, info.height+1, MCLAGraphicsRenderHeight(), guestWidth, guestHeight) : 0;
      t.touchedMips = 0;
      if (renderProbe_ && frames_ == passCaptureFrame_)
        REXLOG_INFO("MCLA METAL PROBE allocation handle={:08X} size={}x{} mips={} format={}",
            c.destination_texture, info.width + 1, info.height + 1, mipCount, destinationFormat);
    }
    memcpy(t.fetch.data(), &f, 24);
    if (!t.image)
      return Fail("resolve-destination");
    if (c.destination_level >= t.image.mipmapLevelCount)
      return Fail("resolve-destination-level");
    const NSUInteger destinationDepth =
        volume ? std::max<NSUInteger>(1, t.image.depth >> c.destination_level)
               : cube ? 6 : t.image.arrayLength;
    if (c.destination_slice_or_face >= destinationDepth)
      return Fail("resolve-destination-slice");
    const NSUInteger destinationLevel = c.destination_level;
    const NSUInteger destinationSlice = c.destination_slice_or_face;
    const NSUInteger destinationWidth =
        std::max<NSUInteger>(1, t.image.width >> destinationLevel);
    const NSUInteger destinationHeight =
        std::max<NSUInteger>(1, t.image.height >> destinationLevel);
    const unsigned guestSX = c.source_rectangle_valid
                            ? std::max(0, c.source_rectangle.left)
                            : 0,
                   guestSY = c.source_rectangle_valid
                            ? std::max(0, c.source_rectangle.top)
                            : 0;
    const unsigned guestDX = c.destination_point_valid
                            ? std::max(0, c.destination_point.x)
                            : 0,
                   guestDY = c.destination_point_valid
                            ? std::max(0, c.destination_point.y)
                            : 0;
    const auto horizontal = mcla::metal::ScaleResolveSpan(c.source.width, uint32_t(source.width),
        std::max(1u,(info.width+1)>>destinationLevel), uint32_t(destinationWidth), guestSX, guestDX,
        c.source_rectangle_valid ? unsigned(std::max(0,c.source_rectangle.right-int(guestSX))) : UINT32_MAX);
    const auto vertical = mcla::metal::ScaleResolveSpan(c.source.height, uint32_t(source.height),
        std::max(1u,(info.height+1)>>destinationLevel), uint32_t(destinationHeight), guestSY, guestDY,
        c.source_rectangle_valid ? unsigned(std::max(0,c.source_rectangle.bottom-int(guestSY))) : UINT32_MAX);
    const auto sx=horizontal.source, sy=vertical.source,
               dx=horizontal.destination, dy=vertical.destination,
               copyWidth=horizontal.sourceSize, copyHeight=vertical.sourceSize,
               writeWidth=horizontal.destinationSize, writeHeight=vertical.destinationSize;
    if (!copyWidth || !copyHeight || !writeWidth || !writeHeight)
      return Fail("resolve-empty-region");
    if (source.pixelFormat == t.image.pixelFormat && copyWidth == writeWidth &&
        copyHeight == writeHeight &&
        (depth || ng::NativeResolveExponent(c.flags) == 0)) {
      auto e = BlitEncoder("resolve-blit");
      [e copyFromTexture:source
                sourceSlice:0
                sourceLevel:0
               sourceOrigin:MTLOriginMake(sx, sy, 0)
                 sourceSize:MTLSizeMake(copyWidth, copyHeight, 1)
                  toTexture:t.image
           destinationSlice:volume ? 0 : destinationSlice
           destinationLevel:destinationLevel
          destinationOrigin:MTLOriginMake(dx, dy,
                                          volume ? destinationSlice : 0)];
      [e endEncoding];
    } else if (!depth) {
      if (!CopyColor(source, t.image, false,
                ng::NativePowerOfTwo(ng::NativeResolveExponent(c.flags)),
                destinationLevel, destinationSlice, sx, sy, copyWidth,
                copyHeight, dx, dy, writeWidth, writeHeight)) return false;
    }
    else {
      auto stencil =
          [source newTextureViewWithPixelFormat:MTLPixelFormatX32_Stencil8];
      auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
      rp.colorAttachments[0].texture = t.image;
      rp.colorAttachments[0].level = destinationLevel;
      if (volume)
        rp.colorAttachments[0].depthPlane = destinationSlice;
      else
        rp.colorAttachments[0].slice = destinationSlice;
      // Packed depth is a color product, but it must obey the same partial
      // resolve contract as a direct depth blit. Retain other atlas tiles.
      const bool fullDestination = dx == 0 && dy == 0 &&
                                   writeWidth == destinationWidth &&
                                   writeHeight == destinationHeight;
      rp.colorAttachments[0].loadAction =
          fullDestination ? MTLLoadActionDontCare : MTLLoadActionLoad;
      rp.colorAttachments[0].storeAction = MTLStoreActionStore;
      auto pd = [MTLRenderPipelineDescriptor new];
      pd.vertexFunction = [helpers_ newFunctionWithName:@"copyVertex"];
      pd.fragmentFunction = [helpers_ newFunctionWithName:@"packDepth"];
      pd.colorAttachments[0].pixelFormat = t.image.pixelFormat;
      uint64_t key = 0xD000000000000000ull | t.image.pixelFormat;
      auto pipeline = pipelines_[key];
      if (!pipeline) {
        NSError *error = nil;
        pipeline = [device_ newRenderPipelineStateWithDescriptor:pd
                                                           error:&error];
        pipelines_[key] = pipeline;
        if (!pipeline)
          return Fail("depth-pack-pipeline");
      }
      auto e = RenderEncoder(rp,"resolve-depth");
      [e setRenderPipelineState:pipeline];
      [e setFragmentTexture:source atIndex:0];
      [e setFragmentTexture:stencil atIndex:1];
      uint32_t parameters[] = {(c.source.format & 63) == 23,
                               uint32_t(f.swizzle), sx, sy, dx, dy,
                               copyWidth, copyHeight, writeWidth, writeHeight};
      [e setFragmentBytes:parameters length:sizeof(parameters) atIndex:0];
      const MTLViewport viewport = {double(dx), double(dy), double(writeWidth),
                                    double(writeHeight), 0.0, 1.0};
      [e setViewport:viewport];
      [e setScissorRect:MTLScissorRect{dx, dy, writeWidth, writeHeight}];
      [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [e endEncoding];
    }
    if (destinationLevel < 64) t.touchedMips |= uint64_t(1) << destinationLevel;
    if (c.flags & 0x300) {
      ng::ClearCommand clear;
      clear.device = c.device;
      clear.flags = (c.flags & 0x100 ? 1u << (c.flags & 3) : 0) |
                    (c.flags & 0x200 ? 48 : 0);
      // D3DDevice_Resolve clears only the resolved source rectangle. Dropping
      // this rectangle turns tile/post-process clears into full-surface
      // clears, erasing the scene snapshot used behind modal UI and any
      // intermediate translucent content outside the resolved region.
      if (c.source_rectangle_valid) {
        clear.left = c.source_rectangle.left;
        clear.top = c.source_rectangle.top;
        clear.right = c.source_rectangle.right;
        clear.bottom = c.source_rectangle.bottom;
      } else {
        clear.right = int32_t(c.source.width);
        clear.bottom = int32_t(c.source.height);
      }
      memcpy(clear.color_bits, c.clear_color_bits, 16);
      clear.depth_bits = c.clear_depth_bits;
      clear.stencil = c.clear_stencil;
      Clear(clear);
    }
    ++resolves_;
    return true;
  }
  bool Present(const ng::PresentCommand &c) {
    // Snapshot once: a UIKit toggle cannot split a frame between modes.
    frameFSREnabled_=MCLAGraphicsFSREnabled();
    const double presentStart = CACurrentMediaTime();
    const auto nativeTiming = MCLANativeTakeFrameTiming();
    const bool performanceCaptureActive =
        MCLAGraphicsPerformanceCaptureRemainingSeconds() > 0.0;
    profile_ = baseProfile_ || performanceCaptureActive;
    if (performanceCaptureActive != performanceCaptureWasActive_) {
      REXLOG_INFO("MCLA METAL bounded performance capture {} frame={} scene_height={} fsr={}",
          performanceCaptureActive ? "started" : "ended", frames_,
          MCLAGraphicsRenderHeight(), MCLAGraphicsFSREnabled());
      performanceCaptureWasActive_ = performanceCaptureActive;
    }
    if(profile_ && frames_%120==0 && profileSamples_){
      REXLOG_INFO("MCLA METAL CPU sample={} us_per_draw state={:.2f} pipeline={:.2f} dynamic={:.2f} vertices={:.2f} bindings={:.2f} indices={:.2f}",profileSamples_,profileMS_[0]*1000/profileSamples_,profileMS_[1]*1000/profileSamples_,profileMS_[2]*1000/profileSamples_,profileMS_[3]*1000/profileSamples_,profileMS_[4]*1000/profileSamples_,profileMS_[5]*1000/profileSamples_);
      REXLOG_INFO("MCLA METAL BIND CPU constants_us={:.2f} textures_us={:.2f} encode_us={:.2f} decoded_textures={}",profileMS_[6]*1000/profileSamples_,profileMS_[7]*1000/profileSamples_,profileMS_[8]*1000/profileSamples_,decodedTextures_);
      profileMS_={};profileSamples_=0;
    }
    if (!Begin())
      return false;
    EndEncoder();
    xn::xe_gpu_texture_fetch_t f{};
    memcpy(&f, c.frontbuffer_fetch, 24);
    auto source = TextureFor(c.frontbuffer_texture, f);
    if (renderProbe_ && frames_ == passCaptureFrame_) {
      CapturePass(source, "present", 0);
      if (ProbeMode(@"pixel-history")) {
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/mcla-pass-capture"];
        [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
        pixelHistory_.Finish(commands_, [root stringByAppendingPathComponent:
            [NSString stringWithFormat:@"pixel-history-%llu-f%llu",
                (unsigned long long)probeToken_, (unsigned long long)frames_]],
            probeToken_, frames_);
      }
      REXLOG_INFO("MCLA METAL PROBE capture_submitted mode={} token={} frame={} overrides={} images={}",
          probeMode_.UTF8String, probeToken_, frames_, probeOverrides_, passCaptureCount_);
    }
    const double drawableStart = CACurrentMediaTime();
    auto drawable = [layer_ nextDrawable];
    const double drawableWaitMS = (CACurrentMediaTime() - drawableStart) * 1000;
    id<MTLTexture> presentSource = source;
#if MCLA_SMAA_LAB
    if (drawable && source && smaaEnabled_) {
      if (auto smoothed = ApplySmaa(source)) presentSource = smoothed;
      else REXLOG_ERROR("MCLA SMAA Lab: frame={} fell back to unfiltered source", frames_);
    }
#endif
    const bool outputReady=drawable && presentSource && CopyColor(presentSource,drawable.texture,true);
    if (outputReady && (frames_ == 0 || frames_ % 300 == 0))
      REXLOG_INFO("MCLA METAL present scene={}x{} selected_height={} fsr={} output={}x{} flights={}",
          source.width,source.height,MCLAGraphicsRenderHeight(),MCLAGraphicsFSREnabled(),
          drawable.texture.width,drawable.texture.height,kFlights);
    if (outputReady) {
      auto timing=displayTiming_;
      const uint64_t presentedFrame = frames_ + 1;
      if (mcla::DiagnosticsEnabled()) [drawable addPresentedHandler:^(id<MTLDrawable> shown){
        const double time=shown.presentedTime;
        if(time>0){
          MCLAGraphicsNoteDisplayPresentation(time);
          if (performanceCaptureActive)
            MCLAGraphicsNotePerformancePresented(presentedFrame,time);
          std::lock_guard lock(timing->mutex);
          if(timing->times.size()<1024)timing->times.push_back(time);
        }
      }];
      [commands_ presentDrawable:drawable atTime:presentationClock_.Plan(CACurrentMediaTime(), MCLAGraphicsFrameRate())];
    }
    const uint64_t frame = ++frames_, draws = draws_, failed = failed_,
                   resolves = resolves_;
    // Command buffers retain resources via useResource; the CPU-side fast
    // bindings need not pin the previous frame's streamed textures.
    for (auto& binding : textureBindings_) binding.image = nil;
    MCLAPerformanceFrame sample{};
    if (performanceCaptureActive) {
      const uint64_t complete = completed_.load();
      sample = MCLAPerformanceFrame{
          frame, draws, failed, resolves, textureChecks_, staleTextures_,
          decodedTextures_, surfaces_.size(),
          textures_.size() + sourceTextures_.size(), buffers_.size(),
          gpuErrors_.load(), MCLAVirtualGamepadButtonEdgeCount(),
          uint32_t(frame > complete ? frame - complete : 0),
          source ? uint32_t(source.width) : 0u,
          source ? uint32_t(source.height) : 0u,
          drawable ? uint32_t(drawable.texture.width) : 0u,
          drawable ? uint32_t(drawable.texture.height) : 0u,
          0};
      sample.submissionThreadWallMilliseconds=submissionThreadWallMS_;
      sample.submissionThreadCPUMilliseconds=submissionThreadCPUMS_;
      sample.drawProfileSamples=frameProfileSamples_;
      for(unsigned section=0;section<9;++section) {
        sample.drawStageWallMicroseconds[section]=frameProfileSamples_
            ? float(frameProfileWallMS_[section]*1000/frameProfileSamples_):-1;
        sample.drawStageCPUMicroseconds[section]=frameProfileSamples_
            ? float(frameProfileCPUMS_[section]*1000/frameProfileSamples_):-1;
      }
    }
    frameProfileWallMS_={};frameProfileCPUMS_={};frameProfileSamples_=0;
    draws_ = resolves_ = 0;
    MaintainResourceCaches(frame);
    if (mcla::DiagnosticsEnabled() && (frame % 120) == 0) {
      size_t uploadBytes = 0;
      for (const auto &flight : flights_)
        for (const auto &block : flight.blocks)
          uploadBytes += block.length;
      REXLOG_INFO(
          "MCLA METAL CACHE frame={} textures={} surfaces={} buffers={} "
          "source_textures={} texture_handles={} buffer_aliases={} "
          "index_buffers={} index_aliases={} "
          "upload_mib={:.1f} "
          "texture_checks={} stale_texture_refreshes={} "
          "gamma_bindings={} resolve_shape_fallbacks={} "
          "evicted_textures={} evicted_buffers={} evicted_index_buffers={} "
          "binding_hits={} binding_lookups={} resource_declarations={} "
          "resource_declaration_skips={} constant_register_uploads={}",
          frame, textures_.size() + sourceTextures_.size(), surfaces_.size(),
          buffers_.size(), sourceTextures_.size(),
          sourceTextureIndex_.AliasCount(), bufferIndex_.AliasCount(),
          indexBuffers_.size(), indexBufferIndex_.AliasCount(),
          double(uploadBytes) / (1024.0 * 1024.0), textureChecks_, staleTextures_,
          gammaBindings_, resolveShapeFallbacks_, evictionsSinceLog_[0], evictionsSinceLog_[1],
          evictionsSinceLog_[2], textureBindingHits_, textureBindingLookups_,
          resourceDeclarations_, resourceDeclarationSkips_,
          constantRegistersUploaded_);
      textureBindingHits_ = textureBindingLookups_ = 0;
      resourceDeclarations_ = resourceDeclarationSkips_ = 0;
      constantRegistersUploaded_ = 0;
      evictionsSinceLog_ = {};
    }
    if (capture_ && frame == 900 && source) {
      auto read = Allocate(source.width * source.height * 8);
      auto e = BlitEncoder("frame-readback");
      [e copyFromTexture:source
                       sourceSlice:0
                       sourceLevel:0
                      sourceOrigin:MTLOriginMake(0, 0, 0)
                        sourceSize:MTLSizeMake(source.width, source.height, 1)
                          toBuffer:read.buffer
                 destinationOffset:read.offset
            destinationBytesPerRow:source.width * PixelBytes(source.pixelFormat)
          destinationBytesPerImage:source.width * source.height *
                                   PixelBytes(source.pixelFormat)];
      [e endEncoding];
      NSString *path = [NSHomeDirectory()
          stringByAppendingPathComponent:@"Documents/mcla-metal-frame.bin"];
      size_t n = source.width * source.height * PixelBytes(source.pixelFormat);
      [commands_ addCompletedHandler:^(id<MTLCommandBuffer> cb) {
        if (cb.status == MTLCommandBufferStatusCompleted)
          [[NSData dataWithBytes:read.cpu length:n] writeToFile:path
                                                     atomically:YES];
      }];
    }
    auto semaphore = flights_[slot_].available;
    auto self = this;
    auto presented = outputReady;
    // A shared timestamp is filled immediately before commit, after handler
    // registration. Captured by value, it outlives this CPU stack frame.
    auto commitTime = std::make_shared<double>(0);
    auto passTrace=gpuPassTrace_;
    [commands_ addCompletedHandler:^(id<MTLCommandBuffer> cb) {
      self->completed_.fetch_add(1);
      if (cb.status == MTLCommandBufferStatusError) {
        self->gpuErrors_.fetch_add(1);
        REXLOG_ERROR("MCLA METAL GPU error: {}",
                     cb.error.localizedDescription.UTF8String);
      }
      MCLAGraphicsNoteMetalCompletion(presented && cb.status == MTLCommandBufferStatusCompleted);
      if (mcla::DiagnosticsEnabled()) {
      std::lock_guard lock(self->timingMutex_);
      double now = CACurrentMediaTime();
      if (presented)
        self->presentTimes_.push_back(now);
      const double gpuMilliseconds =
          (cb.GPUEndTime - cb.GPUStartTime) * 1000;
      if (performanceCaptureActive)
        MCLAGraphicsNotePerformanceGPU(frame, cb.GPUStartTime > 0 ? gpuMilliseconds : -1,
            cb.GPUStartTime > 0 ? (cb.GPUStartTime - *commitTime) * 1000 : -1,
            cb.kernelStartTime > 0 ? (cb.kernelEndTime - cb.kernelStartTime) * 1000 : -1);
      MCLAGraphicsNoteGPUTime(gpuMilliseconds);
      self->gpuMS_.push_back(gpuMilliseconds);
      if (mcla::DiagnosticsEnabled() && frame % 120 == 0) {
        double seconds =
            self->presentTimes_.size() > 1
                ? self->presentTimes_.back() - self->presentTimes_.front()
                : 0;
        double fps =
            seconds > 0 ? (self->presentTimes_.size() - 1) / seconds : 0;
        double sum = 0;
        for (auto t : self->gpuMS_)
          sum += t;
        REXLOG_INFO("MCLA METAL frame={} draws={} failed_total={} resolves={} "
                    "completed_fps={:.2f} gpu_ms={:.2f} flight_slots=3 "
                    "gpu_errors={} capture={}",
                    frame, draws, failed, resolves, fps,
                    sum / std::max(size_t(1), self->gpuMS_.size()),
                    self->gpuErrors_.load(), self->capture_);
        {std::lock_guard displayLock(self->displayTiming_->mutex);
          auto& times=self->displayTiming_->times;
          if(times.size()>2){std::vector<double> intervals;for(size_t i=1;i<times.size();++i)intervals.push_back((times[i]-times[i-1])*1000);std::sort(intervals.begin(),intervals.end());
            const double seconds=times.back()-times.front();
            REXLOG_INFO("MCLA METAL DISPLAY frame={} samples={} fps={:.2f} median_ms={:.2f} p95_ms={:.2f} capture={} release=1 slots=3",frame,times.size(),(times.size()-1)/seconds,intervals[intervals.size()/2],intervals[size_t((intervals.size()-1)*.95)],self->capture_);
          }times.clear();}
        self->presentTimes_.clear();
        self->gpuMS_.clear();
      }
      }
      if(passTrace) {
        auto rows=passTrace->Resolve(cb.device,cb.status==MTLCommandBufferStatusCompleted);
        MCLAGraphicsNoteGPUPasses(rows.data(),uint32_t(rows.size()));
      }
      dispatch_semaphore_signal(semaphore);
    }];
    *commitTime = CACurrentMediaTime();
    if (performanceCaptureActive) {
      sample.submitMilliseconds = lastPresentSubmitTime_ > 0 ?
          (*commitTime - lastPresentSubmitTime_) * 1000 : 0;
      sample.rendererMilliseconds = frameCommandMS_;
      sample.nativeDrawMilliseconds = nativeTiming.drawMilliseconds;
      sample.presentMilliseconds = (*commitTime - presentStart) * 1000;
      sample.drawableWaitMilliseconds = drawableWaitMS;
      sample.slotWaitMilliseconds = frameSlotWaitMS_;
      sample.previousPacingMilliseconds = nativeTiming.previousPacingMilliseconds;
      sample.constantBankUploads = constantBankUploads_;
      sample.constantBankReuses = constantBankReuses_;
      sample.uploadBytes = frameUploadBytes_;
      sample.cacheMaintenanceMilliseconds = frameCacheMaintenanceMS_;
      sample.resourceInvalidationMilliseconds = frameInvalidationMS_;
      sample.cacheEvictions = frameCacheEvictions_;
      sample.invalidationCalls = frameInvalidationCalls_;
      sample.invalidatedKeys = frameInvalidatedKeys_;
      sample.aliasRemovals = frameAliasRemovals_;
      sample.oldestCacheAgeFrames = std::max({sourceTextureIndex_.OldestAge(frame),
          bufferIndex_.OldestAge(frame),indexBufferIndex_.OldestAge(frame)});
      sample.attachmentReuses=attachmentReuses_;sample.pipelineReuses=pipelineReuses_;
      sample.vertexReuses=vertexReuses_;sample.indexReuses=indexReuses_;
      sample.textureGroupReuses=textureGroupReuses_;sample.vertexBindSkips=vertexBindSkips_;
      sample.gpuPassTraceStatus=passTrace?passTrace->status:gpuPassTraceStatus_;
      sample.fsrEnabled=frameFSREnabled_;
      MCLAGraphicsNotePerformanceFrame(&sample);
    }
    if (mcla::DiagnosticsEnabled() && frame % 120 == 0) {
      REXLOG_INFO("MCLA METAL texture_fallbacks={} texture_failure_reasons={}",
          textureFallbacks_,textureFailureReasons_.size());
      REXLOG_INFO("MCLA METAL geometry_scratch={} vertex_conversions={} vertex_scratch_growths={} index_scratch_growths={} scratch_retained_bytes={}",
          reuseGeometryScratch_,vertexScratch_.uses(),vertexScratch_.growths(),
          indexScratch_.growths()+expandedIndexScratch_.growths(),
          vertexScratch_.capacity()+sizeof(uint32_t)*(indexScratch_.capacity()+expandedIndexScratch_.capacity()));
      REXLOG_INFO("MCLA METAL shared_uploads={} shared_reuses={} push_calls={} push_skips={}",
          sharedConstantUploads_,sharedConstantReuses_,pushAddressCalls_,pushAddressSkips_);
      REXLOG_INFO("MCLA METAL dynamic_state_calls={} dynamic_state_skips={} depth_lookup_reuses={}",
          dynamicStateCalls_,dynamicStateSkips_,depthLookupReuses_);
      REXLOG_INFO("MCLA METAL thermal={} low_power={} constant_uploads={} constant_reuses={}",
          int(NSProcessInfo.processInfo.thermalState),
          bool(NSProcessInfo.processInfo.lowPowerModeEnabled),
          constantBankUploads_,constantBankReuses_);
    }
    lastPresentSubmitTime_ = *commitTime;
    frameCommandMS_ = frameSlotWaitMS_ = 0;
    submissionThreadWallMS_=submissionThreadCPUMS_=-1;
    frameUploadBytes_ = 0;
    frameCacheMaintenanceMS_ = frameInvalidationMS_ = 0;
    frameCacheEvictions_ = frameInvalidationCalls_ = frameInvalidatedKeys_ = frameAliasRemovals_ = 0;
    MCLAGraphicsNoteMetalSubmission();
    // Work already in flight may be rejected during a transition. Stop new
    // commits until UIKit resumes the app, without spinning the guest thread.
    if (!MCLAGraphicsWaitForApplicationActive()) return false;
    [commands_ commit];
    commands_ = nil;
    slot_ = (slot_ + 1) % kFlights;
    PollRenderProbe();
    return presented;
  }

public:
  ~MetalRenderer() override { Shutdown(); }
  rex::X_STATUS SetupPresentation(rex::ui::WindowedAppContext *) override {
    return 0;
  }
  bool has_presentation() const override { return layer_ != nil; }
  rex::X_STATUS SetupGuestGpu(rex::runtime::FunctionDispatcher *d,
                              rex::system::KernelState *) override {
    memory_ = d->memory();
    layer_ = (__bridge CAMetalLayer *)MCLAGraphicsBoundMetalLayer();
    device_ = layer_.device;
    queue_ = [device_ newCommandQueue];
    gpuCountersSupported_=[device_ supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary];
    if (!device_ || !queue_)
      return 0xC0000001;
    if (const char* plan=std::getenv("MCLA_METAL_VERTEX_FIXUP_PLAN"))
      planVertexFixups_=std::strcmp(plan,"0")!=0;
    capture_ = mcla::DiagnosticsEnabled() && std::getenv("MCLA_METAL_CAPTURE") != nullptr;
    baseProfile_ = mcla::DiagnosticsEnabled() && std::getenv("MCLA_METAL_PROFILE") != nullptr;
    profile_ = baseProfile_;
    if (const char* reuse = std::getenv("MCLA_METAL_DRAW_STATE_REUSE"))
      optimizeDrawState_ = std::strcmp(reuse,"0") != 0;
    if (const char* reuse = std::getenv("MCLA_METAL_GEOMETRY_SCRATCH"))
      reuseGeometryScratch_ = std::strcmp(reuse,"0") != 0;
    if (const char* reuse = std::getenv("MCLA_METAL_BINDING_REUSE"))
      optimizeBindings_ = std::strcmp(reuse,"0") != 0;
    REXLOG_INFO("MCLA METAL draw_state_reuse={} binding_reuse={}",
        optimizeDrawState_,optimizeBindings_);
    renderProbe_ = mcla::DiagnosticsEnabled() && std::getenv("MCLA_METAL_RENDER_PROBE") != nullptr;
    if (renderProbe_) {
      auto td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
          width:1 height:1 mipmapped:NO];
      td.storageMode = MTLStorageModeShared;
      probeNeutralCollector_ = [device_ newTextureWithDescriptor:td];
      // xCityGrime doubles collector green, so .5 is neutral, not white.
      const uint16_t neutral[] = {0x3800, 0x3800, 0x3800, 0x3C00};
      [probeNeutralCollector_ replaceRegion:MTLRegionMake2D(0,0,1,1)
          mipmapLevel:0 withBytes:neutral bytesPerRow:sizeof(neutral)];
      auto sampler = [MTLSamplerDescriptor new];
      sampler.supportArgumentBuffers = YES;
      sampler.sAddressMode = sampler.tAddressMode = sampler.rAddressMode = MTLSamplerAddressModeClampToEdge;
      probeNeutralSampler_ = [device_ newSamplerStateWithDescriptor:sampler];
      REXLOG_INFO("MCLA METAL PROBE enabled revision=resolve-shadow-ab-v1; default=baseline; no persisted renderer override");
    }
    if (NSString *frame = mcla::DiagnosticsEnabled() ? NSProcessInfo.processInfo.environment[@"MCLA_METAL_PASS_CAPTURE_FRAME"] : nil)
      passCaptureFrame_ = uint64_t(std::max<NSInteger>(0, frame.longLongValue));
    if (NSString *frame = mcla::DiagnosticsEnabled() ? NSProcessInfo.processInfo.environment[@"MCLA_HUD_TRACE_FRAME"] : nil)
      hudTraceFrame_ = uint64_t(std::max<NSInteger>(0, frame.longLongValue));
    if (const char* hudOverride = std::getenv("MCLA_HUD_SAFE_FRAME_PROBE"))
      hudSafeFrameProbe_ = std::strcmp(hudOverride, "0") != 0;
    NSString* filterOverride=NSProcessInfo.processInfo.environment[@"MCLA_FILTER_MODE"];
    filterMode_=std::clamp<NSInteger>(filterOverride?filterOverride.integerValue:
        [NSUserDefaults.standardUserDefaults integerForKey:@"MCLAFilterMode"],0,4);
    NSString* bloomOverride=NSProcessInfo.processInfo.environment[@"MCLA_BLOOM_MODE"];
    bloomMode_=std::clamp<NSInteger>(bloomOverride?bloomOverride.integerValue:
        [NSUserDefaults.standardUserDefaults integerForKey:@"MCLABloomMode"],0,2);
    // 0 is the balanced default for fresh installs, 1 preserves the exact
    // title-authored intensity, and 2 is a deliberately restrained option.
    bloomStrength_=bloomMode_==1?1.0f:bloomMode_==2?0.35f:0.65f;
    NSError *error = nil;
    helpers_ = [device_ newLibraryWithSource:kMCLAMetalHelpers
                                     options:nil
                                       error:&error];
    if (!helpers_) {
      REXLOG_ERROR("Metal helper {}", error.localizedDescription.UTF8String);
      return 0xC0000001;
    }
    { // Load even if FSR starts off: the presentation switch is now live.
      NSURL* path=[[NSBundle mainBundle] URLForResource:@"MCLAFsr" withExtension:@"metallib"];
      fsr_=[device_ newLibraryWithURL:path error:&error];
      if(!fsr_){REXLOG_ERROR("MCLA FSR library: {}",error.localizedDescription.UTF8String);return 0xC0000001;}
      auto sampler=[MTLSamplerDescriptor new];
      sampler.minFilter=sampler.magFilter=MTLSamplerMinMagFilterLinear;
      sampler.sAddressMode=sampler.tAddressMode=MTLSamplerAddressModeClampToEdge;
      fsrSampler_=[device_ newSamplerStateWithDescriptor:sampler];
      // Compile once at renderer startup, including when FSR starts disabled.
      // A live switch must not first compile two graphics pipelines in gameplay.
      if(!FsrPipeline(0,MTLPixelFormatRGBA8Unorm) ||
          !FsrPipeline(1,layer_.pixelFormat))return 0xC0000001;
    }
#if MCLA_SMAA_LAB
    NSString *smaaOverride = NSProcessInfo.processInfo.environment[@"MCLA_SMAA_ENABLED"];
    smaaEnabled_ = smaaOverride ? smaaOverride.boolValue :
        [NSUserDefaults.standardUserDefaults boolForKey:@"MCLASMAAEnabled"];
    if (smaaEnabled_) {
      NSURL *path = [[NSBundle mainBundle] URLForResource:@"MCLASmaa"
                                           withExtension:@"metallib"];
      smaa_ = [device_ newLibraryWithURL:path error:&error];
      if (!smaa_) {
        REXLOG_ERROR("MCLA SMAA Lab library: {}", error.localizedDescription.UTF8String);
        return 0xC0000001;
      }
      auto lookup = [&](MTLPixelFormat format, NSUInteger width, NSUInteger height,
                        const unsigned char *bytes, NSUInteger rowBytes) {
        auto descriptor = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:format width:width height:height
                                      mipmapped:NO];
        descriptor.storageMode = MTLStorageModeShared;
        descriptor.usage = MTLTextureUsageShaderRead;
        auto texture = [device_ newTextureWithDescriptor:descriptor];
        if (texture) [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                              mipmapLevel:0 withBytes:bytes bytesPerRow:rowBytes];
        return texture;
      };
      smaaArea_ = lookup(MTLPixelFormatRG8Unorm, AREATEX_WIDTH, AREATEX_HEIGHT,
                         areaTexBytes, AREATEX_PITCH);
      smaaSearch_ = lookup(MTLPixelFormatR8Unorm, SEARCHTEX_WIDTH, SEARCHTEX_HEIGHT,
                           searchTexBytes, SEARCHTEX_PITCH);
      auto linear = [MTLSamplerDescriptor new];
      linear.minFilter = linear.magFilter = MTLSamplerMinMagFilterLinear;
      linear.sAddressMode = linear.tAddressMode = MTLSamplerAddressModeClampToEdge;
      smaaLinear_ = [device_ newSamplerStateWithDescriptor:linear];
      auto point = [MTLSamplerDescriptor new];
      point.minFilter = point.magFilter = MTLSamplerMinMagFilterNearest;
      point.sAddressMode = point.tAddressMode = MTLSamplerAddressModeClampToEdge;
      smaaPoint_ = [device_ newSamplerStateWithDescriptor:point];
      if (!smaaArea_ || !smaaSearch_ || !smaaLinear_ || !smaaPoint_) {
        REXLOG_ERROR("MCLA SMAA Lab lookup texture/sampler allocation failed");
        return 0xC0000001;
      }
    }
    REXLOG_INFO("MCLA SMAA Lab configured enabled={} quality=high stage=before-fsr single_tile=false",
        smaaEnabled_);
#endif
    REXLOG_INFO("MCLA METAL options scene={}x{} fsr={} output={}x{} filter_mode={} bloom_mode={} bloom_strength={:.2f} fixed_present_hz=30 profile={}",mcla::metal::RenderSize(MCLAGraphicsRenderHeight()).width,MCLAGraphicsRenderHeight(),MCLAGraphicsFSREnabled(),layer_.drawableSize.width,layer_.drawableSize.height,filterMode_,bloomMode_,bloomStrength_,profile_);
    for (unsigned k = 0; k < 4; ++k) {
      auto td = [MTLTextureDescriptor
          texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                       width:1
                                      height:1
                                   mipmapped:NO];
      td.storageMode = MTLStorageModeShared;
      td.usage = MTLTextureUsageShaderRead;
      if (k == 1)
        td.textureType = MTLTextureType2DArray;
      if (k == 2)
        td.textureType = MTLTextureType3D;
      if (k == 3)
        td.textureType = MTLTextureTypeCube;
      fallback_[k] = [device_ newTextureWithDescriptor:td];
      uint32_t zero = 0;
      for (unsigned l = 0; l < (k == 3 ? 6 : 1); ++l)
        [fallback_[k] replaceRegion:MTLRegionMake3D(0, 0, 0, 1, 1, 1)
                        mipmapLevel:0
                              slice:l
                          withBytes:&zero
                        bytesPerRow:4
                      bytesPerImage:4];
    }
    auto sd = [MTLSamplerDescriptor new];
    sd.supportArgumentBuffers = YES;
    fallbackSampler_ = [device_ newSamplerStateWithDescriptor:sd];
    for(unsigned k=0;k<5;++k)for(unsigned i=0;i<26;++i){uint64_t id=k==4?fallbackSampler_.gpuResourceID._impl:fallback_[k].gpuResourceID._impl;memcpy(heapTemplate_.data()+k*256+i*8,&id,8);}
    REXLOG_INFO("MCLA HANDWRITTEN METAL active device={} flight_slots=3 "
                "generic_cp=0 vulkan=0 moltenvk=0",
                device_.name.UTF8String);
    return 0;
  }
  uint32_t GetTitleCommandAbi(uint32_t title) const override {
    return title == ng::kTitleId ? ng::kTitleCommandAbi : 0;
  }
  bool SubmitTitleCommand(uint32_t title, uint32_t abi, const void *command,
                          size_t size) override {
    @autoreleasepool {
      if (!memory_ || title != ng::kTitleId || abi != ng::kTitleCommandAbi ||
          size < sizeof(ng::CommandHeader))
        return false;
      auto h = static_cast<const ng::CommandHeader *>(command);
      if (h->size != size)
        return false;
      if (!MCLAGraphicsWaitForApplicationActive()) return false;
      struct CommandTimer {
        double* total;
        double start;
        ~CommandTimer() { if (total) *total += (CACurrentMediaTime()-start)*1000; }
      } timer{performanceCaptureWasActive_ && h->type != ng::CommandType::kPresent
                  ? &frameCommandMS_ : nullptr, 0};
      if (timer.total) timer.start = CACurrentMediaTime();
#define CMD(T)                                                                 \
  if (size != sizeof(ng::T))                                                   \
    return false;                                                              \
  const auto &c = *static_cast<const ng::T *>(command)
      switch (h->type) {
      case ng::CommandType::kRegisterShader: {
        CMD(RegisterShaderCommand);
        shaderHandles_[c.shader] = c.hash;
        return true;
      }
      case ng::CommandType::kRegisterVertexDeclaration: {
        CMD(RegisterVertexDeclarationCommand);
        declarations_[c.declaration] = c;
        ++declarationRevision_;
        declarationVersions_[c.declaration]=declarationRevision_;
        if(decl_==c.declaration)currentDeclarationVersion_=declarationRevision_;
        return true;
      }
      case ng::CommandType::kSetVertexShader: {
        CMD(SetShaderCommand);
        vs_ = c.shader;
        return true;
      }
      case ng::CommandType::kSetPixelShader: {
        CMD(SetShaderCommand);
        ps_ = c.shader;
        return true;
      }
      case ng::CommandType::kSetVertexDeclaration: {
        CMD(SetVertexDeclarationCommand);
        decl_ = c.declaration;
        currentDeclarationVersion_=declarationVersions_[decl_];
        return true;
      }
      case ng::CommandType::kSetVertexStream: {
        CMD(SetVertexStreamCommand);
        if (c.stream >= 17)
          return false;
        streams_[c.stream] = c;
        return true;
      }
      case ng::CommandType::kSetIndexBuffer: {
        CMD(SetIndexBufferCommand);
        index_ = c.buffer;
        return true;
      }
      case ng::CommandType::kDrawPrimitive: {
        CMD(DrawPrimitiveCommand);
        return Draw(c.device, c.primitive_type, c.start_vertex, c.vertex_count,
                    false, 0);
      }
      case ng::CommandType::kDrawIndexedPrimitive: {
        CMD(DrawIndexedPrimitiveCommand);
        return Draw(c.device, c.primitive_type, c.start_index, c.index_count,
                    true, c.base_vertex);
      }
      case ng::CommandType::kDrawPrimitiveUp: {
        CMD(DrawPrimitiveUpCommand);
        return Draw(c.device, c.primitive_type, 0, c.vertex_count, false, 0,
                    c.vertex_data, c.stride);
      }
      case ng::CommandType::kResolve: {
        CMD(ResolveCommand);
        return Resolve(c);
      }
      case ng::CommandType::kClear: {
        CMD(ClearCommand);
        return Clear(c);
      }
      case ng::CommandType::kPresent: {
        CMD(PresentCommand);
        const bool captureThread=MCLAGraphicsPerformanceCaptureActive();
        if(captureThread && submissionThreadStart_.cpuNanoseconds) {
          const auto interval=mcla::metal::MeasureThreadCPUInterval(
              submissionThreadStart_,
              mcla::metal::TakeThreadCPUSample(CACurrentMediaTime()));
          if(interval.valid) {
            submissionThreadWallMS_=interval.wallMilliseconds;
            submissionThreadCPUMS_=interval.cpuMilliseconds;
          }
        }
        const bool submitted=Present(c);
        submissionThreadStart_=MCLAGraphicsPerformanceCaptureActive()
            ? mcla::metal::TakeThreadCPUSample(CACurrentMediaTime())
            : mcla::metal::ThreadCPUSample{};
        return submitted;
      }
      case ng::CommandType::kResourceUnlock: {
        CMD(ResourceUnlockCommand);
        if (c.access != ng::ResourceUnlockAccess::kGuestWrite)
          return true;
        InvalidateResource(c.resource);
        return true;
      }
      case ng::CommandType::kReleaseResource: {
        CMD(ReleaseResourceCommand);
        InvalidateResource(c.resource);
        return true;
      }
      case ng::CommandType::kDeviceCreated:
      case ng::CommandType::kDeviceDestroyed:
      case ng::CommandType::kSetRenderTarget:
      case ng::CommandType::kSetDepthStencil:
        return true;
      default:
        return false;
      }
#undef CMD
    }
  }
  void Shutdown() override {
    EndEncoder();
    if (commands_) {
      auto sem = flights_[slot_].available;
      [commands_ addCompletedHandler:^(id<MTLCommandBuffer>) {
        dispatch_semaphore_signal(sem);
      }];
      if (MCLAGraphicsApplicationActive()) [commands_ commit];
      else dispatch_semaphore_signal(sem); // Discard unsubmitted background work.
      commands_ = nil;
    }
    for (auto &f : flights_) {
      dispatch_semaphore_wait(f.available, DISPATCH_TIME_FOREVER);
      dispatch_semaphore_signal(f.available);
    }
    memory_ = nullptr;
  }
};
} // namespace
std::unique_ptr<rex::system::IGraphicsSystem>
MCLACreateHandwrittenMetalRenderer() {
  return std::make_unique<MetalRenderer>();
}
