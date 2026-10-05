cmake_minimum_required(VERSION 3.20)

project(mcla_shader_corpus LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(MCLA_WORKSPACE "${CMAKE_CURRENT_LIST_DIR}/../..")
set(MCLA_MODLOADER "${MCLA_WORKSPACE}/larecomp/src/mc_engine/modloader")
set(MCLA_MSPACK "${MCLA_WORKSPACE}/theft4-foundation/glue/rexglue-sdk-main/thirdparty/libmspack/libmspack/mspack")

add_executable(mcla_shader_corpus
    main.cpp
    "${MCLA_MODLOADER}/aes256.cpp"
    "${MCLA_MSPACK}/lzxd.c"
)

target_include_directories(mcla_shader_corpus PRIVATE
    "${MCLA_MODLOADER}"
    "${MCLA_MSPACK}"
)

target_compile_options(mcla_shader_corpus PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic>
)
