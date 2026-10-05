#pragma once

#include <memory>

namespace rex::system {
class IGraphicsSystem;
}

// Creates MCLA's generic Xenos emulation service. This is the title-neutral
// PM4/Vulkan path, hosted by MCLA's own UIKit and CAMetalLayer lifecycle. It is
// the correctness fallback and must not be reported as the title-native MCLA
// renderer.
std::unique_ptr<rex::system::IGraphicsSystem> MCLACreateXenosGraphics();
