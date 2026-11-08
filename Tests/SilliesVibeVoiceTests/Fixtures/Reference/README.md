# VibeVoice reference outputs

These small test fixtures come from Microsoft's published components, using Float32 PyTorch inference
and independently dequantized, pinned 8-bit weights. They are test data, not models or app resources.
`provenance.json` records model/source revisions, package versions, dimensions and artifact hashes.

The stage fixtures use Emma's voice state. The complete Carter utterance uses the exact MLX seed-one
normal-noise sequence replayed through the reference transformer, diffusion head and streaming codec.
This checks the entire interleaved generation sequence and its stopping frame, not just isolated layers.
The observed native/reference relative RMS error is about 0.000107; the regression requires less
than 0.001 and identical sample counts. The test does not score speech naturalness or word accuracy.

Run the opt-in tests with the pinned model directory in `SILLIES_VIBEVOICE_MODEL`. Reference data is
bundled with the tests; neither Python nor a reference runtime is needed to execute them. Ordinary
checks skip model-dependent tests and never download weights or open an audio device.

Sources and notices: [Microsoft VibeVoice](https://github.com/microsoft/VibeVoice/tree/16fb2cb1217c9934a886e1948ffb06120caa2df5),
[8-bit weights](https://huggingface.co/mlx-community/VibeVoice-Realtime-0.5B-8bit/tree/ae6a233e1b2d6d5e2315e7030581323cc8191bb3),
[third-party notices](../../../../THIRD_PARTY_NOTICES.md).
