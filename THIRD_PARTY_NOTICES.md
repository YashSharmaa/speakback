# Third-party notices

speakback is MIT licensed (see [LICENSE](LICENSE)). It links or downloads the works below, all under permissive
licences. Model weights are downloaded from Hugging Face on first run and are not redistributed in this repository
or in the installed binary.

## Linked into the `speak` binary

| Component | Version | Licence | Source |
| --- | --- | --- | --- |
| FluidAudio (Swift package; TTS and NemoTextProcessing traits) | 0.18.2 | Apache-2.0 | https://github.com/FluidInference/FluidAudio |
| NemoTextProcessing / text-processing-rs (prebuilt static library, via FluidAudio) | 0.3.1 | Apache-2.0 | https://github.com/FluidInference/text-processing-rs |

FluidAudio's own third-party notices are in its `ThirdPartyLicenses` folder and apply to the linked binary. Of
those, fastcluster (BSD-2-Clause) and VBx (Apache-2.0) belong to the diarizer, which speakback leaves out.

FluidAudio's `TTS` trait also builds a resource bundle, `FluidAudio_LuxTtsG2pResources.bundle`, holding LuxTTS
pronunciation data derived from espeak-ng (GPL-3.0-or-later) and FrequencyWords (CC-BY-SA-4.0). speakback never
uses LuxTTS, and neither `build.sh`, `install.sh` nor the Homebrew formula installs that bundle: only the `speak`
binary is installed.

## Downloaded at first run

| Component | Licence | Source |
| --- | --- | --- |
| Kokoro-82M v1.0 weights and voice packs (including `af_heart` and `hf_alpha`, used for the Indian-English blend) | Apache-2.0 | https://huggingface.co/hexgrad/Kokoro-82M |
| Kokoro-82M Core ML conversion, legacy runtime | Apache-2.0 | https://huggingface.co/FluidInference/kokoro-82m-coreml (derived from laishere/kokoro-coreml, used with permission) |
| Kokoro-82M Core ML conversion, ANE-v3 runtime (`SPEAK_KOKORO=v3`) | Apache-2.0 | https://huggingface.co/FluidInference/kokoro-82m-coreml (derived from mattmireles/kokoro-coreml, Apache-2.0) |
| English G2P model and Misaki pronunciation lexicon cache (FluidAudio's Kokoro frontend) | Apache-2.0 | https://huggingface.co/FluidInference/kokoro-82m-coreml, https://github.com/hexgrad/misaki |

## Other credits

- Voice grades shown by `speak --voices` come from `VOICES.md` in hexgrad/Kokoro-82M (Apache-2.0).
- The voice-blend weights, chunking and pause lengths follow public Kokoro guidance; no code was copied.
