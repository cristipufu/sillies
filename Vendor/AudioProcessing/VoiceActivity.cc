#include "include/VoiceActivity.h"
#include "common_audio/vad/include/webrtc_vad.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <new>

namespace {
constexpr int kSampleRate = 16000;
constexpr size_t kFrameSamples = 160;
constexpr int kAggressiveness = 2;
constexpr float kPCMScale = 32767.0f;
}
struct SilliesVoiceActivity { VadInst *vad; };

SilliesVoiceActivity *sillies_vad_create(void) {
  auto *state = new (std::nothrow) SilliesVoiceActivity{nullptr};
  if (!state) return nullptr;
  state->vad = WebRtcVad_Create();
  if (!state->vad || WebRtcVad_Init(state->vad) != 0 ||
      WebRtcVad_set_mode(state->vad, kAggressiveness) != 0) {
    sillies_vad_destroy(state);
    return nullptr;
  }
  return state;
}
void sillies_vad_destroy(SilliesVoiceActivity *state) {
  if (!state) return;
  if (state->vad) WebRtcVad_Free(state->vad);
  delete state;
}
int sillies_vad_process(SilliesVoiceActivity *state, const float *samples, size_t count) {
  if (!state || !samples || count != kFrameSamples) return -1;
  std::array<int16_t, kFrameSamples> pcm{};
  for (size_t i = 0; i < count; ++i) {
    if (!std::isfinite(samples[i])) return -1;
    pcm[i] = static_cast<int16_t>(std::clamp(samples[i], -1.0f, 1.0f) * kPCMScale);
  }
  return WebRtcVad_Process(state->vad, kSampleRate, pcm.data(), pcm.size());
}
