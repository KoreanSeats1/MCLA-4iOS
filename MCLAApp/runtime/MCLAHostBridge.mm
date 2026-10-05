#include "MCLAHostBridge.h"

#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstring>

#if MCLA_RUNTIME_ENABLED
#include "MCLANativeTitleBridge.h"
#include "MCLARuntimeBootstrap.h"
#endif

namespace {

constexpr const char* kRequiredFiles[] = {
    "default.xex",
    "xarchive_audio.rpf",
    "xarchive_audlo.rpf",
    "xarchive_cache.rpf",
    "xarchive_music.rpf",
};

void CopyMessage(char* destination, size_t destinationSize, const char* message) {
    if (!destination || destinationSize == 0) {
        return;
    }
    std::snprintf(destination, destinationSize, "%s", message ? message : "");
}

}  // namespace

uint32_t MCLAHostBridgeVersion(void) {
    return MCLA_HOST_BRIDGE_ABI_VERSION;
}

bool MCLAHostInspectGameData(const char* rootPath, MCLADataReport* report) {
    if (!report) {
        return false;
    }

    std::memset(report, 0, sizeof(*report));
    report->requiredFiles = static_cast<uint32_t>(
        sizeof(kRequiredFiles) / sizeof(kRequiredFiles[0]));

    if (!rootPath || rootPath[0] == '\0') {
        CopyMessage(report->detail, sizeof(report->detail), "No game-data path was supplied.");
        return false;
    }

    NSString* root = [NSString stringWithUTF8String:rootPath];
    NSFileManager* files = NSFileManager.defaultManager;
    NSMutableArray<NSString*>* missing = [NSMutableArray array];

    for (const char* required : kRequiredFiles) {
        NSString* name = [NSString stringWithUTF8String:required];
        NSString* path = [root stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if ([files fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
            ++report->presentFiles;
        } else {
            [missing addObject:name];
        }
    }

    report->ready = missing.count == 0;
    if (report->ready) {
        CopyMessage(report->detail, sizeof(report->detail), "Complete Edition data set detected.");
    } else {
        NSString* message = [NSString stringWithFormat:@"Missing: %@",
            [missing componentsJoinedByString:@", "]];
        CopyMessage(report->detail, sizeof(report->detail), message.UTF8String);
    }
    return report->ready;
}

bool MCLAHostStartRuntime(const char* rootPath, char* errorMessage, uint32_t errorMessageSize) {
#if MCLA_RUNTIME_ENABLED
    NSString* metadataPath = [NSBundle.mainBundle
        pathForResource:@"mcla_vertex_elements" ofType:@"map"];
    if (!metadataPath || !MCLANativeTitleBridgeSetMetadataPath(
                             metadataPath.fileSystemRepresentation)) {
        CopyMessage(errorMessage, errorMessageSize,
                    "The MCLA native vertex metadata map is missing or invalid.");
        return false;
    }
    NSString* shaderPackPath = [NSBundle.mainBundle
        pathForResource:@"mcla_native_shaders" ofType:@"mspv"];
    if (!shaderPackPath || !MCLANativeTitleBridgeSetShaderPackPath(
                               shaderPackPath.fileSystemRepresentation)) {
        CopyMessage(errorMessage, errorMessageSize,
                    "The MCLA native SPIR-V shader pack is missing or invalid.");
        return false;
    }
    NSArray<NSString*>* supportDirectories = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString* support = [supportDirectories.firstObject
        stringByAppendingPathComponent:@"MCLA"];
    return MCLAStartRuntimeBackend(rootPath, support.fileSystemRepresentation,
                                   errorMessage, errorMessageSize);
#else
    (void)rootPath;
    CopyMessage(errorMessage, errorMessageSize,
        "This is the host-shell build; the MCLA AOT runtime is not linked yet.");
#endif
    return false;
}

void MCLAHostGetRuntimeReport(MCLARuntimeReport* report) {
    if (!report) {
        return;
    }
    std::memset(report, 0, sizeof(*report));
#if MCLA_RUNTIME_ENABLED
    report->available = true;
    MCLAGetRuntimeBackendStatus(report->detail, sizeof(report->detail),
                                &report->running, &report->finished,
                                &report->entryReached, &report->failed);
#else
    CopyMessage(report->detail, sizeof(report->detail),
                "MCLA AOT runtime is not linked in this build.");
#endif
}

#if !MCLA_RUNTIME_ENABLED
// The menu-only simulator has no guest input consumer. Keep UIKit's control
// callbacks linkable so all settings can still be previewed without the AOT.
#include "MCLABootstrapSubsystems.h"
void MCLASetVirtualGamepadButton(uint16_t, bool) {}
void MCLASetVirtualGamepadTrigger(bool, bool) {}
void MCLASetVirtualGamepadLeftStick(float, float, bool) {}
void MCLASetVirtualGamepadRightStick(float, float, bool) {}
void MCLASetVirtualGamepadTilt(float, bool) {}
uint64_t MCLAVirtualGamepadButtonEdgeCount() { return 0; }
void MCLAResetVirtualGamepad() {}
#endif
