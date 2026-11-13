// xyrdp_grafis_check.hpp - Native C++17 DirectX, Mesa3D OpenGL 4.6 & Studio Readiness Inspector
// Founder: xykal (Haekal Saputra) · Tim XyVerse · Indonesia
#ifndef XYRDP_GRAFIS_CHECK_HPP
#define XYRDP_GRAFIS_CHECK_HPP

#include <string>
#include <vector>

namespace xyrdp {

struct ModuleCheck {
    std::string name;
    std::string path;
    bool present;
};

struct GraphicsAuditReport {
    bool directx_modern_ready;
    bool directx_legacy_ready;
    bool mesa_opengl46_ready;
    bool blender_ready;
    bool roblox_studio_ready;
    bool winrar_ready;
    int dwm_frame_interval_ms;
    std::vector<ModuleCheck> modules;

    std::string to_json() const;
};

GraphicsAuditReport run_graphics_audit(const std::string &system_root_override = "");

} // namespace xyrdp

#endif // XYRDP_GRAFIS_CHECK_HPP
