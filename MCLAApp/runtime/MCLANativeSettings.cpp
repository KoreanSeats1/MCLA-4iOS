#include <rex/cvar.h>
#include <rex/graphics/gta4_native/anti_aliasing_policy.h>
// Renderer configuration ABI shared with Theft4; MCLA owns these definitions.
// and pace the guest at the project's 30 FPS target.
REXCVAR_DEFINE_STRING(gta4_aspect_ratio, "16:9", "GTA IV/Graphics/Display",
                      "Render aspect ratio")
    .allowed({"auto", "original", "16:9", "16:10", "3:2", "4:3", "5:4", "21:9", "43:18", "32:9", "32:10"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_present_mode, "vsync", "GTA IV/Graphics/Display",
                      "Presentation mode")
    .allowed({"auto", "vsync", "mailbox", "immediate"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_UINT32(gta4_frame_limit, 30, "GTA IV/Graphics/Display",
                      "Maximum guest frame rate")
    .allowed({"0", "30", "60", "120"});
REXCVAR_DEFINE_STRING(gta4_native_hdr_mode, "off", "GTA IV/Graphics/HDR", "HDR output mode")
    .allowed({"off", "scrgb", "auto_hdr"});
REXCVAR_DEFINE_BOOL(gta4_native_hdr_mode_unified, false,
                    "GTA IV/Graphics/HDR/Compatibility", "HDR compatibility state");
REXCVAR_DEFINE_DOUBLE(gta4_native_hdr_paper_white_nits, 203.0, "GTA IV/Graphics/HDR",
                      "SDR reference white brightness")
    .range(80.0, 500.0);
REXCVAR_DEFINE_DOUBLE(gta4_native_hdr_peak_nits, 400.0, "GTA IV/Graphics/HDR",
                      "Auto HDR highlight target")
    .range(80.0, 2000.0);
REXCVAR_DEFINE_DOUBLE(gta4_native_auto_hdr_shoulder_start, 0.0,
                      "GTA IV/Graphics/HDR/Advanced", "Auto HDR shoulder start")
    .range(0.0, 1.0);
REXCVAR_DEFINE_DOUBLE(gta4_native_auto_hdr_shoulder_power, 2.5,
                      "GTA IV/Graphics/HDR/Advanced", "Auto HDR shoulder exponent")
    .range(1.0, 10.0);
REXCVAR_DEFINE_UINT32(gta4_shadow_map_base_size, 256, "GTA IV/Graphics/Shadows",
                      "Base shadow-map size")
    .range(256, 1024)
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_DOUBLE(gta4_shadow_distance_scale, 1.0, "GTA IV/Graphics/Shadows",
                      "Directional shadow range multiplier")
    .range(1.0, 4.0)
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_reflection_resolution, "original", "GTA IV/Graphics/Reflections",
                      "Reflection resolution")
    .allowed({"original", "1080p", "full"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_reflection_resolution_cap, "1440p", "GTA IV/Graphics/Reflections",
                      "Maximum reflection resolution")
    .allowed({"1080p", "1440p", "display"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_mirror_reflection_resolution, "inherit",
                      "GTA IV/Graphics/Reflections/Advanced", "Mirror reflection resolution")
    .allowed({"inherit", "original", "1080p", "full"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_water_reflection_resolution, "inherit",
                      "GTA IV/Graphics/Reflections/Advanced", "Water reflection resolution")
    .allowed({"inherit", "original", "1080p", "full"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_environment_reflection_resolution, "inherit",
                      "GTA IV/Graphics/Reflections/Advanced", "Environment reflection resolution")
    .allowed({"inherit", "original", "1080p", "full"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_reflection_aa, "original", "GTA IV/Graphics/Reflections",
                      "Reflection anti-aliasing")
    .allowed({"original", "off", "2x", "4x"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_reflection_capture_distance, "original",
                      "GTA IV/Graphics/Reflections/Advanced", "Reflection capture distance")
    .allowed({"original", "extended", "far"});
REXCVAR_DEFINE_STRING(gta4_native_anti_aliasing, "off",
                      "GTA IV/Graphics/Anti-Aliasing", "Anti-aliasing mode")
    .allowed({"off", "fxaa", "smaa", "msaa2x", "msaa4x", "ssaa2x", "ssaa4x",
              "ssaa6x", "ssaa8x", "ssaa10x", "ssaa12x", "ssaa14x", "ssaa16x",
              "spatial"});
REXCVAR_DEFINE_BOOL(gta4_native_anti_aliasing_unified, false,
                    "GTA IV/Graphics/Anti-Aliasing/Compatibility",
                    "Unified anti-aliasing compatibility state");
REXCVAR_DEFINE_STRING(gta4_native_smaa_quality, "high",
                      "GTA IV/Graphics/Anti-Aliasing", "SMAA quality")
    .allowed({"low", "medium", "high", "ultra"});
REXCVAR_DEFINE_STRING(gta4_native_upscaler, "native", "GTA IV/Graphics/Upscaling",
                      "Output upscaler")
    .allowed({"native", "fsr1"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_STRING(gta4_fsr1_quality, "quality", "GTA IV/Graphics/Upscaling",
                      "FSR 1 quality")
    .allowed({"ultra_quality", "quality", "balanced", "performance"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_DOUBLE(gta4_fsr1_sharpness_reduction, 0.2, "GTA IV/Graphics/Upscaling",
                      "FSR 1 sharpness reduction")
    .range(0.0, 2.0)
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);
REXCVAR_DEFINE_BOOL(gta4_force_highest_lod, false, "GTA IV/Graphics/LOD",
                    "Prefer the highest resident model LOD");
REXCVAR_DEFINE_DOUBLE(gta4_draw_distance_scale, 1.0, "GTA IV/Graphics/LOD",
                      "World-distance multiplier")
    .range(1.0, 4.0);
REXCVAR_DEFINE_UINT32(gta4_drawable_reference_limit, 13000, "GTA IV/Graphics/LOD",
                      "Drawable-reference capacity")
    .range(13000, 40000)
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);

// GTA4App owns the mutable anti-aliasing controller on desktop. The iOS shell
// currently exposes a launch-time setting only, so resolving the configured
// mode directly is equivalent and keeps the renderer frontend-independent.
namespace rex::graphics::gta4_native {

AntiAliasingMode GetActiveAntiAliasingMode() {
  const auto configured = ParseAntiAliasingMode(
      REXCVAR_GET(gta4_native_anti_aliasing));
  return configured.value_or(AntiAliasingMode::kOff);
}

}  // namespace rex::graphics::gta4_native
