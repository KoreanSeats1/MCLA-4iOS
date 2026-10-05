#pragma once
#include <memory>
namespace rex::system { class IGraphicsSystem; }
std::unique_ptr<rex::system::IGraphicsSystem> MCLACreateHandwrittenMetalRenderer();
