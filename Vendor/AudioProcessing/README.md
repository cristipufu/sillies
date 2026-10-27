# Local echo cancellation

This package statically builds WebRTC AudioProcessing (AEC3). It contains no device capture, playback, networking, model downloads, or runtime build tools. Only the C bridge is public. The explicit source list follows upstream production Meson/CMake manifests; architecture-specific assembly/AVX/SSE/NEON implementations are excluded in favor of portable scalar code. Upstream source files are unmodified. DSP is optimized in debug builds too, so audio deadlines remain realistic.

Sources:
- webrtc-audio-processing 2.1: https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-2.1.tar.xz
  SHA-256: ae9302824b2038d394f10213cab05312c564a038434269f11dbf68f511f9f9fe
- Abseil 20240722.0: https://github.com/abseil/abseil-cpp/releases/download/20240722.0/abseil-cpp-20240722.0.tar.gz
  SHA-256: f50e5ac311a81382da7fa75b97310e4b9006474f9560ac46f54a9967f07d4ae3

Headers and production sources are retained for offline, reproducible SwiftPM builds. Licenses and the WebRTC patent grant are adjacent; embedded third-party license notices are retained in source. No upstream tests or executable utilities are built. Changes to the bridge must preserve the 16 kHz mono, 10 ms frame contract, error propagation, and device-independent processing.

For updates, verify upstream archive hashes, refresh the production source lists against Meson/CMake, preserve license notices, and run the echo/double-talk regressions plus `make check` and the real speech-model interaction check.
