#include "include/EchoCancellation.h"
#include "api/audio/audio_processing.h"
#include <array>
#include <new>

namespace {
constexpr int kSampleRate = 16000;
constexpr int kChannels = 1;
constexpr int kFrameSamples = kSampleRate / 100;
}

struct SilliesEchoCanceller {
  rtc::scoped_refptr<webrtc::AudioProcessing> processor;
  webrtc::StreamConfig format{kSampleRate, kChannels};
  std::array<float, kFrameSamples> reverse_output{};
};

SilliesEchoCanceller *sillies_echo_create(void) {
  auto *state = new (std::nothrow) SilliesEchoCanceller;
  if (!state) return nullptr;
  state->processor = webrtc::AudioProcessingBuilder().Create();
  if (!state->processor) { delete state; return nullptr; }
  webrtc::AudioProcessing::Config config;
  config.echo_canceller.enabled = true;
  config.echo_canceller.mobile_mode = false;  // AEC3 with internal delay estimation.
  config.echo_canceller.enforce_high_pass_filtering = false;
  config.high_pass_filter.enabled = false;
  config.gain_controller1.enabled = false;
  config.gain_controller2.enabled = false;
  config.noise_suppression.enabled = false;
  state->processor->ApplyConfig(config);
  if (sillies_echo_reset(state) != 0) { delete state; return nullptr; }
  return state;
}

void sillies_echo_destroy(SilliesEchoCanceller *state) { delete state; }

int sillies_echo_reset(SilliesEchoCanceller *state) {
  if (!state) return -1;
  const webrtc::ProcessingConfig configuration{
    {state->format, state->format, state->format, state->format}};
  return state->processor->Initialize(configuration);
}

int sillies_echo_process(SilliesEchoCanceller *state, const float *reference,
                        const float *microphone, float *cleaned) {
  if (!state || !reference || !microphone || !cleaned) return -1;
  const float *render[] = {reference};
  float *reverse_output[] = {state->reverse_output.data()};
  int status = state->processor->ProcessReverseStream(
    render, state->format, state->format, reverse_output);
  if (status != 0) return status;
  const float *capture[] = {microphone};
  float *output[] = {cleaned};
  state->processor->set_stream_delay_ms(0);
  return state->processor->ProcessStream(capture, state->format, state->format, output);
}
