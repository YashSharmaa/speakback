# Changelog

## 1.0.0 (2026-11-07)

First public release.

- `speak` reads text, files and standard input aloud with Kokoro-82M through FluidAudio 0.18.2, on device. A warm
  server on a Unix socket starts audio in about 60 to 150 ms.
- Markdown-aware text normaliser: code blocks, tables, links, emoji, money, units, dates, versions, file paths,
  camelCase and snake_case identifiers, and a developer-term lexicon (npm, TypeScript, Postgres, SQLite, OAuth,
  JWT, YAML, stdin, ffmpeg, PyTorch, regex and more).
- The first sentence is cut at a comma past 35 characters so speech starts sooner; 120 ms pauses after clauses
  and 280 ms after sentences.
- An Indian-English voice, `--voice indian`, blended from 0.75 `af_heart` and 0.25 `hf_alpha`.
- The server unloads the model after 15 minutes idle and exits after 30.
- `speak install-skill` for Claude Code, Codex and OpenCode, with `--print` for any other harness and `--uninstall`.
- `--out` writes a WAV; `--stop`, `--status`, `--voices`, `--normalize`, `--phonemes`, `--version`.
- Homebrew formula and a one-line installer.
