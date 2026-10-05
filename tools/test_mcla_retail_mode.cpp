#include "../MCLAApp/runtime/MCLADiagnostics.h"
#include <rex/diagnostics/policy.h>
#include <cassert>
#include <string>

int main(int argc, char**) {
    using namespace rex::diagnostics;
    const bool diagnosticLaunch = argc > 1;
    assert(!mcla::DiagnosticsEnabled()); // Retail is the cold-launch default.
    mcla::SetDiagnosticsEnabled(diagnosticLaunch);
    std::string error;
    assert(Configure(mcla::DiagnosticsEnabled(), diagnosticLaunch
        ? "logging,vulkan,presenter,guest-hooks,watchdog" : "", &error));
    assert(IsEnabled() == diagnosticLaunch);
    assert(IsEnabled(Category::kLogging) == diagnosticLaunch);
    assert(IsEnabled(Category::kWatchdog) == diagnosticLaunch);
    if (!diagnosticLaunch) {
        for (size_t i = 0; i < static_cast<size_t>(Category::kCount); ++i)
            assert(!IsEnabled(static_cast<Category>(i)));
        // A config/environment request cannot turn diagnostics back on midgame.
        assert(!Configure(true, "logging", &error));
        assert(!IsEnabled(Category::kLogging));
    }
}
