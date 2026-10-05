#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { MCLA_HOST_BRIDGE_ABI_VERSION = 2 };

typedef struct MCLADataReport {
    bool ready;
    uint32_t presentFiles;
    uint32_t requiredFiles;
    char detail[256];
} MCLADataReport;

typedef struct MCLARuntimeReport {
    bool available;
    bool running;
    bool finished;
    bool entryReached;
    bool failed;
    char detail[256];
} MCLARuntimeReport;

uint32_t MCLAHostBridgeVersion(void);
bool MCLAHostInspectGameData(const char* rootPath, MCLADataReport* report);
bool MCLAHostStartRuntime(const char* rootPath, char* errorMessage, uint32_t errorMessageSize);
void MCLAHostGetRuntimeReport(MCLARuntimeReport* report);

#ifdef __cplusplus
}
#endif
