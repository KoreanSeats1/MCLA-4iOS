#include "MCLADiagnostics.h"
#include "MCLANativeRenderer.h"
#include "MCLADrawReuse.h"
#include "MCLAActiveVertexStreams.h"
#include "MCLACanonicalDrawState.h"
#include "MCLANativeResolveABI.h"
#include "MCLANativeClear.h"
#include "MCLAShaderConstants.h"
#include "MCLAMissingShaderCapture.h"
#include "MCLAGraphicsFoundation.h"
#include "MCLARuntimeBootstrap.h"
#include "MCLAMetalRenderer.h"
#include <rex/graphics/gta4_native/title_commands.h>
#include <rex/graphics/gta4_native/anti_aliasing_policy.h>
#include <rex/graphics/gta4_native/surface_view.h>
#if !MCLA_DIRECT_METAL
#include <rex/ui/vulkan/provider.h>
#include <rex/ui/vulkan/presenter.h>
#include <graphics/gta4_native/graphics_system.h>
#endif
#include <rex/ui/surface.h>
#include <rex/system/interfaces/graphics.h>
#include <rex/memory.h>
#include <rex/runtime.h>
#include <rex/system/xmemory.h>
#include <rex/cvar.h>
#include <rex/logging.h>
#include "MCLANativeGpuCompatibility.h"
#include <shader/shader_cache.h>
#if MCLA_DIRECT_METAL
#include "mcla_metal_shader_info.h"
#endif
#include <gta4_frame_limiter.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <chrono>
#include <cstring>
#include <cstdlib>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <unordered_set>

namespace ng = rex::graphics::gta4_native;
namespace {
rex::system::IGraphicsSystem* renderer = nullptr;
std::recursive_mutex submissionMutex;
std::mutex framePacingMutex;
gta4::frame_limiter::State framePacing;
double nativeDrawMilliseconds = 0;
std::atomic<double> previousPacingMilliseconds{0};
struct NativeDrawTimer {
  bool enabled = MCLAGraphicsPerformanceCaptureActive();
  std::chrono::steady_clock::time_point start = enabled ?
      std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
  ~NativeDrawTimer() {
    if(enabled) nativeDrawMilliseconds += std::chrono::duration<double,std::milli>(
        std::chrono::steady_clock::now()-start).count();
  }
};
uint64_t draws=0, rejected=0, presents=0, resolves=0;
uint32_t currentDevice=0;
uint32_t nextShader=0xF0000000u;
std::unordered_map<uint64_t,uint32_t> shaders;
std::unordered_set<uint64_t> missingVertexShaders,missingPixelShaders;
mcla::native::MissingShaderCaptureBudget missingCaptureBudget;
struct DeclarationSnapshot {
  uint32_t count = 0;
  std::array<uint8_t,64*12> bytes{};
#if MCLA_DIRECT_METAL
  std::array<ng::VertexElement,64> elements{};
  const MCLAMetalShaderInfo* inputShader=nullptr;
  uint32_t activeStreams=0xFFFF;
#endif
};
std::unordered_map<uint32_t,DeclarationSnapshot> declarations;
#if MCLA_DIRECT_METAL
std::unordered_map<uint64_t,const MCLAMetalShaderInfo*> shaderInputs;
uint64_t vertexStreamChecks=0,vertexStreamChecksSkipped=0;
bool ActiveStreamPreparation() {
  static const bool enabled=[] {
    const char* flag=std::getenv("MCLA_ACTIVE_STREAM_PREPARATION");
    return !flag || std::strcmp(flag,"0")!=0;
  }();return enabled;
}
#endif
struct TiledSurface { uint32_t dimensions; uint32_t width; uint32_t height; };
std::unordered_map<uint32_t,TiledSurface> tiledSurfaces;
std::atomic<uint64_t> surfaceRevision{0};
uint32_t lastVS=UINT32_MAX, lastPS=UINT32_MAX, lastDecl=UINT32_MAX;
struct LastVertexStream {
  uint32_t buffer=UINT32_MAX;
  uint32_t stride=UINT32_MAX;
  uint32_t offset=UINT32_MAX;
};
std::array<LastVertexStream,16> lastStreams;
uint32_t lastIndex=UINT32_MAX;
uint32_t R(const uint8_t* p, uint32_t o) { uint32_t v; std::memcpy(&v,p+o,4); return __builtin_bswap32(v); }
void W(uint8_t* p,uint32_t o,uint32_t v) { v=__builtin_bswap32(v);std::memcpy(p+o,&v,4); }
const uint8_t* P(const uint8_t* base,uint32_t a) { return rex::memory::GuestPtr<const uint8_t*>(const_cast<uint8_t*>(base),a); }
bool Readable(uint32_t address, uint64_t bytes) {
  if(address<0x1000 || !bytes || uint64_t(address)+bytes>0x100000000ull)return false;
  auto* runtime=rex::Runtime::instance();auto* memory=runtime?runtime->memory():nullptr;
  auto* heap=memory?memory->LookupHeap(address):nullptr;
  return heap && heap->QueryRangeAccess(address,uint32_t(uint64_t(address)+bytes-1))!=rex::memory::PageAccess::kNoAccess;
}
thread_local std::array<mcla::native::ShaderDefinitionSnapshot,2> definitionSnapshots;
bool ReuseShaderDefinitions() {
  static const bool enabled=[] {
    const char* flag=std::getenv("MCLA_SHADER_DEFINITION_REUSE");
    return !flag || std::strcmp(flag,"0")!=0;
  }();
  return enabled;
}
void OverlayShaderConstants(uint8_t* snapshot,const uint8_t* device,bool pixel) {
  const uint32_t object=R(device,pixel?12692:12696);
  if(!object || !Readable(object,pixel?64:896))return;
  auto* runtime=rex::Runtime::instance();auto* memory=runtime?runtime->memory():nullptr;
  if(!memory)return;
  const auto* base=memory->virtual_membase();
  const auto* shader=P(base,object);
  const uint32_t descriptor=pixel?40:872;
  const uint32_t relative=R(shader,descriptor+20);
  if(!relative)return;
  const uint64_t table=uint64_t(object)+descriptor+relative;
  if(table>UINT32_MAX || !Readable(uint32_t(table),20))return;
  const uint32_t size=R(P(base,uint32_t(table)),16);
  if(!size || size>65536 || !Readable(uint32_t(table),20ull+size))return;
  const std::span<const uint8_t> tableBytes{P(base,uint32_t(table))+20,size};
  std::span<const mcla::native::ShaderFloatDefinition> definitions;
  std::array<mcla::native::ShaderFloatDefinition,256> fallback;
  if (ReuseShaderDefinitions()) {
    if (!definitionSnapshots[pixel?1:0].Resolve(tableBytes,pixel?256:0,definitions))return;
  } else {
    size_t count=0;
    if (!mcla::native::DecodeShaderFloatDefinitionsInto(tableBytes,pixel?256:0,fallback,count))return;
    definitions={fallback.data(),count};
  }
  const size_t definitionCount=definitions.size();
  const uint32_t physicalBase=R(shader,pixel?24:32);
  // Validate all source spans first so a malformed table cannot leave a
  // partially patched constant bank in this draw's snapshot.
  for(size_t i=0;i<definitionCount;++i) {
    const auto& d=definitions[i];
    const uint64_t source=uint64_t(physicalBase)+d.source;
    if(source>UINT32_MAX || !Readable(uint32_t(source),d.bytes))return;
  }
  for(size_t i=0;i<definitionCount;++i) {
    const auto& d=definitions[i];
    std::memcpy(snapshot+(pixel?6016:1920)+d.destination,
                P(base,physicalBase+d.source),d.bytes);
  }
  if(definitionCount) {
    static std::atomic<uint32_t> reports{0};
    if(reports.load(std::memory_order_relaxed)<12 &&
       reports.fetch_add(1,std::memory_order_relaxed)<12)
      REXLOG_INFO("MCLA native shader constants stage={} object={:08X} definitions={} c255={:08X}",
                  pixel?"ps":"vs",object,definitionCount,R(snapshot,(pixel?6016:1920)+255*16));
  }
}
template<class T> bool Submit(const T& c) {
  bool ok=renderer && renderer->SubmitTitleCommand(ng::kTitleId,ng::kTitleCommandAbi,&c,sizeof(c));
  if(!ok && ++rejected<=24) REXLOG_ERROR("MCLA native command rejected type={} count={}",uint32_t(c.header.type),rejected);
  return ok;
}
void Device(uint32_t dev) {
  if(currentDevice==dev) return;
  currentDevice=dev;
  ng::DeviceCommand c{{sizeof(c),ng::CommandType::kDeviceCreated},dev,0}; Submit(c);
  lastVS=lastPS=lastDecl=UINT32_MAX;
  lastStreams={};
  for(auto& stream:lastStreams)stream={UINT32_MAX,UINT32_MAX,UINT32_MAX};
  lastIndex=UINT32_MAX;
}
uint32_t Shader(uint64_t hash,bool vertex) {
  if(!hash) return 0;
  auto found=shaders.find(hash); if(found!=shaders.end())return found->second;
#if MCLA_DIRECT_METAL
  const auto entry=std::find_if(std::begin(kMCLAMetalShaders),std::end(kMCLAMetalShaders),
      [hash,vertex](const auto& shader){return shader.hash==hash && shader.vertex==vertex;});
  if(entry==std::end(kMCLAMetalShaders)) {
#else
  auto* entry=std::lower_bound(g_shaderCacheEntries,g_shaderCacheEntries+g_shaderCacheEntryCount,hash,
     [](const ShaderCacheEntry& e,uint64_t h){return e.hash<h;});
  if(entry==g_shaderCacheEntries+g_shaderCacheEntryCount || entry->hash!=hash) {
#endif
    ++rejected;
    auto& missing=vertex?missingVertexShaders:missingPixelShaders;
    if(missing.insert(hash).second)
      REXLOG_ERROR("MCLA native shader missing stage={} hash={:016X}",vertex?"vs":"ps",hash);
    return 0;
  }
  uint32_t handle=nextShader++;
  ng::RegisterShaderCommand c; c.shader=handle;c.hash=hash;c.stage=vertex?ng::ShaderStage::kVertex:ng::ShaderStage::kPixel;
  if(!Submit(c))return 0;
#if MCLA_DIRECT_METAL
  if(vertex)shaderInputs.emplace(hash,&*entry);
#endif
  shaders.emplace(hash,handle);return handle;
}
ng::SurfaceDescriptor Surface(const uint8_t* base,uint32_t handle) {
  ng::SurfaceDescriptor s{};s.handle=handle;if(!handle)return s;
  if(!Readable(handle,44))return {};
  auto p=P(base,handle);s.flags=R(p,0);s.base=R(p,24);s.address=R(p,28);
  s.packed_dimensions=R(p,36);s.format=R(p,40);
  s.width=(s.packed_dimensions>>18)+1;s.height=((s.packed_dimensions>>3)&0x7FFF)+1;
  s.sample_type=ng::DecodeSurfaceSampleType(s.base);MCLANativeCanonicalSurface(s);return s;
}
class SurfaceHost final:public rex::ui::Surface {
 public: explicit SurfaceHost(void* layer):layer_(layer){}
  TypeIndex GetType()const override{return kTypeIndex_CAMetalLayer;}
  void* GetNativePresentationHandle()const override{return layer_;}
 protected:bool GetSizeImpl(uint32_t& w,uint32_t& h)const override{return MCLAGraphicsBoundLayerSize(&w,&h);}
 private:void* layer_;
};
}

MCLANativeFrameTiming MCLANativeTakeFrameTiming() {
  // Called at Swap with submissionMutex held by the native adapter.
  const MCLANativeFrameTiming result{nativeDrawMilliseconds,
      previousPacingMilliseconds.load(std::memory_order_relaxed)};
  nativeDrawMilliseconds = 0;
  return result;
}

void MCLANativeCanonicalSurface(ng::SurfaceDescriptor& surface) {
  std::lock_guard lock(submissionMutex);
  auto found=tiledSurfaces.find(surface.handle);
  if(found==tiledSurfaces.end() || found->second.dimensions!=surface.packed_dimensions)return;
  // Native draws use the full guest viewport. EDRAM tile capacity is not the
  // host image size. Normalize both draw snapshots and resolve descriptors.
  surface.width=found->second.width;surface.height=found->second.height;
  surface.packed_dimensions=((surface.width-1)<<18)|((surface.height-1)<<3)|
                             (surface.packed_dimensions&7);
}

uint64_t MCLANativeSurfaceRevision() { return surfaceRevision.load(std::memory_order_relaxed); }
void MCLANativeBeginTiling(const uint8_t* base,uint32_t dev,uint32_t count,uint32_t rectangles) {
  std::lock_guard lock(submissionMutex);
  if(!renderer || !base || count>16 || !Readable(dev,ng::kGuestDeviceSize))return;
  ++surfaceRevision;
  // Clear stale overrides even for non-tiled passes, but retain the prior
  // identity for transition-only logging (BeginTiling runs every frame).
  std::array<TiledSurface,5> previous{};
  for(uint32_t i=0;i<5;++i){
    const auto handle=R(P(base,dev),12440+i*4);
    if(const auto found=tiledSurfaces.find(handle);found!=tiledSurfaces.end())
      previous[i]=found->second;
    tiledSurfaces.erase(handle);
  }
  if(count<2 || !Readable(rectangles,uint64_t(count)*16))return;
  std::array<std::array<int32_t,4>,16> regions{};
  for(uint32_t i=0;i<count;++i)for(uint32_t j=0;j<4;++j)
    regions[i][j]=int32_t(R(P(base,rectangles),i*16+j*4));
  const auto canvas=mcla::native::VerticalTiledCanvas({regions.data(),count});
  if(!canvas)return;
  for(uint32_t i=0;i<5;++i){
    const uint32_t handle=R(P(base,dev),12440+i*4);
    if(!handle || !Readable(handle,44))continue;
    const auto raw=R(P(base,handle),36);
    const uint32_t width=(raw>>18)+1,height=((raw>>3)&0x7FFF)+1;
    if(width!=canvas->width || height>=canvas->height)continue;
    auto& entry=tiledSurfaces[handle];
    const bool changed=previous[i].dimensions!=raw || previous[i].width!=canvas->width ||
                       previous[i].height!=canvas->height;
    entry={raw,canvas->width,canvas->height};
    if(changed)REXLOG_INFO("MCLA native tiled canvas surface={:08X} tile={}x{} canvas={}x{} tiles={}",
                          handle,width,height,canvas->width,canvas->height,count);
  }
}

// The low XDK register/constant blocks match; MCLA's high-level cached
// pointers move by 8 bytes. Normalize only a host copy, never the guest device.
const uint8_t* MCLANativeCanonicalDevice(const uint8_t* device,
    const uint64_t* vertexConstants, const uint64_t* pixelConstants, bool compactDraw) {
  if(!device)return nullptr;
  thread_local std::array<uint8_t,ng::kGuestDeviceSize> snapshot;
  mcla::metal::CopyCanonicalDrawState(snapshot.data(), device, snapshot.size(),
                                    vertexConstants, pixelConstants, compactDraw);
  OverlayShaderConstants(snapshot.data(),device,false);
  OverlayShaderConstants(snapshot.data(),device,true);
  return snapshot.data();
}

std::unique_ptr<rex::system::IGraphicsSystem> MCLACreateNativeRenderer() {
#if MCLA_DIRECT_METAL
  auto result=MCLACreateHandwrittenMetalRenderer();
  renderer=result.get();
  REXLOG_INFO("MCLA selected HANDWRITTEN METAL: no Vulkan, MoltenVK, generic CP or fallback");
  REXLOG_INFO("MCLA rendering patch=visual-experiments-v1 missing_capture_limit=64 texture_failures=bounded visual_experiments={} depth_of_field_disabled={} target_fps={}", MCLAGraphicsVisualExperiments(), MCLAGraphicsDepthOfFieldDisabled(), MCLAGraphicsFrameRate());
  return result;
#else
  rex::cvar::SetFlagByName("gta4_native_vector_fonts","false");
  rex::cvar::SetFlagByName("gta4_native_anti_aliasing","off");
  rex::cvar::SetFlagByName("gta4_native_anti_aliasing_unified","true");
  rex::cvar::SetFlagByName("gta4_native_msaa","original");
  rex::cvar::SetFlagByName("gta4_native_light_overrides","stock");
  rex::cvar::SetFlagByName("gta4_native_state_transport","snapshot");
  auto provider=rex::ui::vulkan::VulkanProvider::Create(false,true,true,true);
  if(!provider)return nullptr;
  auto presenter=provider->CreatePresenter();if(!presenter)return nullptr;
  auto surface=std::make_unique<SurfaceHost>(MCLAGraphicsBoundMetalLayer());
  struct Attach{rex::ui::vulkan::VulkanPresenter* p;rex::ui::Surface* s;} attach{
    static_cast<rex::ui::vulkan::VulkanPresenter*>(presenter.get()),surface.get()};
  auto bind=[](void* arg){auto* a=static_cast<Attach*>(arg);a->p->SetWindowSurfaceFromUIThread(nullptr,a->s);};
  if(pthread_main_np())bind(&attach);else dispatch_sync_f(dispatch_get_main_queue(),&attach,bind);
  auto result=std::make_unique<ng::Gta4NativeGraphicsSystem>(std::move(provider),std::move(presenter),std::move(surface));
  renderer=result.get();
  REXLOG_INFO("MCLA renderer selected: Theft4 native engine, MCLA shader cache, generic command processor disabled");
  return result;
#endif
}

bool MCLANativeDraw(const uint8_t* base,uint32_t dev,uint32_t prim,uint32_t count,uint32_t start,
                   int32_t baseVertex,bool indexed,uint32_t stride,uint32_t data,uint64_t vs,uint64_t ps) {
  std::lock_guard lock(submissionMutex);if(!renderer||!base||!count||!Readable(dev,ng::kGuestDeviceSize))return false;Device(dev);
  NativeDrawTimer drawTimer;
  const auto* device=P(base,dev);
  const uint32_t v=Shader(vs,true),p=Shader(ps,false);
  if(!v || (ps&&!p))return
      mcla::DiagnosticsEnabled() &&
      (missingVertexShaders.contains(vs) || missingPixelShaders.contains(ps)) &&
      missingCaptureBudget.Take(vs,ps);
  auto bindShader=[&](uint32_t handle,uint32_t& last,ng::CommandType type){if(handle==last)return;
    ng::SetShaderCommand c{{sizeof(c),type},dev,handle};if(Submit(c))last=handle;};
  bindShader(v,lastVS,ng::CommandType::kSetVertexShader);bindShader(p,lastPS,ng::CommandType::kSetPixelShader);
  uint32_t decl=R(device,11820);
  uint32_t activeStreams=0xFFFF;
  if(decl && Readable(decl,52)) {
    auto* obj=P(base,decl);const uint32_t n=R(obj,24);
    if(!n || n>64 || !Readable(decl,52+uint64_t(n)*12))return false;
    const auto cached = declarations.find(decl);
    // Exact comparison keeps in-place guest mutations visible and replaces
    // a serial bytewise FNV dependency chain on every city draw.
    if(cached==declarations.end() || cached->second.count!=n ||
       std::memcmp(cached->second.bytes.data(),obj+52,n*12)!=0) {
      ng::RegisterVertexDeclarationCommand c;c.device=dev;c.declaration=decl;c.element_count=n;
      for(uint32_t i=0;i<n;++i){auto* e=obj+52+i*12;auto& d=c.elements[i];
        d.stream=(e[0]<<8)|e[1];d.offset=(e[2]<<8)|e[3];d.type=R(e,4);
        d.method=e[8];d.usage=e[9];d.usage_index=e[10];
        c.maximum_stream=std::max(c.maximum_stream,uint32_t(d.stream));}
      if(Submit(c)) {
        auto& saved=declarations[decl];saved.count=n;
        std::memcpy(saved.bytes.data(),obj+52,n*12);
#if MCLA_DIRECT_METAL
        std::copy_n(c.elements,n,saved.elements.begin());
        saved.inputShader=nullptr;
#endif
      }
      lastDecl=UINT32_MAX;
    }
    if(lastDecl!=decl){ng::SetVertexDeclarationCommand c;c.device=dev;c.declaration=decl;if(Submit(c))lastDecl=decl;}
#if MCLA_DIRECT_METAL
    if(ActiveStreamPreparation()) {
      auto snapshot=declarations.find(decl);
      if(snapshot!=declarations.end()) {
        auto& saved=snapshot->second;
        if(!saved.inputShader || saved.inputShader->hash!=vs) {
          auto info=shaderInputs.find(vs);
          if(info!=shaderInputs.end()) {
            saved.activeStreams=mcla::metal::ActiveVertexStreams(
                std::span<const ng::VertexElement>(saved.elements.data(),saved.count),
                std::span<const MCLAMetalAttribute>(info->second->attributes,info->second->count)).value_or(0xFFFF);
            saved.inputShader=info->second;
          } else saved.inputShader=nullptr;
        }
        if(saved.inputShader)activeStreams=saved.activeStreams;
      }
    }
#endif
  }
  ng::NativeDirtyState dirty;dirty.words.fill(UINT64_MAX);
  if(data){if(!Readable(data,uint64_t(count)*stride)||uint64_t(count)*stride>UINT32_MAX)return false;
    ng::DrawPrimitiveUpCommand c;c.device=dev;c.primitive_type=prim;c.vertex_count=count;
    c.stride=stride;c.vertex_data=data;c.vertex_data_size=count*stride;c.dirty_state=dirty;Submit(c);
  }else{
#if MCLA_DIRECT_METAL
    if(mcla::DiagnosticsEnabled()) {
      const auto used=std::popcount(activeStreams&0xFFFF);
      vertexStreamChecks+=used;vertexStreamChecksSkipped+=16-used;
    }
#endif
    for(uint32_t i=0;i<16;++i){
#if MCLA_DIRECT_METAL
      if(!(activeStreams&(1u<<i)))continue;
#endif
      uint32_t buffer=R(device,12460+i*4);
      ng::SetVertexStreamCommand c;c.device=dev;c.stream=i;
      // Explicit unbinds prevent the previous pass's stream state from
      // surviving into a draw whose guest binding is null. The title repeats
      // the same complete stream table for most adjacent draws, however, so
      // only cross the renderer command boundary when the binding actually
      // changes. Dynamic payload writes are still observed by VertexBuffer;
      // this memo covers binding metadata only.
      if(!buffer){
        const LastVertexStream next{0,0,0};
        if(lastStreams[i].buffer!=next.buffer || lastStreams[i].stride!=next.stride ||
           lastStreams[i].offset!=next.offset){
          if(Submit(c))lastStreams[i]=next;
        }
        continue;
      }
      if(!Readable(buffer,32))return false;
      c.buffer=buffer;c.stride_words=device[12528+i];c.stride=c.stride_words*4;
      const uint32_t fetchAddress=R(device,1152+(95-i)*8)&~3u;
      const uint32_t address=R(P(base,buffer),24)&~3u;
      const uint32_t physical=(address&0x1FFFFFFFu)+(((address>>20)+512u)&0x1000u);
      c.offset=fetchAddress>=physical?fetchAddress-physical:0;
      const LastVertexStream next{c.buffer,c.stride,c.offset};
      if(lastStreams[i].buffer!=next.buffer || lastStreams[i].stride!=next.stride ||
         lastStreams[i].offset!=next.offset){
        if(Submit(c))lastStreams[i]=next;
      }
    }
    if(indexed){const uint32_t index=R(device,12436);
      if(lastIndex!=index){ng::SetIndexBufferCommand b;b.device=dev;b.buffer=index;if(Submit(b))lastIndex=index;}
      ng::DrawIndexedPrimitiveCommand c;c.device=dev;c.primitive_type=prim;c.index_count=count;c.start_index=start;c.base_vertex=baseVertex;c.dirty_state=dirty;Submit(c);
    }else{ng::DrawPrimitiveCommand c;c.device=dev;c.primitive_type=prim;c.vertex_count=count;c.start_vertex=start;c.dirty_state=dirty;Submit(c);}
  }
  ++draws;
  return false;
}

void MCLANativeClear(uint8_t* base,uint32_t dev,uint32_t rectangleCount,uint32_t rectangles,
                     uint32_t flags,uint32_t color,float depth,uint32_t stencil){
  std::lock_guard lock(submissionMutex);
  if(!renderer || !base || !Readable(dev,ng::kGuestDeviceSize))return;
  const auto bytes=mcla::native::ClearRectangleBytes(rectangleCount,rectangles!=0);
  if(!bytes || (*bytes && !Readable(rectangles,*bytes))) {
    if(++rejected<=24)REXLOG_ERROR("MCLA native clear rejected rectangle list count={} address={:08X}",rectangleCount,rectangles);
    return;
  }
  const auto device=P(base,dev);
  uint32_t surfaceHandle=R(device,12440);
  if(!surfaceHandle)surfaceHandle=R(device,12456);
  const auto surface=Surface(base,surfaceHandle);
  // Use the original size here; the helper reproduces the guest's explicit
  // tiled-canvas override before applying viewport and API-scissor clipping.
  const auto dims=surface.handle?R(P(base,surface.handle),36):0;
  const auto regions=mcla::native::DecodeClearRectangles(
      {device,ng::kGuestDeviceSize},rectangleCount,rectangles!=0,
      *bytes?std::span<const uint8_t>{P(base,rectangles),*bytes}:std::span<const uint8_t>{},
      surface.handle?(dims>>18)+1:0,
      surface.handle?((dims>>3)&0x7FFF)+1:0);
  if(!regions) {
    if(++rejected<=24)REXLOG_ERROR("MCLA native clear rejected invalid rectangle/viewport state device={:08X}",dev);
    return;
  }
  if(regions->empty())return;
  Device(dev);
  ng::ClearCommand c;c.device=dev;c.flags=flags;c.depth_bits=std::bit_cast<uint64_t>(double(depth));c.stencil=stencil;
  for(uint32_t i=0;i<4;++i)c.color_bits[i]=std::bit_cast<uint32_t>(float((color>>(i==3?24:(2-i)*8))&255)/255.f);
  c.dirty_state.words.fill(UINT64_MAX);
  for(const auto& r:*regions){
    c.left=r.left;c.top=r.top;c.right=r.right;c.bottom=r.bottom;
    if(!Submit(c))break;
  }
}

bool MCLANativeResolveStackArguments(const uint8_t* base,uint32_t stack,uint32_t* stencil,uint32_t* parameters){
  if(!base || !stencil || !parameters || !Readable(stack,mcla::native::kResolveStackBytes))return false;
  const auto args=mcla::native::DecodeResolveStack({P(base,stack),mcla::native::kResolveStackBytes});
  if(!args)return false;
  *stencil=args->stencil;*parameters=args->parameters;return true;
}

bool MCLANativeResolve(uint8_t* base,uint32_t dev,uint32_t flags,uint32_t rect,uint32_t texture,uint32_t point,
                       uint32_t level,uint32_t slice,uint32_t color,double depth,uint32_t stencil,uint32_t parameters){
  std::lock_guard lock(submissionMutex);
  const auto sourceOffset=mcla::native::ResolveSurfaceOffset(flags);
  // The guest only dereferences this optional structure for resolve-clears.
  const bool hasClearParameters=mcla::native::ResolveUsesClearParameters(flags,parameters);
  if(!renderer || !base || !sourceOffset || !Readable(dev,ng::kGuestDeviceSize) || !Readable(texture,52) ||
     (rect && !Readable(rect,16)) || (point && !Readable(point,8)) ||
     (color && !Readable(color,16)) || (hasClearParameters && !Readable(parameters,12))){
    if(++rejected<=24)REXLOG_ERROR("MCLA native resolve rejected invalid guest arguments dev={:08X} texture={:08X} flags={:08X}",dev,texture,flags);
    return false;
  }
  Device(dev);
  ng::ResolveCommand c;c.device=dev;c.flags=flags;c.destination_texture=texture;c.destination_level=level;c.destination_slice_or_face=slice;
  // Draws capture attachments directly, but resolve-clears use the worker's
  // binding state. Publish the actual bindings (including nulls) first, or
  // clears target empty/stale descriptors and contaminate the next pass.
  for(uint32_t i=0;i<4;++i){
    ng::SetRenderTargetCommand binding;binding.device=dev;binding.index=i;
    binding.surface=Surface(base,R(P(base,dev),12440+i*4));
    if(!Submit(binding))return false;
  }
  ng::SetDepthStencilCommand depthBinding;depthBinding.device=dev;
  depthBinding.surface=Surface(base,R(P(base,dev),12456));
  if(!Submit(depthBinding))return false;
  c.source=Surface(base,R(P(base,dev),*sourceOffset));
  c.flags=ng::NormalizeResolveSampleFlags(flags,c.source.sample_type);
  for(uint32_t i=0;i<6;++i)c.destination_fetch[i]=R(P(base,texture),28+i*4);
  if(rect){auto p=P(base,rect);c.source_rectangle_valid=1;c.source_rectangle={int32_t(R(p,0)),int32_t(R(p,4)),int32_t(R(p,8)),int32_t(R(p,12))};}
  if(point){auto p=P(base,point);c.destination_point_valid=1;c.destination_point={int32_t(R(p,0)),int32_t(R(p,4))};}
  if(color)for(uint32_t i=0;i<4;++i)c.clear_color_bits[i]=R(P(base,color),i*4);
  else if(Readable(0x82008220,16))for(uint32_t i=0;i<4;++i)c.clear_color_bits[i]=R(P(base,0x82008220),i*4);
  if(hasClearParameters){c.parameters_valid=1;c.color_format=R(P(base,parameters),0);
    c.color_exp_bias=int32_t(R(P(base,parameters),4));c.depth_format=R(P(base,parameters),8);}
  c.clear_depth_bits=std::bit_cast<uint64_t>(depth);c.clear_stencil=stencil;
  const bool accepted=Submit(c);
  if(accepted)++resolves;
  return accepted;
}

bool MCLANativePresent(uint8_t* base,uint32_t dev,uint32_t texture){
  std::unique_lock lock(submissionMutex);
  if(!renderer || !base || !Readable(dev,ng::kGuestDeviceSize) || !Readable(texture,52))return false;
  Device(dev);
  ng::PresentCommand c;c.device=dev;c.frontbuffer_texture=texture;
  for(uint32_t i=0;i<6;++i)c.frontbuffer_fetch[i]=R(P(base,texture),28+i*4);
  c.width=(c.frontbuffer_fetch[2]&0x1FFF)+1;c.height=((c.frontbuffer_fetch[2]>>13)&0x1FFF)+1;
  c.display_width=1280;c.display_height=720;c.submitted_frame=uint32_t(++presents);
  // These are the MCLA Swap counters, advanced without emitting a PM4 swap.
  W(const_cast<uint8_t*>(P(base,dev)),16560,c.submitted_frame);
  // Upstream no-CP policy prevents queries from hiding vehicle bodies forever.
  *const_cast<uint8_t*>(P(base,0x8288D5D1))=0;
  bool ok=Submit(c);
  if(mcla::DiagnosticsEnabled() && (presents<=5 || presents%120==0)){
    char msg[384];std::snprintf(msg,sizeof(msg),"backend=%s native_title_takeover=1 generic_cp=0 native_draws=%llu resolves=%llu presents=%llu rejected=%llu missing_unique=%zu",MCLA_DIRECT_METAL?"mcla-handwritten-metal":"mcla-title-vulkan",draws,resolves,presents,rejected,missingVertexShaders.size()+missingPixelShaders.size());
    MCLAPublishRuntimeGpuTelemetry(msg);REXLOG_INFO("{}",msg);
#if MCLA_DIRECT_METAL
    REXLOG_INFO("MCLA native active_stream_preparation={} stream_checks={} skipped_stream_checks={}",
        ActiveStreamPreparation(),vertexStreamChecks,vertexStreamChecksSkipped);
#endif
    REXLOG_INFO("MCLA native definition_reuse={} definition_hits={} definition_decodes={}",
        ReuseShaderDefinitions(),definitionSnapshots[0].hits()+definitionSnapshots[1].hits(),
        definitionSnapshots[0].decodes()+definitionSnapshots[1].decodes());
  }
  lock.unlock();
  if(ok){
    // Reuse Theft4's tested deadline accumulator, including late-frame reset.
    // The guest no longer has a generic command processor's swap throttle.
    using Clock=std::chrono::steady_clock;using Nanoseconds=std::chrono::nanoseconds;
    std::lock_guard pacingLock(framePacingMutex);
    const auto now=std::chrono::duration_cast<Nanoseconds>(Clock::now().time_since_epoch()).count();
    const auto decision=gta4::frame_limiter::Plan(framePacing,MCLAGraphicsFrameRate(),now);
    framePacing=decision.next_state;
    if(decision.should_wait(now))std::this_thread::sleep_until(Clock::time_point(Nanoseconds(decision.wait_until_ns)));
    previousPacingMilliseconds.store(std::chrono::duration<double,std::milli>(
        Clock::now()-Clock::time_point(Nanoseconds(now))).count(),std::memory_order_relaxed);
  }
  return ok;
}

void MCLANativeResourceUnlock(uint8_t* base,uint32_t resource,uint32_t mipAddress,uint32_t caller){
  std::lock_guard lock(submissionMutex);
  if(!renderer || !base || !Readable(resource,28))return;
  const auto* header=P(base,resource);
  // Inspect before the generated unlock decrements the lock count and clears
  // its dirty ranges. Nested and read-only unlocks must not invalidate an
  // authoritative host-produced render target.
  if((R(header,0)&0xF00)!=0x100)return;
  auto dirty=[](uint32_t range){return (range&0xFFFF)>(range>>16);};
  if(!dirty(R(header,20)) && !(mipAddress && dirty(R(header,24))))return;
  ng::ResourceUnlockCommand command;command.resource=resource;
  command.access=ng::ResourceUnlockAccess::kGuestWrite;command.unlock_caller=caller;
  // Zero length requests full-resource invalidation, including a mip-only
  // write. The engine retains old snapshots until their GPU fences complete.
  Submit(command);
}

void MCLANativeResourceRelease(uint32_t resource){
  std::lock_guard lock(submissionMutex);if(!renderer||!resource)return;
  tiledSurfaces.erase(resource);
  ng::ReleaseResourceCommand command;command.resource=resource;Submit(command);
}
