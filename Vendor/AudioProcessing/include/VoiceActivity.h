#ifndef SILLIES_VOICE_ACTIVITY_H
#define SILLIES_VOICE_ACTIVITY_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct SilliesVoiceActivity SilliesVoiceActivity;
SilliesVoiceActivity *sillies_vad_create(void);
void sillies_vad_destroy(SilliesVoiceActivity *state);
// Mono Float32, 16 kHz, 160 samples. Returns speech (1), silence (0), or failure (-1).
int sillies_vad_process(SilliesVoiceActivity *state, const float *samples, size_t count);
#ifdef __cplusplus
}
#endif
#endif
