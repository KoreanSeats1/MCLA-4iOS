#include "MCLAVulkanGate.h"

#include "MCLAGraphicsFoundation.h"

#include <dispatch/dispatch.h>
#include <pthread.h>

#include <memory>
#include <mutex>
#include <vector>

#include <rex/logging.h>
#include <rex/ui/surface.h>
#include <rex/ui/vulkan/device.h>
#include <rex/ui/vulkan/instance.h>
#include <rex/ui/vulkan/presenter.h>
#include <rex/ui/vulkan/ui_samplers.h>

namespace {

std::mutex gDeviceMutex;
std::unique_ptr<rex::ui::vulkan::VulkanInstance> gInstance;
std::unique_ptr<rex::ui::vulkan::VulkanDevice> gDevice;
std::unique_ptr<rex::ui::vulkan::UISamplers> gUISamplers;
std::unique_ptr<rex::ui::vulkan::VulkanPresenter> gPresenter;

class MCLAMetalLayerSurface final : public rex::ui::Surface {
 public:
    explicit MCLAMetalLayerSurface(void* layer) : layer_(layer) {}

    TypeIndex GetType() const override { return kTypeIndex_CAMetalLayer; }
    void* GetNativePresentationHandle() const override { return layer_; }

 protected:
    bool GetSizeImpl(uint32_t& width, uint32_t& height) const override {
        return MCLAGraphicsBoundLayerSize(&width, &height);
    }

 private:
    void* layer_ = nullptr;
};

std::unique_ptr<MCLAMetalLayerSurface> gSurface;

}  // namespace

bool MCLAVulkanDeviceGate() {
    std::lock_guard lock(gDeviceMutex);
    if (gDevice) {
        return true;
    }
    gInstance = rex::ui::vulkan::VulkanInstance::Create(true, false);
    if (!gInstance) {
        REXLOG_ERROR("MCLA VulkanInstance creation failed");
        return false;
    }

    std::vector<VkPhysicalDevice> physicalDevices;
    gInstance->EnumeratePhysicalDevices(physicalDevices);
    if (physicalDevices.empty()) {
        REXLOG_ERROR("MCLA VulkanInstance found no Apple GPU");
        gInstance.reset();
        return false;
    }

    gDevice = rex::ui::vulkan::VulkanDevice::CreateIfSupported(
        gInstance.get(), physicalDevices.front(), true, true);
    if (!gDevice) {
        REXLOG_ERROR("MCLA VulkanDevice rejected the Apple GPU");
        gInstance.reset();
        return false;
    }
    gUISamplers = rex::ui::vulkan::UISamplers::Create(gDevice.get());
    if (!gUISamplers) {
        REXLOG_ERROR("MCLA Vulkan UI sampler creation failed");
        gDevice.reset();
        gInstance.reset();
        return false;
    }
    gPresenter = rex::ui::vulkan::VulkanPresenter::Create(
        [](bool responsible, bool) {
            REXLOG_ERROR("MCLA Vulkan presenter reported GPU loss ({})",
                         responsible ? "responsible" : "external");
        },
        gDevice.get(), gUISamplers.get());
    if (!gPresenter) {
        REXLOG_ERROR("MCLA Vulkan presenter creation failed");
        gUISamplers.reset();
        gDevice.reset();
        gInstance.reset();
        return false;
    }

    void* layer = MCLAGraphicsBoundMetalLayer();
    if (!layer) {
        REXLOG_ERROR("MCLA Vulkan presenter has no bound CAMetalLayer");
        gPresenter.reset();
        gUISamplers.reset();
        gDevice.reset();
        gInstance.reset();
        return false;
    }
    gSurface = std::make_unique<MCLAMetalLayerSurface>(layer);
    auto attachSurface = [](void*) {
        gPresenter->SetWindowSurfaceFromUIThread(nullptr, gSurface.get());
    };
    if (pthread_main_np()) {
        attachSurface(nullptr);
    } else {
        dispatch_sync_f(dispatch_get_main_queue(), nullptr, attachSurface);
    }
    REXLOG_INFO("MCLA Vulkan device ready on '{}'", gDevice->properties().deviceName);
    REXLOG_INFO("MCLA Vulkan presenter attached to the UIKit CAMetalLayer");
    return true;
}

rex::ui::vulkan::VulkanDevice* MCLAVulkanDevice() {
    std::lock_guard lock(gDeviceMutex);
    return gDevice.get();
}

rex::ui::vulkan::VulkanPresenter* MCLAVulkanPresenter() {
    std::lock_guard lock(gDeviceMutex);
    return gPresenter.get();
}

void MCLAVulkanDeviceShutdown() {
    std::lock_guard lock(gDeviceMutex);
    if (gPresenter) {
        auto detachSurface = [](void*) {
            gPresenter->SetWindowSurfaceFromUIThread(nullptr, nullptr);
        };
        if (pthread_main_np()) {
            detachSurface(nullptr);
        } else {
            dispatch_sync_f(dispatch_get_main_queue(), nullptr, detachSurface);
        }
    }
    gPresenter.reset();
    gSurface.reset();
    gUISamplers.reset();
    gDevice.reset();
    gInstance.reset();
}
