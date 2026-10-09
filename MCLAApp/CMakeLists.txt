cmake_minimum_required(VERSION 3.25)

project(MCLAApp VERSION 1.0.4 LANGUAGES C CXX OBJC OBJCXX)

if(NOT APPLE OR NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "MCLAApp currently targets iOS/iPadOS. Configure with -DCMAKE_SYSTEM_NAME=iOS.")
endif()

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(MCLA_RUNTIME_ENABLED "Link the MCLA AOT runtime and enable launch attempts" ON)
option(MCLA_DIRECT_METAL "Use the hand-written title Metal renderer; no generic fallback" ON)
option(MCLA_SINGLE_TILE_LAB "Build a separate MCLA Lab app with the guarded single-tile experiment" OFF)
option(MCLA_SMAA_LAB "Build a separate MCLA Lab app with handwritten Metal SMAA" OFF)
if(MCLA_SINGLE_TILE_LAB AND MCLA_SMAA_LAB)
    message(FATAL_ERROR "Select only one MCLA Lab experiment")
endif()
if((MCLA_SINGLE_TILE_LAB OR MCLA_SMAA_LAB) AND
   (NOT MCLA_RUNTIME_ENABLED OR NOT MCLA_DIRECT_METAL))
    message(FATAL_ERROR "MCLA Lab requires the title runtime and handwritten Metal")
endif()
option(MCLA_ENABLE_XENOS_VULKAN
       "Link shared Xenos/Vulkan support; MCLA uses the title-native renderer" ON)
if(MCLA_DIRECT_METAL)
    set(MCLA_ENABLE_XENOS_VULKAN OFF)
endif()
set(MCLA_THEFT4_FOUNDATION_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../theft4-foundation"
    CACHE PATH "Read-only Theft4 reference checkout containing the ReXGlue foundation")

set(MCLA_REXGLUE_SOURCE_STAGED OFF)
if(EXISTS "${MCLA_THEFT4_FOUNDATION_DIR}/glue/rexglue-sdk-main/src/graphics/command_processor.cpp")
    set(MCLA_REXGLUE_SOURCE_STAGED ON)
    message(STATUS "MCLA: ReXGlue/Xenos foundation staged at ${MCLA_THEFT4_FOUNDATION_DIR}")
else()
    message(STATUS "MCLA: ReXGlue/Xenos foundation not staged; shell remains buildable")
endif()

set(MCLA_REXGLUE_SDK_DIR
    "${MCLA_THEFT4_FOUNDATION_DIR}/glue/rexglue-sdk-main")
set(MCLA_GENERATED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/generated")
set(MCLA_XENIOS_IOS_LIB_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../XeniOS-reference/build-ios-xcode/obj/iOS/Release"
    CACHE PATH "Directory containing the device MoltenVK/SPIR-V static archives")
set(MCLA_TITLE_AOT_LINKED OFF)
set(MCLA_RUNTIME_CORE_LINKED OFF)
set(MCLA_XENOS_BACKEND_LINKED OFF)

if(MCLA_RUNTIME_ENABLED)
    if(NOT EXISTS "${MCLA_GENERATED_DIR}/sources.cmake")
        message(FATAL_ERROR
            "MCLA_RUNTIME_ENABLED requires generated/sources.cmake. "
            "Run the MCLA codegen preparation step first.")
    endif()

    # Reuse the proven Theft4 ReXGlue kernel/runtime foundation without
    # enabling its GTA-specific renderer or modifying the reference checkout.
    set(REXGLUE_CORE_ONLY ON CACHE BOOL "" FORCE)
    set(REXGLUE_RUNTIME_ONLY ON CACHE BOOL "" FORCE)
    set(REXGLUE_HEADLESS_KERNEL ON CACHE BOOL "" FORCE)
    set(REXGLUE_HEADLESS_RENDER_AUDIO ON CACHE BOOL "" FORCE)
    # MCLA's cinematics and streaming state advance through the real XMA
    # hardware contract. A paced mixer without the decoder can leave the
    # animated loading screen alive while title state waits indefinitely.
    set(REXGLUE_HEADLESS_XMA_DECODER ON CACHE BOOL "" FORCE)
    set(REXGLUE_HEADLESS_INPUT ON CACHE BOOL "" FORCE)
    set(REXGLUE_USE_VULKAN OFF CACHE BOOL "" FORCE)
    set(REXGLUE_USE_D3D12 OFF CACHE BOOL "" FORCE)
    set(REXGLUE_ENABLE_TRACY OFF CACHE BOOL "" FORCE)
    set(REXGLUE_ENABLE_PERF_COUNTERS OFF CACHE BOOL "" FORCE)
    set(REXGLUE_BUILD_GTA4_RECOMP OFF CACHE BOOL "" FORCE)
    set(REXGLUE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    # FindThreads' executable link probe is unreliable while cross-compiling
    # with the iOS SDK. pthreads are part of libSystem on Apple platforms.
    set(CMAKE_HAVE_LIBC_PTHREAD 1 CACHE INTERNAL "" FORCE)
    set(CMAKE_USE_PTHREADS_INIT 1 CACHE INTERNAL "" FORCE)
    set(CMAKE_THREAD_LIBS_INIT "" CACHE STRING "" FORCE)
    add_subdirectory("${MCLA_REXGLUE_SDK_DIR}"
                     "${CMAKE_CURRENT_BINARY_DIR}/rexglue")

    include("${MCLA_GENERATED_DIR}/sources.cmake")
    if(MCLA_SINGLE_TILE_LAB)
        # Keep the working app's generated AOT source untouched. The Lab-only
        # copies of the two hook-bearing units are made in this build tree.
        find_package(Python3 REQUIRED COMPONENTS Interpreter)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
            "${CMAKE_CURRENT_SOURCE_DIR}/tools/generate_single_tile_lab.py"
            "${MCLA_GENERATED_DIR}/larecomp_recomp.2.cpp"
            "${MCLA_GENERATED_DIR}/larecomp_recomp.25.cpp")
        set(MCLA_LAB_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/mcla-lab-generated")
        execute_process(
            COMMAND "${Python3_EXECUTABLE}"
                    "${CMAKE_CURRENT_SOURCE_DIR}/tools/generate_single_tile_lab.py"
                    "${MCLA_GENERATED_DIR}" "${MCLA_LAB_GENERATED_DIR}"
            RESULT_VARIABLE MCLA_LAB_GENERATE_RESULT
            OUTPUT_VARIABLE MCLA_LAB_GENERATE_OUTPUT
            ERROR_VARIABLE MCLA_LAB_GENERATE_ERROR)
        if(NOT MCLA_LAB_GENERATE_RESULT EQUAL 0)
            message(FATAL_ERROR "MCLA Lab AOT patch generation failed: ${MCLA_LAB_GENERATE_ERROR}")
        endif()
        list(REMOVE_ITEM GENERATED_SOURCES
            "${MCLA_GENERATED_DIR}/larecomp_recomp.2.cpp"
            "${MCLA_GENERATED_DIR}/larecomp_recomp.25.cpp")
        list(APPEND GENERATED_SOURCES
            "${MCLA_LAB_GENERATED_DIR}/larecomp_recomp.2.cpp"
            "${MCLA_LAB_GENERATED_DIR}/larecomp_recomp.25.cpp")
    endif()
    add_library(MCLATitleAOT STATIC ${GENERATED_SOURCES})
    target_include_directories(MCLATitleAOT PUBLIC "${MCLA_GENERATED_DIR}")
    target_link_libraries(MCLATitleAOT PUBLIC rex::runtime)
    target_compile_features(MCLATitleAOT PUBLIC cxx_std_23)
    set_source_files_properties("${MCLA_GENERATED_DIR}/larecomp_register.cpp"
        PROPERTIES COMPILE_OPTIONS "-O0;-fno-global-isel")

    # LARecomp's shipping manifest contains optional diagnostics, desktop UI,
    # multiplayer probes, and mod hooks. Its XEO3 build already supplies a
    # title-maintained inert implementation for those hooks. Reuse those exact
    # stubs for the first iPad boot instead of inventing behavior or pulling
    # Windows-only subsystems into the Apple target.
    set(MCLA_BOOT_HOOK_STUB_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/hooks.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/time_of_day.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/carbon_parts.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/cutscene_gallery.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/map_mouse.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/menu_camera.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/pause_menu.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/camera_look.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/squash_stretch.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/tire_offset.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/online/system_link.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/online/tournament.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/mc_engine/mp3custom/mp3custom.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/discord_rpc/discord_hooks.cpp"
    )
    add_library(MCLABootHookStubs STATIC ${MCLA_BOOT_HOOK_STUB_SOURCES})
    target_compile_definitions(MCLABootHookStubs PRIVATE
        REXGLUE_HAS_XEO3_TARGET=1)
    # A few upstream XEO3 stub branches name PPCRegister without repeating
    # the declaration include used by their desktop branch.
    target_compile_options(MCLABootHookStubs PRIVATE
        -include rex/ppc/context.h)
    target_include_directories(MCLABootHookStubs PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src")
    target_link_libraries(MCLABootHookStubs PUBLIC rex::runtime)
    target_compile_features(MCLABootHookStubs PUBLIC cxx_std_23)
    set(MCLA_TITLE_AOT_LINKED ON)
    set(MCLA_RUNTIME_CORE_LINKED ON)
    message(STATUS "MCLA: ReXGlue runtime and generated title AOT enabled")
endif()

# Compile and link the title-neutral ownership pieces already proven by the
# Theft4 native renderer. MCLA consumes an isolated foundation clone and owns
# its presenter and title mappings separately from the actual Theft4 project.
set(MCLA_NATIVE_RENDERER_ROOT
    "${MCLA_THEFT4_FOUNDATION_DIR}/glue/rexglue-sdk-main/src/graphics/gta4_native")
set(MCLA_LARECOMP_NATIVE_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../larecomp/src/native_gfx")
set(MCLA_NATIVE_RENDERER_PORTABLE_SOURCES
    "${MCLA_NATIVE_RENDERER_ROOT}/native_buffer_arena.cpp"
    "${MCLA_NATIVE_RENDERER_ROOT}/native_descriptor_backend.cpp"
    "${MCLA_NATIVE_RENDERER_ROOT}/native_frame_context.cpp"
    "${MCLA_NATIVE_RENDERER_ROOT}/native_memory_samples.cpp"
    "${MCLA_NATIVE_RENDERER_ROOT}/native_performance_samples.cpp"
    "${MCLA_NATIVE_RENDERER_ROOT}/native_submission_lifetime.cpp"
    # MCLA-owned title decoding. These are backend-independent and become the
    # front half of the Metal adapter; D3D12 files remain excluded.
    "${MCLA_LARECOMP_NATIVE_ROOT}/shader_identity.cpp"
    "${MCLA_LARECOMP_NATIVE_ROOT}/draw_slicing.cpp"
)
set(MCLA_NATIVE_RENDERER_CORE_LINKED OFF)
if(EXISTS "${MCLA_NATIVE_RENDERER_ROOT}/native_buffer_arena.cpp")
    add_library(MCLANativeRendererCore STATIC
        ${MCLA_NATIVE_RENDERER_PORTABLE_SOURCES})
    target_include_directories(MCLANativeRendererCore PUBLIC
        "${MCLA_NATIVE_RENDERER_ROOT}"
        "${MCLA_LARECOMP_NATIVE_ROOT}")
    target_compile_features(MCLANativeRendererCore PUBLIC cxx_std_23)
    set(MCLA_NATIVE_RENDERER_CORE_LINKED ON)
    message(STATUS "MCLA: portable Theft4 native-renderer core enabled")
endif()

set(MCLA_APP_SOURCES
    ios/main.mm
    ios/AppDelegate.mm
    ios/SceneDelegate.mm
    ios/MCLAMetalView.mm
    ios/MCLAViewController.mm
    ios/MCLASaveArchive.mm
    ios/MCLALogArchive.mm
    ios/MCLALauncherView.mm
    ios/MCLALauncherSceneView.mm
    runtime/MCLAGraphicsFoundation.mm
    runtime/MCLAHostBridge.mm
)

if(MCLA_RUNTIME_ENABLED)
    list(APPEND MCLA_APP_SOURCES
        runtime/MCLARuntimeBootstrap.cpp
        runtime/MCLAAppleGraphicsHooks.cpp
        runtime/MCLANativeTitleBridge.cpp
        runtime/MCLABootstrapSubsystems.cpp
        runtime/MCLAAudioOutput.mm
        runtime/MCLAGraphicsFlags.cpp
        "${MCLA_REXGLUE_SDK_DIR}/src/input/absolute_pointer.cpp"
        "${MCLA_REXGLUE_SDK_DIR}/src/input/ios/ios_input_driver.mm")
endif()

add_executable(MCLAApp MACOSX_BUNDLE ${MCLA_APP_SOURCES})

if(MCLA_SINGLE_TILE_LAB)
    target_sources(MCLAApp PRIVATE runtime/MCLASingleTileLab.cpp)
    target_compile_definitions(MCLAApp PRIVATE MCLA_SINGLE_TILE_LAB=1)
    message(STATUS "MCLA Lab: separate bundle with guarded guest single-tile experiment")
endif()

target_include_directories(MCLAApp PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/ios"
    "${CMAKE_CURRENT_SOURCE_DIR}/runtime"
    "${MCLA_REXGLUE_SDK_DIR}/src/input"
)

set_source_files_properties(runtime/MCLAAudioOutput.mm
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
set_source_files_properties(
    "${MCLA_REXGLUE_SDK_DIR}/src/input/ios/ios_input_driver.mm"
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc")

if(MCLA_RUNTIME_ENABLED AND MCLA_ENABLE_XENOS_VULKAN)
    target_sources(MCLAApp PRIVATE runtime/MCLAXenosGraphics.cpp runtime/MCLAVulkanGate.cpp)
    if(NOT EXISTS "${MCLA_XENIOS_IOS_LIB_DIR}/libMoltenVK.a")
        message(FATAL_ERROR
            "MCLA's native Xenos backend requires the device MoltenVK archives at "
            "${MCLA_XENIOS_IOS_LIB_DIR}")
    endif()

    # Build the same checked-in glslang revision as the proven Theft4 generic
    # backend. The Xenos translator needs both SPIR-V emission and runtime GLSL
    # compilation for its internal resolve/copy shaders.
    set(ENABLE_GLSLANG_BINARIES OFF CACHE BOOL "" FORCE)
    set(ENABLE_SPVREMAPPER OFF CACHE BOOL "" FORCE)
    set(ENABLE_OPT OFF CACHE BOOL "" FORCE)
    set(ENABLE_RTTI ON CACHE BOOL "" FORCE)
    set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(SKIP_GLSLANG_INSTALL ON CACHE BOOL "" FORCE)
    # The vendored, known-good glslang revision predates CMake 4's removal of
    # compatibility defaults but is intentionally the same ABI used by Theft4.
    set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)
    add_subdirectory(
        "${MCLA_REXGLUE_SDK_DIR}/thirdparty/glslang"
        "${CMAKE_CURRENT_BINARY_DIR}/mcla-glslang" EXCLUDE_FROM_ALL)

    set(MCLA_XENOS_SOURCE_ROOT "${MCLA_REXGLUE_SDK_DIR}/src")
    target_sources(MCLAApp PRIVATE
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/command_processor.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/vulkan/command_processor.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/format/ucode.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/shader.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/spirv.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/spirv_builder.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/spirv_translator.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/spirv_translator_alu.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/spirv_translator_fetch.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/spirv_translator_memexport.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/spirv_translator_rb.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/translator.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/translator_disasm.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/util/draw.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/register_file.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/registers.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/trace_writer.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/flags.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/renderdoc_api.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/graphics_upload_buffer_pool.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/graphics_util.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/presenter.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/linked_type_descriptor_set_allocator.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/single_layout_descriptor_set_pool.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/ui_samplers.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/vulkan_instance.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/vulkan_device.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/vulkan_mem_alloc.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/vulkan_presenter.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/vulkan_submission_tracker.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/vulkan_upload_buffer_pool.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/ui/vulkan/vulkan_util.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/sampler_info.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/packet_disassembler.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/primitive_processor.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/shared_memory.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/render_target/cache.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/texture/cache.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/pipeline/shader/interpreter.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/util/draw_extent_estimator.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/vulkan/deferred_command_buffer.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/vulkan/pipeline_cache.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/vulkan/primitive_processor.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/vulkan/render_target_cache.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/vulkan/shader.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/vulkan/shared_memory.cpp"
        "${MCLA_XENOS_SOURCE_ROOT}/graphics/vulkan/texture_cache.cpp")
    target_include_directories(MCLAApp PRIVATE
        "${MCLA_REXGLUE_SDK_DIR}/thirdparty/vulkan-headers/include"
        "${MCLA_REXGLUE_SDK_DIR}/thirdparty/vulkan-memory-allocator/include"
        "${MCLA_REXGLUE_SDK_DIR}/thirdparty/glslang"
        "${MCLA_REXGLUE_SDK_DIR}/thirdparty/renderdoc")
    target_compile_definitions(MCLAApp PRIVATE REX_HAS_VULKAN=1)
    target_link_libraries(MCLAApp PRIVATE
        SPIRV glslang MachineIndependent GenericCodeGen OSDependent OGLCompiler
        xxHash::xxhash
        "${MCLA_XENIOS_IOS_LIB_DIR}/libMoltenVK.a"
        "${MCLA_XENIOS_IOS_LIB_DIR}/libMoltenVK_ShaderConverter.a"
        "${MCLA_XENIOS_IOS_LIB_DIR}/libMoltenVK_Common.a"
        "${MCLA_XENIOS_IOS_LIB_DIR}/libspirv-cross.a"
        "${MCLA_XENIOS_IOS_LIB_DIR}/libSPIRV-Tools.a"
        "-framework CoreFoundation"
        "-framework IOSurface")
    target_link_options(MCLAApp PRIVATE
        "LINKER:-force_load,${MCLA_XENIOS_IOS_LIB_DIR}/libMoltenVK.a"
        "LINKER:-force_load,$<TARGET_FILE:rexruntime>")
    set(MCLA_XENOS_BACKEND_LINKED ON)
    message(STATUS "MCLA: Vulkan/MoltenVK transport linked; title-native renderer selected (no generic CP)")
endif()

target_compile_definitions(MCLAApp PRIVATE
    MCLA_NATIVE_TITLE=1
    MCLA_DIRECT_METAL=$<BOOL:${MCLA_DIRECT_METAL}>
    MCLA_RUNTIME_ENABLED=$<BOOL:${MCLA_RUNTIME_ENABLED}>
    MCLA_REXGLUE_SOURCE_STAGED=$<BOOL:${MCLA_REXGLUE_SOURCE_STAGED}>
    MCLA_NATIVE_RENDERER_CORE_LINKED=$<BOOL:${MCLA_NATIVE_RENDERER_CORE_LINKED}>
    MCLA_XENOS_RUNTIME_LINKED=$<BOOL:${MCLA_XENOS_BACKEND_LINKED}>
    MCLA_TITLE_AOT_LINKED=$<BOOL:${MCLA_TITLE_AOT_LINKED}>
)

if(MCLA_NATIVE_RENDERER_CORE_LINKED)
    target_link_libraries(MCLAApp PRIVATE MCLANativeRendererCore)
endif()

if(MCLA_RUNTIME_ENABLED AND NOT MCLA_DIRECT_METAL)
    # Compile the actual Theft4 native engine with MCLA's own cache/profile.
    # The original GTA4 checkout is read only for compiler support libraries.
    set(MCLA_XENOS_COMPILER_ROOT "${MCLA_THEFT4_FOUNDATION_DIR}/tools/XenosRecomp" CACHE PATH "XenosRecomp support libraries")
    set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
    set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
    set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    add_subdirectory("${MCLA_XENOS_COMPILER_ROOT}/thirdparty/zstd/build/cmake" "mcla-native-zstd" EXCLUDE_FROM_ALL)
    target_sources(MCLAApp PRIVATE
        runtime/MCLANativeRenderer.cpp
        runtime/MCLANativeSettings.cpp
        generated/mcla_native_cache.cpp
        "${MCLA_NATIVE_RENDERER_ROOT}/graphics_system.cpp"
        "${MCLA_NATIVE_RENDERER_ROOT}/modern_shader_options.cpp"
        "${MCLA_NATIVE_RENDERER_ROOT}/native_gpu_attribution.cpp"
        "${MCLA_NATIVE_RENDERER_ROOT}/postfx_resource_pool.cpp"
        "${MCLA_NATIVE_RENDERER_ROOT}/smaa_pipeline.cpp"
        "${MCLA_NATIVE_RENDERER_ROOT}/split_postfx_pass.cpp"
        "${MCLA_NATIVE_RENDERER_ROOT}/sun_shafts_pass.cpp"
        "${MCLA_THEFT4_FOUNDATION_DIR}/ios/bridge/theft4_empty_shader_overrides.cpp"
        "${MCLA_XENOS_COMPILER_ROOT}/thirdparty/smol-v/source/smolv.cpp"
        "${MCLA_REXGLUE_SDK_DIR}/src/ui/image_decode.cpp"
        "${MCLA_REXGLUE_SDK_DIR}/src/ui/immediate_drawer.cpp"
        "${MCLA_REXGLUE_SDK_DIR}/src/ui/windowed_app_context.cpp"
        "${MCLA_REXGLUE_SDK_DIR}/src/ui/vulkan/vulkan_immediate_drawer.cpp"
        "${MCLA_REXGLUE_SDK_DIR}/src/ui/vulkan/vulkan_provider.cpp")
    target_include_directories(MCLAApp PRIVATE
        runtime/native_cache
        "${MCLA_THEFT4_FOUNDATION_DIR}/LibertyRecompLib"
        "${MCLA_REXGLUE_SDK_DIR}/src"
        "${MCLA_REXGLUE_SDK_DIR}/gta4-recomp/src"
        "${MCLA_REXGLUE_SDK_DIR}/thirdparty/stb"
        "${MCLA_REXGLUE_SDK_DIR}/thirdparty/spirv-headers/include"
        "${MCLA_XENOS_COMPILER_ROOT}/thirdparty/smol-v/source"
        "${MCLA_XENOS_COMPILER_ROOT}/thirdparty/zstd/lib")
    target_link_libraries(MCLAApp PRIVATE libzstd_static)
    set_source_files_properties("${MCLA_NATIVE_RENDERER_ROOT}/graphics_system.cpp"
        PROPERTIES COMPILE_DEFINITIONS "REXGLUE_BUILD_CONFIG=\"${CMAKE_BUILD_TYPE}\"")
endif()

if(MCLA_RUNTIME_ENABLED AND MCLA_DIRECT_METAL)
    target_sources(MCLAApp PRIVATE runtime/MCLANativeRenderer.cpp
        runtime/MCLAMetalRenderer.mm runtime/MCLANativeSettings.cpp)
    target_include_directories(MCLAApp PRIVATE runtime/native_cache
        "${MCLA_REXGLUE_SDK_DIR}/src"
        "${MCLA_REXGLUE_SDK_DIR}/gta4-recomp/src"
        "${MCLA_REXGLUE_SDK_DIR}/thirdparty/vulkan-headers/include"
        "${MCLA_THEFT4_FOUNDATION_DIR}/LibertyRecompLib")
    target_link_options(MCLAApp PRIVATE "LINKER:-force_load,$<TARGET_FILE:rexruntime>")
    target_link_libraries(MCLAApp PRIVATE xxHash::xxhash)
    file(GLOB MCLA_METAL_LIBRARIES "${CMAKE_CURRENT_SOURCE_DIR}/../artifacts/mcla-metal-shaders/*.metallib")
    list(LENGTH MCLA_METAL_LIBRARIES MCLA_METAL_LIBRARY_COUNT)
    if(MCLA_METAL_LIBRARY_COUNT LESS 534)
        message(FATAL_ERROR "Expected at least 534 Metal title libraries; run tools/build_mcla_metal_shaders.py")
    endif()
    set_source_files_properties(${MCLA_METAL_LIBRARIES} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/MCLAMetalShaders")
    target_sources(MCLAApp PRIVATE ${MCLA_METAL_LIBRARIES})
    set(MCLA_FSR_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/../artifacts/mcla-metal-upscale/MCLAFsr.metallib")
    if(NOT EXISTS "${MCLA_FSR_LIBRARY}")
        message(FATAL_ERROR "Run tools/build_mcla_fsr.py to build the offline Metal FSR library")
    endif()
    set_source_files_properties("${MCLA_FSR_LIBRARY}" shaders/MCLAFsr-LICENSE.txt
        PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
    target_sources(MCLAApp PRIVATE "${MCLA_FSR_LIBRARY}" shaders/MCLAFsr-LICENSE.txt)
    if(MCLA_SMAA_LAB)
        target_compile_definitions(MCLAApp PRIVATE MCLA_SMAA_LAB=1)
        set(MCLA_SMAA_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/../artifacts/mcla-metal-smaa/MCLASmaa.metallib")
        if(NOT EXISTS "${MCLA_SMAA_LIBRARY}")
            message(FATAL_ERROR "Run tools/build_mcla_smaa.py to build the offline Metal SMAA library")
        endif()
        set_source_files_properties("${MCLA_SMAA_LIBRARY}" shaders/MCLASmaa-LICENSE.txt
            PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
        target_sources(MCLAApp PRIVATE "${MCLA_SMAA_LIBRARY}" shaders/MCLASmaa-LICENSE.txt)
    endif()
endif()

if(MCLA_RUNTIME_ENABLED)
    target_link_libraries(MCLAApp PRIVATE
        MCLATitleAOT MCLABootHookStubs rex::runtime)
endif()

target_link_libraries(MCLAApp PRIVATE
    z
    "-framework UIKit"
    "-framework UniformTypeIdentifiers"
    "-framework SceneKit"
    "-framework MetalKit"
    "-framework CoreGraphics"
    "-framework Metal"
    "-framework QuartzCore"
    "-framework GameController"
    "-framework CoreMotion"
    "-framework CoreHaptics"
    "-framework AVFoundation"
    "-framework AudioToolbox"
)

set_source_files_properties(Resources/GameDataManifest.json PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources
)
target_sources(MCLAApp PRIVATE Resources/GameDataManifest.json)
set_source_files_properties(Resources/Assets.xcassets PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources)
target_sources(MCLAApp PRIVATE Resources/Assets.xcassets)

# Generated exclusively from the user's live MCLA shader descriptors. This is
# the first title-specific input to the MCLA native renderer and intentionally
# remains separate from Theft4's GTA IV shader cache.
set(MCLA_VERTEX_METADATA_MAP
    "${CMAKE_CURRENT_SOURCE_DIR}/../artifacts/mcla-native-metadata/mcla_vertex_elements.map")
if(NOT EXISTS "${MCLA_VERTEX_METADATA_MAP}")
    message(FATAL_ERROR
        "MCLA vertex metadata map is missing. Run tools/mcla_vertex_semantics "
        "against a device native-capture directory first.")
endif()
set_source_files_properties("${MCLA_VERTEX_METADATA_MAP}" PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources
)
target_sources(MCLAApp PRIVATE "${MCLA_VERTEX_METADATA_MAP}")

# Raw SPIR-V compiled offline from MCLA's captured Xenos programs using the
# same compiler lineage as Theft4. Entries are keyed by MCLA's normalized
# runtime shader identities and remain independently gated from takeover.
set(MCLA_NATIVE_SHADER_PACK
    "${CMAKE_CURRENT_SOURCE_DIR}/../artifacts/mcla-native-metadata/mcla_native_shaders.mspv")
if(NOT EXISTS "${MCLA_NATIVE_SHADER_PACK}")
    message(FATAL_ERROR
        "MCLA native SPIR-V pack is missing. Run tools/build_mcla_native_shaders.sh "
        "and tools/mcla_spirv_pack first.")
endif()
set_source_files_properties("${MCLA_NATIVE_SHADER_PACK}" PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources
)
target_sources(MCLAApp PRIVATE "${MCLA_NATIVE_SHADER_PACK}")

if(MCLA_SINGLE_TILE_LAB OR MCLA_SMAA_LAB)
    set(MCLA_APP_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/ios/Info-Lab.plist")
    set(MCLA_APP_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/MCLALab.entitlements")
    set(MCLA_APP_BUNDLE_NAME "MCLA Lab")
    set(MCLA_APP_BUNDLE_ID "com.koreanseats.mcla.lab")
else()
    set(MCLA_APP_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/ios/Info.plist")
    set(MCLA_APP_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/MCLAApp.entitlements")
    set(MCLA_APP_BUNDLE_NAME "MCLA")
    set(MCLA_APP_BUNDLE_ID "com.koreanseats.mcla")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${MCLA_APP_INFO_PLIST}")
set_target_properties(MCLAApp PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${MCLA_APP_INFO_PLIST}"
    MACOSX_BUNDLE_BUNDLE_NAME "${MCLA_APP_BUNDLE_NAME}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${MCLA_APP_BUNDLE_ID}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "6"
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC "YES"
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
    XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${MCLA_APP_ENTITLEMENTS}"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
    XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION "6"
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${MCLA_DEVELOPMENT_TEAM}"
    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE "NO"
    # The linked MoltenVK/SPIR-V device archives are built for iOS 18.
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "18.0"
    XCODE_ATTRIBUTE_MARKETING_VERSION "${PROJECT_VERSION}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${MCLA_APP_BUNDLE_ID}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
)
