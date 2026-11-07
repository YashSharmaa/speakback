#!/usr/bin/env bash
# Installs speak (speakback) from source: checks the Mac, builds with build.sh,
# and installs ~/.local/bin/speak.
#
#   curl -fsSL https://raw.githubusercontent.com/YashSharmaa/speakback/main/install.sh | bash
#
# Run from a checkout, it builds that checkout; otherwise it clones the repository
# into a temporary folder and removes it afterwards.
# SPEAKBACK_REF picks a branch or tag to clone (default main).
set -euo pipefail

REPO="https://github.com/YashSharmaa/speakback.git"
REF="${SPEAKBACK_REF:-main}"

say() { printf '%s\n' "$*"; }
fail() { printf 'speakback: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "speak runs on macOS only."
[[ "$(uname -m)" == "arm64" ]] || fail "speak needs an Apple Silicon Mac (M1 or later)."

macos="$(sw_vers -productVersion)"
if (( ${macos%%.*} < 14 )); then
  fail "speak needs macOS 14 or later; this Mac has $macos."
fi

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  say "The Xcode command-line tools are needed to build speak."
  answer="n"
  if [[ -r /dev/tty ]]; then
    read -r -p "Install them now with 'xcode-select --install'? [y/N] " answer </dev/tty || true
  fi
  if [[ "$answer" =~ ^[Yy] ]]; then
    xcode-select --install || true
    say "Finish the installer window, then run this script again."
  else
    say "Run 'xcode-select --install', then run this script again."
  fi
  exit 1
fi

swift_version="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)"
if [[ -n "$swift_version" ]]; then
  major="${swift_version%%.*}"; minor="${swift_version#*.}"
  if (( major < 6 || (major == 6 && minor < 2) )); then
    fail "speak needs Swift 6.2 or later (found $swift_version). Update the command-line tools in Software Update."
  fi
fi

# Use the checkout this script sits in, if it is one; otherwise clone.
src=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n "$script_dir" && -f "$script_dir/Package.swift" && -x "$script_dir/build.sh" ]]; then
  src="$script_dir"
  say "Building the checkout in $src"
else
  command -v git >/dev/null 2>&1 || fail "git is needed to download speakback."
  tmp="$(mktemp -d -t speakback)"
  trap 'rm -rf "$tmp"' EXIT
  say "Downloading speakback ($REF)..."
  git clone --quiet --depth 1 --branch "$REF" "$REPO" "$tmp/speakback"
  src="$tmp/speakback"
fi

"$src/build.sh"

say ""
say "Done. Try: speak \"Hello from speakback.\""
say "The first run downloads about 90 MB of models (once)."
say "Teach Claude Code to read answers aloud: speak install-skill --claude"
