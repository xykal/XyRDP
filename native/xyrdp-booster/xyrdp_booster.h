/*
 * xyrdp_booster.h - Native C11 Low-Latency RDP Session & Frame-Pacing Booster
 * Founder: xykal (Haekal Saputra) · Tim XyVerse · Indonesia
 */
#ifndef XYRDP_BOOSTER_H
#define XYRDP_BOOSTER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int timer_1ms_active;
    int execution_awake_locked;
    uint32_t trimmed_processes;
    uint64_t total_ram_mb;
    uint64_t avail_ram_mb;
    uint32_t target_fps;
} xyrdp_boost_status_t;

int xyrdp_apply_session_boost(uint32_t target_fps, int trim_working_set, xyrdp_boost_status_t *out_status);
int xyrdp_compute_frame_interval_ms(uint32_t target_fps);

#ifdef __cplusplus
}
#endif

#endif /* XYRDP_BOOSTER_H */
