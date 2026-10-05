#pragma once

namespace rex::ui::vulkan {
class VulkanDevice;
class VulkanPresenter;
}

// Builds ReXGlue's production Vulkan device and presenter on the CAMetalLayer
// owned by MCLAApp. MoltenVK is the Apple transport only; guest GPU behavior
// remains in the generic Xenos command processor.
bool MCLAVulkanDeviceGate();
rex::ui::vulkan::VulkanDevice* MCLAVulkanDevice();
rex::ui::vulkan::VulkanPresenter* MCLAVulkanPresenter();
void MCLAVulkanDeviceShutdown();
