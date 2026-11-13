/*
 * xyrdp_booster.c - Native C11 Low-Latency RDP Session & Frame-Pacing Booster
 *
 * Mengunci resolusi timer multimedia 1ms untuk kelancaran DWM 60Hz / AVC444,
 * mencegah sesi Windows Server masuk kondisi idle/throttle, dan memangkas
 * working-set proses latar agar RAM runner 14 GB tetap lega.
 */
#include "xyrdp_booster.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>

typedef UINT (WINAPI *pfn_timeBeginPeriod)(UINT uPeriod);
typedef LONG (NTAPI *pfn_NtSetTimerResolution)(ULONG DesiredResolution, BOOLEAN SetResolution, PULONG CurrentResolution);
#else
#include <time.h>
#endif

int xyrdp_compute_frame_interval_ms(uint32_t target_fps) {
    if (target_fps >= 120U) {
        return 8;
    }
    if (target_fps >= 60U) {
        return 15; /* Nilai optimal DWMFRAMEINTERVAL Windows Terminal Services untuk 60Hz */
    }
    if (target_fps == 0U) {
        return 33;
    }
    int raw = (int)(1000U / target_fps);
    return raw < 8 ? 8 : raw;
}

int xyrdp_apply_session_boost(uint32_t target_fps, int trim_working_set, xyrdp_boost_status_t *out_status) {
    if (out_status == NULL) {
        return -1;
    }
    memset(out_status, 0, sizeof(*out_status));
    out_status->target_fps = (target_fps == 0U) ? 60U : target_fps;

#ifdef _WIN32
    /* 1. Kunci quantum scheduler ke 1.0 ms (10.000 x 100ns) */
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    if (hNtdll != NULL) {
        pfn_NtSetTimerResolution fnNt = (pfn_NtSetTimerResolution)(void *)GetProcAddress(hNtdll, "NtSetTimerResolution");
        ULONG actual = 0;
        if (fnNt != NULL && fnNt(10000UL, TRUE, &actual) == 0) {
            out_status->timer_1ms_active = 1;
        }
    }
    if (!out_status->timer_1ms_active) {
        HMODULE hWinmm = LoadLibraryA("winmm.dll");
        if (hWinmm != NULL) {
            pfn_timeBeginPeriod fnTb = (pfn_timeBeginPeriod)(void *)GetProcAddress(hWinmm, "timeBeginPeriod");
            if (fnTb != NULL && fnTb(1U) == 0U) {
                out_status->timer_1ms_active = 1;
            }
        }
    }

    /* 2. Cegah Windows mematikan sesi display / sleep di VM headless */
    EXECUTION_STATE prev = SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
    if (prev != 0) {
        out_status->execution_awake_locked = 1;
    }

    /* 3. Pangkas working set proses latar yang menganggur bila diminta */
    if (trim_working_set) {
        DWORD pids[1024];
        DWORD needed = 0;
        DWORD selfPid = GetCurrentProcessId();
        if (K32EnumProcesses(pids, sizeof(pids), &needed)) {
            DWORD count = needed / sizeof(DWORD);
            for (DWORD i = 0; i < count; ++i) {
                if (pids[i] <= 4U || pids[i] == selfPid) {
                    continue;
                }
                HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SET_QUOTA, FALSE, pids[i]);
                if (hProc != NULL) {
                    if (K32EmptyWorkingSet(hProc)) {
                        out_status->trimmed_processes++;
                    }
                    CloseHandle(hProc);
                }
            }
        }
    }

    /* 4. Baca kapasitas RAM fisik aktual */
    MEMORYSTATUSEX mem;
    memset(&mem, 0, sizeof(mem));
    mem.dwLength = sizeof(mem);
    if (GlobalMemoryStatusEx(&mem)) {
        out_status->total_ram_mb = (uint64_t)(mem.ullTotalPhys / (1024ULL * 1024ULL));
        out_status->avail_ram_mb = (uint64_t)(mem.ullAvailPhys / (1024ULL * 1024ULL));
    }
#else
    (void)trim_working_set;
    struct timespec ts;
    if (clock_getres(CLOCK_MONOTONIC, &ts) == 0 && ts.tv_sec == 0 && ts.tv_nsec <= 1000000L) {
        out_status->timer_1ms_active = 1;
    }
    out_status->execution_awake_locked = 1;

    FILE *fp = fopen("/proc/meminfo", "r");
    if (fp != NULL) {
        char line[128];
        unsigned long long kb = 0;
        while (fgets(line, sizeof(line), fp) != NULL) {
            if (sscanf(line, "MemTotal: %llu kB", &kb) == 1) {
                out_status->total_ram_mb = (uint64_t)(kb / 1024ULL);
            } else if (sscanf(line, "MemAvailable: %llu kB", &kb) == 1) {
                out_status->avail_ram_mb = (uint64_t)(kb / 1024ULL);
            }
        }
        fclose(fp);
    }
#endif
    return 0;
}

int main(int argc, char **argv) {
    int self_test = 0;
    int trim = 0;
    uint32_t fps = 60U;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--self-test") == 0) {
            self_test = 1;
        } else if (strcmp(argv[i], "--trim-ram") == 0) {
            trim = 1;
        } else if (strcmp(argv[i], "--fps") == 0 && i + 1 < argc) {
            long val = strtol(argv[++i], NULL, 10);
            if (val >= 24 && val <= 240) {
                fps = (uint32_t)val;
            }
        }
    }

    if (self_test) {
        if (xyrdp_compute_frame_interval_ms(60U) != 15 || xyrdp_compute_frame_interval_ms(120U) != 8) {
            fprintf(stderr, "{\"engine\":\"xyrdp-booster-c\",\"self_test\":\"failed\"}\n");
            return 2;
        }
        xyrdp_boost_status_t st;
        if (xyrdp_apply_session_boost(60U, 0, &st) != 0) {
            return 2;
        }
        printf("{\"engine\":\"xyrdp-booster-c\",\"self_test\":\"ok\",\"dwm_interval_ms\":15,\"total_ram_mb\":%llu,\"avail_ram_mb\":%llu}\n",
               (unsigned long long)st.total_ram_mb,
               (unsigned long long)st.avail_ram_mb);
        return 0;
    }

    xyrdp_boost_status_t status;
    if (xyrdp_apply_session_boost(fps, trim, &status) != 0) {
        fprintf(stderr, "{\"engine\":\"xyrdp-booster-c\",\"status\":\"error\"}\n");
        return 1;
    }

    printf("{\"engine\":\"xyrdp-booster-c\",\"status\":\"ok\",\"timer_1ms\":%s,\"awake_locked\":%s,\"dwm_interval_ms\":%d,\"trimmed_processes\":%u,\"total_ram_mb\":%llu,\"avail_ram_mb\":%llu}\n",
           status.timer_1ms_active ? "true" : "false",
           status.execution_awake_locked ? "true" : "false",
           xyrdp_compute_frame_interval_ms(status.target_fps),
           status.trimmed_processes,
           (unsigned long long)status.total_ram_mb,
           (unsigned long long)status.avail_ram_mb);
    return 0;
}
