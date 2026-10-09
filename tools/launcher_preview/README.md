# MCLA launcher visual and integration harness

This isolated simulator app uses the shipping `MCLALauncherView.mm`. It does
not contain the game runtime or read device saves. The optional integration
mode also links the shipping `MCLAViewController.mm` to explicit runtime stubs.

Compile with the iPhone Simulator SDK, ARC, arm64, and deployment target 18:

```
xcrun --sdk iphonesimulator clang++ -std=c++17 -fobjc-arc -arch arm64 \
  -mios-simulator-version-min=18.0 -I MCLAApp/ios \
  tools/launcher_preview/main.mm MCLAApp/ios/MCLALauncherView.mm \
  MCLAApp/ios/MCLALauncherSceneView.mm \
  -framework UIKit -framework SceneKit -framework Foundation \
  -framework QuartzCore -framework CoreGraphics -framework MetalKit -framework Metal \
  -o /private/tmp/mcla-launcher-preview.app/LauncherPreview
```

Create the temporary app directory first and copy this directory's Info.plist
into it. Install on an isolated simulator using `xcrun simctl install`.
`SIMCTL_CHILD_PREVIEW_LANDSCAPE=1` selects landscape; the default is portrait.
Stop the preview and shut down its simulator after collecting screenshots.

For the integration check, add `-DMCLA_LAUNCHER_INTEGRATION_TEST=1`,
`-I MCLAApp/runtime`, these sources:

- `tools/launcher_preview/integration.mm`
- `tools/launcher_preview/runtime_stubs.mm`
- `MCLAApp/ios/MCLAViewController.mm`

and the CoreMotion and GameController frameworks. Run with `simctl launch
--console`. The harness checks menu action routing, landscape before runtime
startup, release of SceneKit resources at gameplay, the installed three-touch
recognizer, hidden toolbar defaults, reveal, repeated-gesture timer renewal,
and automatic timeout. It prints `MCLA_LAUNCHER_UI_TEST PASS` and exits after
about 24 seconds. This is not a hardware controller or GPU-performance test.

The integration check also tests the car's center-lane position/heading,
continuity of camera motion across turnarounds, status polling not restarting
the animation clock, and the floating-point display format.

For a separate simulator HDR readback check, compile the visual harness with
`-DMCLA_LAUNCHER_HDR_TEST=1`. This test-only build uses a four-times-SDR
headroom and reads back the linear scene and presented Metal textures after
two seconds. It asserts finite radiance, values above 1.0 in both buffers,
and output bounded by the chosen headroom. This flag is never enabled in the
shipping CMake target. A simulator screenshot is SDR and cannot validate
physical OLED luminance. Neither this nor simulator cadence proves device
60-fps performance.

## Log export integration

The log-export test uses `log_export_integration.mm` instead of `integration.mm`, with the same integration flag, runtime stubs and production controller. Also link `MCLASaveArchive.mm`, `MCLALogArchive.mm`, UniformTypeIdentifiers and `-lz`; add `-I MCLAApp/runtime`. The stubs provide a synthetic failed runtime. The test checks that failure restores the Export Logs button, creates a ZIP even without detailed diagnostics, and opens the actual iOS share sheet. It prints `MCLA_LOG_EXPORT_UI_TEST PASS` and exits. It does not run the game or confirm a recipient signing configuration.
