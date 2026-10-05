cmake_minimum_required(VERSION 3.25)

project(MCLAReXGlueHostTools LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(REXSDK_SOURCE_DIR
    "${CMAKE_CURRENT_LIST_DIR}/../../../theft4-foundation/glue/rexglue-sdk-main"
    CACHE PATH "Path to the isolated Theft4 ReXGlue SDK source tree")

if(NOT EXISTS "${REXSDK_SOURCE_DIR}/src/rexglue/main.cpp")
    message(FATAL_ERROR "ReXGlue source was not found at ${REXSDK_SOURCE_DIR}")
endif()

# These two targets normally live beneath the SDK's top-level directory and
# inherit this variable. The host-tools wrapper adds them afterward, so retain
# the same root explicitly in our directory scope.
set(REXGLUE_ROOT "${REXSDK_SOURCE_DIR}")

# The SDK's normal macOS build configures every graphics backend, including
# GTA-IV-native shader assets. Code generation needs none of that. Configure
# the supported headless core/runtime first, then add only the host codegen and
# CLI directories that the SDK deliberately skips in CORE_ONLY mode.
set(REXGLUE_CORE_ONLY ON CACHE BOOL "" FORCE)
set(REXGLUE_RUNTIME_ONLY ON CACHE BOOL "" FORCE)
set(REXGLUE_HEADLESS_KERNEL ON CACHE BOOL "" FORCE)
set(REXGLUE_HEADLESS_RENDER_AUDIO OFF CACHE BOOL "" FORCE)
set(REXGLUE_HEADLESS_XMA_DECODER OFF CACHE BOOL "" FORCE)
set(REXGLUE_HEADLESS_INPUT OFF CACHE BOOL "" FORCE)
set(REXGLUE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(REXGLUE_ENABLE_TRACY OFF CACHE BOOL "" FORCE)
set(REXGLUE_ENABLE_PERF_COUNTERS OFF CACHE BOOL "" FORCE)
set(REXGLUE_ENABLE_FIDELITYFX OFF CACHE BOOL "" FORCE)

add_subdirectory("${REXSDK_SOURCE_DIR}" rexglue-core)

if(NOT TARGET disasm)
    add_subdirectory("${REXSDK_SOURCE_DIR}/thirdparty/disasm" rexglue-disasm)
    target_compile_options(disasm PRIVATE -w)
endif()

add_subdirectory("${REXSDK_SOURCE_DIR}/src/codegen" rexglue-codegen)
add_subdirectory("${REXSDK_SOURCE_DIR}/src/rexglue" rexglue-cli)
