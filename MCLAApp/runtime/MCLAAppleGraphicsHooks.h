#pragma once

#include <cstdint>

struct MCLAAppleGraphicsHookReport {
    uint64_t drawIndexed = 0;
    uint64_t draw = 0;
    uint64_t beginVertices = 0;
    uint64_t endVertices = 0;
    uint64_t beginTiling = 0;
    uint64_t endTiling = 0;
    uint64_t resolves = 0;
    uint64_t frameEnds = 0;
    uint64_t swaps = 0;
    uint64_t clears = 0;
    uint64_t idleBypasses = 0;
    uint64_t nativePresents = 0;
    uint32_t inlinePrimitive = 0;
    uint32_t inlineVertexCount = 0;
    uint32_t inlineStride = 0;
    uint32_t inlineBuffer = 0;
    uint32_t inlineWords[4] = {};
    uint32_t inlineChecksum = 0;
    const char* lastHook = nullptr;
};

void MCLAGetAppleGraphicsHookReport(MCLAAppleGraphicsHookReport* report);
