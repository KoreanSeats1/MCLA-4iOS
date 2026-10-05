#pragma once

#include <cstddef>

// Internal C++ boundary used by the Objective-C host bridge. The public app
// API remains the versioned C surface in MCLAHostBridge.h.
bool MCLAStartRuntimeBackend(const char* gameRoot, const char* supportRoot,
                             char* errorMessage, std::size_t errorMessageSize);
void MCLAGetRuntimeBackendStatus(char* message, std::size_t messageSize,
                                 bool* running, bool* finished,
                                 bool* entryReached, bool* failed);

// Production GPU telemetry is published by the Xenos worker through the same
// app-container file used by the host UI and device-side bring-up scripts.
void MCLAPublishRuntimeGpuTelemetry(const char* telemetry);
