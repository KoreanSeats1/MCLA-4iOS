#include "pch.h"
#include "shader_recompiler.h"
#include <fstream>
#include <iostream>
#include <iterator>

static std::string Read(const char* path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error(std::string("Cannot read ") + path);
    return {std::istreambuf_iterator<char>(stream), {}};
}

int main(int argc, char** argv) {
    try {
        if (argc != 4 && !(argc == 5 && std::string(argv[4]) == "--legacy")) {
            std::cerr << "usage: mcla-xenosrecomp container.bin output.hlsl common.h [--legacy]\n";
            return 2;
        }
        auto input = Read(argv[1]);
        auto common = Read(argv[3]);
        if (input.size() < sizeof(ShaderContainer)) return 3;
        const auto* header = reinterpret_cast<const ShaderContainer*>(input.data());
        if (uint64_t(header->virtualSize) + uint64_t(header->physicalSize) > input.size() ||
            uint64_t(header->shaderOffset) + sizeof(Shader) > uint64_t(header->virtualSize))
            return 3;
        ShaderRecompiler compiler;
        compiler.preserveParallelAluSources = argc == 4;
        compiler.recompile(reinterpret_cast<const uint8_t*>(input.data()), common);
        std::ofstream output(argv[2], std::ios::binary);
        output << compiler.out;
        return output ? 0 : 4;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
