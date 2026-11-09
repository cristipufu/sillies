#ifndef SILLIES_ECHO_CANCELLATION_H
#define SILLIES_ECHO_CANCELLATION_H
#ifdef __cplusplus
extern "C" {
#endif

typedef struct SilliesEchoCanceller SilliesEchoCanceller;
typedef struct SilliesEchoStatistics {
  double delay_ms;
  double return_loss_db;
  double reduction_db;
} SilliesEchoStatistics;
// Mono Float32, 16 kHz, exactly 160 samples per call. No audio devices are opened.
SilliesEchoCanceller *sillies_echo_create(void);
void sillies_echo_destroy(SilliesEchoCanceller *state);
int sillies_echo_reset(SilliesEchoCanceller *state);
int sillies_echo_process(SilliesEchoCanceller *state, const float *reference,
                        const float *microphone, float *cleaned);
// Unavailable statistics are NaN. This reads scalars only; no AEC audio dump is enabled.
int sillies_echo_statistics(SilliesEchoCanceller *state, SilliesEchoStatistics *statistics);
#ifdef __cplusplus
}
#endif
#endif
