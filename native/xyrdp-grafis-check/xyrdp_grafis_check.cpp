// xyrdp_grafis_check.cpp - Native C++17 DirectX, Mesa3D OpenGL 4.6 & Studio Readiness Inspector
// Memeriksa kesiapan DLL Direct3D 11/12, DirectX Juni 2010, Mesa3D llvmpipe OpenGL 4.6,
// serta aplikasi kreatif & utilitas (Blender 3D, Roblox Studio, WinRAR) pada sesi XyRDP.

#include "xyrdp_grafis_check.hpp"

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <sstream>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

namespace fs = std::filesystem;

namespace xyrdp {
namespace {

std::string json_escape(const std::string &src) {
    std::ostringstream oss;
    for (unsigned char c : src) {
        switch (c) {
            case '"':  oss << "\\\""; break;
            case '\\': oss << "\\\\"; break;
            case '\n': oss << "\\n"; break;
            case '\r': oss << "\\r"; break;
            case '\t': oss << "\\t"; break;
            default:
                if (c < 0x20) {
                    oss << "\\u00" << "0123456789abcdef"[(c >> 4) & 0xF] << "0123456789abcdef"[c & 0xF];
                } else {
                    oss << static_cast<char>(c);
                }
        }
    }
    return oss.str();
}

bool exists_safe(const fs::path &p) {
    std::error_code ec;
    return fs::exists(p, ec) && !ec;
}

bool find_any(const std::vector<fs::path> &candidates, std::string &matched_out) {
    for (const auto &p : candidates) {
        if (exists_safe(p)) {
            matched_out = p.string();
            return true;
        }
    }
    matched_out = candidates.empty() ? "" : candidates.front().string();
    return false;
}

int read_dwm_interval_ms() {
#ifdef _WIN32
    HKEY hKey = nullptr;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
                      "SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations",
                      0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        DWORD val = 0;
        DWORD sz = sizeof(val);
        DWORD type = 0;
        LONG rc = RegQueryValueExA(hKey, "DWMFRAMEINTERVAL", nullptr, &type, reinterpret_cast<LPBYTE>(&val), &sz);
        RegCloseKey(hKey);
        if (rc == ERROR_SUCCESS && type == REG_DWORD) {
            return static_cast<int>(val);
        }
    }
#endif
    return 15;
}

} // namespace

GraphicsAuditReport run_graphics_audit(const std::string &system_root_override) {
    GraphicsAuditReport rep{};
    const char *env_win = std::getenv("SystemRoot");
    fs::path win_dir = !system_root_override.empty()
        ? fs::path(system_root_override)
        : fs::path(env_win != nullptr ? env_win : "C:\\Windows");
    fs::path sys32 = win_dir / "System32";

    auto check_sys32 = [&](const std::string &dll) -> bool {
        fs::path target = sys32 / dll;
        bool ok = exists_safe(target);
        rep.modules.push_back(ModuleCheck{dll, target.string(), ok});
        return ok;
    };

    bool d3d11 = check_sys32("d3d11.dll");
    bool d3d12 = check_sys32("d3d12.dll");
    bool dxgi  = check_sys32("dxgi.dll");
    rep.directx_modern_ready = d3d11 && d3d12 && dxgi;

    bool dx9_43   = check_sys32("d3dx9_43.dll");
    bool d3dc_43  = check_sys32("d3dcompiler_43.dll");
    bool xinput13 = check_sys32("xinput1_3.dll");
    rep.directx_legacy_ready = dx9_43 && d3dc_43 && xinput13;

    std::string mesa_match;
    rep.mesa_opengl46_ready = find_any({
        "C:\\XyRDP\\grafis\\mesa-x64\\opengl32.dll",
        "C:\\Program Files\\Mesa3D\\opengl32.dll"
    }, mesa_match);
    rep.modules.push_back(ModuleCheck{"mesa_opengl46", mesa_match, rep.mesa_opengl46_ready});

    std::string blender_match;
    rep.blender_ready = find_any({
        "C:\\Studio\\Blender\\blender-4.2.3-windows-x64\\blender.exe",
        "C:\\Studio\\Blender\\blender.exe",
        "C:\\Games\\Blender\\blender-4.2.3-windows-x64\\blender.exe",
        "C:\\Program Files\\Blender Foundation\\Blender 4.2\\blender.exe"
    }, blender_match);
    rep.modules.push_back(ModuleCheck{"blender_3d", blender_match, rep.blender_ready});

    std::string studio_match;
    rep.roblox_studio_ready = find_any({
        "C:\\Studio\\RobloxStudio\\RobloxStudioBeta.exe",
        "C:\\Games\\Roblox\\Studio\\RobloxStudioBeta.exe"
    }, studio_match);
    rep.modules.push_back(ModuleCheck{"roblox_studio", studio_match, rep.roblox_studio_ready});

    std::string winrar_match;
    rep.winrar_ready = find_any({
        "C:\\Program Files\\WinRAR\\WinRAR.exe",
        "C:\\Program Files (x86)\\WinRAR\\WinRAR.exe"
    }, winrar_match);
    rep.modules.push_back(ModuleCheck{"winrar", winrar_match, rep.winrar_ready});

    rep.dwm_frame_interval_ms = read_dwm_interval_ms();
    return rep;
}

std::string GraphicsAuditReport::to_json() const {
    std::ostringstream oss;
    oss << "{"
        << "\"engine\":\"xyrdp-grafis-check-cpp17\","
        << "\"directx_modern_ready\":" << (directx_modern_ready ? "true" : "false") << ","
        << "\"directx_legacy_ready\":" << (directx_legacy_ready ? "true" : "false") << ","
        << "\"mesa_opengl46_ready\":" << (mesa_opengl46_ready ? "true" : "false") << ","
        << "\"blender_ready\":" << (blender_ready ? "true" : "false") << ","
        << "\"roblox_studio_ready\":" << (roblox_studio_ready ? "true" : "false") << ","
        << "\"winrar_ready\":" << (winrar_ready ? "true" : "false") << ","
        << "\"dwm_frame_interval_ms\":" << dwm_frame_interval_ms << ","
        << "\"modules\":[";
    for (std::size_t i = 0; i < modules.size(); ++i) {
        if (i > 0) {
            oss << ",";
        }
        oss << "{\"name\":\"" << json_escape(modules[i].name)
            << "\",\"path\":\"" << json_escape(modules[i].path)
            << "\",\"present\":" << (modules[i].present ? "true" : "false") << "}";
    }
    oss << "]}";
    return oss.str();
}

} // namespace xyrdp

int main(int argc, char **argv) {
    bool self_test = false;
    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--self-test") {
            self_test = true;
        }
    }

    if (self_test) {
        fs::path temp_root = fs::temp_directory_path() / "xyrdp_cpp_selftest";
        fs::path sys32 = temp_root / "System32";
        std::error_code ec;
        fs::create_directories(sys32, ec);
        for (const char *dll : {"d3d11.dll", "d3d12.dll", "dxgi.dll", "d3dx9_43.dll", "d3dcompiler_43.dll", "xinput1_3.dll"}) {
            FILE *f = std::fopen((sys32 / dll).string().c_str(), "wb");
            if (f != nullptr) {
                std::fclose(f);
            }
        }
        auto rep = xyrdp::run_graphics_audit(temp_root.string());
        fs::remove_all(temp_root, ec);
        if (!rep.directx_modern_ready || !rep.directx_legacy_ready) {
            std::cerr << "{\"engine\":\"xyrdp-grafis-check-cpp17\",\"self_test\":\"failed\"}\n";
            return 2;
        }
        std::cout << "{\"engine\":\"xyrdp-grafis-check-cpp17\",\"self_test\":\"ok\",\"verified_dlls\":6}\n";
        return 0;
    }

    auto report = xyrdp::run_graphics_audit();
    std::cout << report.to_json() << "\n";
    return 0;
}
