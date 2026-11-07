<p align="center"><img src="docs/icon.png" width="160" alt="speakback logo"></p>

# speakback

`speak` reads text aloud on your Mac with [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), running on
device through [FluidAudio](https://github.com/FluidInference/FluidAudio)'s Core ML pipeline. It is built for
coding agents and terminals: it cleans up markdown, code and numbers before speaking, starts talking in about
60 to 150 ms, and can teach Claude Code, Codex or OpenCode to read answers aloud when you ask.

Nothing leaves the machine after the one-time model download.

## Requirements

- An Apple Silicon Mac (M1 or later).
- macOS 14 or later.
- The Xcode command-line tools with Swift 6.2 or later (`xcode-select --install`).

## Install

With Homebrew:

```sh
brew tap YashSharmaa/tap && brew trust yashsharmaa/tap && brew install speakback
```

Or with the install script, which checks the Mac, builds from source and installs `~/.local/bin/speak`:

```sh
curl -fsSL https://raw.githubusercontent.com/YashSharmaa/speakback/main/install.sh | bash
```

From a checkout, `./build.sh` does the same. It signs with the first Apple Development identity in your keychain,
or ad hoc if there is none.

## Use

```sh
speak "The build passed."        # speaks, replacing anything already playing
speak --file notes.md            # markdown is cleaned up before speaking
git log -1 --format=%B | speak   # standard input
speak --out reply.wav "Hello."   # write a WAV instead of playing
speak --stop                     # stop at once
speak --speed 1.3 --voice bf_emma "Faster, British."
speak --voice indian "Namaste, the deploy is done."   # Indian-English blend
speak --voices                   # list voices
speak --status                   # server state, memory, model
speak --version
```

### Let your coding agent speak

```sh
speak install-skill --claude     # Claude Code skill: ~/.claude/skills/speak/SKILL.md
speak install-skill --codex      # a marked section in ~/.codex/AGENTS.md
speak install-skill --opencode   # OpenCode skill: ~/.config/opencode/skills/speak/SKILL.md
speak install-skill --deepseek   # DeepSeek-TUI skill: ~/.deepseek/skills/speak/SKILL.md
speak install-skill --gemini     # a marked section in ~/.gemini/GEMINI.md
speak install-skill --all        # every harness above
speak install-skill --print      # the instructions, for any other harness
speak install-skill --claude --uninstall
```

Then say "read that out", "read it aloud", "speak it to me", "say it out loud" or "I want to hear this". The agent
rewrites its answer as plain spoken prose (no markdown, code or URLs, numbers as you would say them, never a
secret), pipes it to `speak`, and keeps its chat reply short. "Stop" runs `speak --stop`.

- **Several Claude Code accounts:** set `CLAUDE_CONFIG_DIR`, or pass `--config-dir` once per folder:
  `speak install-skill --config-dir ~/.claude --config-dir ~/.claude-work`.
- **Codex** reads `$CODEX_HOME/AGENTS.md` (default `~/.codex`). If an `AGENTS.override.md` sits next to it, Codex
  reads that instead, and install-skill warns you.
- **OpenCode** also reads `~/.claude/skills`, so with the Claude Code skill installed it already works there.
- Running install-skill again updates the text in place, and `--uninstall` removes only what it wrote. The texts are
  in [`skills/`](skills).

## Models and disk space

The first run downloads the models from Hugging Face into `~/Library/Application Support/speak/models` and
compiles them (about 40 s, once):

| What | Size on disk |
| --- | --- |
| Kokoro-82M Core ML, legacy runtime (default), with vocab and `af_heart` | about 81 MB |
| English G2P model and pronunciation lexicon | about 11 MB |
| Each further voice (downloaded on first use) | about 0.5 MB |
| ANE-v3 runtime, only with `SPEAK_KOKORO=v3` | about 380 MB more |

After that, a cold start takes about 1.5 s.

## How it works

- **A warm server.** `speak` talks to `speak serve` over a Unix socket at
  `~/Library/Application Support/speak/speak.sock`, starting it if it is not running. The server keeps the model
  loaded, unloads it after 15 minutes without a request (it reloads in under a second), and exits after 30. Only
  one server runs per user.
- **Streaming.** Text is normalised, split into sentences and chunked. The first sentence is cut at its first
  comma past 35 characters, and the first chunk is held to about 4 s of speech, so audio starts quickly. Later
  chunks carry whole sentences. Each chunk goes to the player as soon as it is synthesised.
- **Gapless playback.** Chunks are scheduled on one `AVAudioPlayerNode` at explicit sample times. Edges are trimmed
  with 5 ms fades, then a pause is added: 280 ms after a sentence, 120 ms after a clause.
- **Replacement.** A new `speak` flushes the queue and starts over. `--stop` does the same with nothing new.

## Text normalisation

`SpeakNormalizer` is a pure Swift module (Foundation only, no I/O) with unit tests:

| Input | Spoken |
| --- | --- |
| `# Heading`, `- item`, `**bold**` | Heading. / item. / bold |
| fenced code | Code block omitted. |
| a pipe table | Table with two rows. Columns: Model, Score. Kokoro, nine of ten. |
| `https://github.com/a/b` | a link to github dot com |
| emoji, flags, ZWJ sequences | dropped |
| `$1,520.50`, `€2.50`, `₹1,50,000` | one thousand five hundred twenty dollars and fifty cents, two euros and fifty cents, one hundred fifty thousand rupees |
| `2.3 s`, `150 ms`, `36 GB`, `45%` | two point three seconds, one hundred fifty milliseconds, thirty six gigabytes, forty five percent |
| `10:30 am`, `2026-11-07`, `v1.2.3` | ten thirty A M, November seventh, twenty twenty six, version one point two point three |
| API, CLI, PR, CI/CD, JWT, URL | spelled as letters |
| npm, pnpm, uv, SQL, SQLite, PostgreSQL | N P M, P N P M, U V, S Q L, S Q Lite, Post gress Q L |
| JSON, YAML, TOML, OAuth | Jason, yammel, tommel, oh auth |
| TypeScript, PyTorch, ffmpeg, regex, localhost | Type Script, Pie Torch, F F M peg, rej ex, local host |
| stdin, stdout, stderr | standard in, standard out, standard error |
| iOS, macOS | I O S, mac O S |
| `fetchUserData`, `max_retry_count` | fetch User Data, max retry count |
| `package.json`, `~/src/main.ts`, `app.py` | package dot json, home slash src slash main dot T S, app dot pie |

`speak --normalize "text"` prints the result and the chunks. `speak --phonemes "text"` prints the phonemes the
engine will use. `--raw` skips normalisation.

## Voices

**Default: `af_heart`**, the only English voice graded A overall in Kokoro's `VOICES.md`. `--voice indian`
(`af_heart_in`) is an Indian-English blend: each of its 510 style rows is 0.75 `af_heart` plus 0.25 `hf_alpha`,
computed once and saved next to the stock voices. The four Hindi voices (`hf_alpha`, `hf_beta`, `hm_omega`,
`hm_psi`) read English with a stronger Indian accent; Devanagari text is not read.

## Engine and measurements

Kokoro-82M v1.0 runs as seven Core ML stages through FluidAudio 0.18.2. The **legacy** runtime is the default;
**ANE-v3** (`SPEAK_KOKORO=v3`) is about twice as fast, but on macOS 27.2 its GPU memory grew by about 13 MB per
chunk, so the long-lived server does not use it by default.

Measured on an M5 Max (36 GB, macOS 27.2), legacy runtime, default settings:

| | |
| --- | --- |
| Time to first audio, warm server | 59 ms (two-sentence reply) to 152 ms (numbers paragraph) |
| First sentence with a comma past 35 characters | 116 ms, against 168 ms for the same sentence without the cut |
| Real-time factor (synthesis time over audio time) | 0.040 to 0.06 |
| Cold start (models cached) | about 1.1 s model load, 1.45 s to a finished two-sentence WAV |
| Memory while loaded, after idle unload | about 455 MB footprint, about 330 MB after unload |
| Intelligibility (WhisperKit large-v3, word accuracy) | 99.3% on a three-minute sample, 100% on numbers |

## Configuration

| Variable | Effect |
| --- | --- |
| `SPEAK_AUDIO=null` | render audio in real time and discard it: no sound (tests, CI) |
| `SPEAK_KOKORO=v3` | use FluidAudio's ANE-v3 runtime |
| `SPEAK_UNLOAD_SECONDS` | idle seconds before the model is unloaded (default 900) |
| `SPEAK_IDLE_SECONDS` | idle seconds before the server exits (default 1800) |
| `SPEAK_HOME` | use another folder instead of `~/Library/Application Support/speak` |
| `SPEAK_SIGN_IDENTITY` | `build.sh` signing identity (default: first Apple Development identity, else ad hoc) |
| `SPEAK_INSTALL_DIR` | `build.sh` install folder (default `~/.local/bin`) |
| `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `XDG_CONFIG_HOME` | where `install-skill` writes for Claude Code, Codex and OpenCode |

Server settings come from the environment of the first `speak` call that starts the server.

## Privacy

Everything runs locally. Text is normalised and synthesised on your Mac; nothing is sent anywhere, and there is no
telemetry. The only network traffic is the one-time model and voice download from Hugging Face.

## Tests

```sh
swift test
```

The normaliser suites cover markdown, links, emoji, the developer lexicon, identifiers, paths, numbers and
chunking. The core suites drive `AVAudioEngine` in offline rendering (no audio device) and cover sample-exact
joins, replacement, stop, idle unload, the WAV and protocol codecs, and install-skill against a temporary home
folder. `swift scripts/make-icon.swift` redraws `docs/icon.png`.

## Credits and licence

MIT, see [LICENSE](LICENSE). Kokoro-82M by hexgrad (Apache-2.0), FluidAudio and its Core ML conversions by
FluidInference (Apache-2.0), and the NeMo text normaliser port text-processing-rs (Apache-2.0). Full list in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
