#!/usr/bin/env bash
# Builds speak in release mode, signs it, and installs it to ~/.local/bin.
#
# Signing identity, in order:
#   1. $SPEAK_SIGN_IDENTITY (a name or SHA-1 from `security find-identity`)
#   2. the first "Apple Development" identity in the keychain
#   3. ad hoc ("-")
# A stable identity keeps macOS permission grants across rebuilds.
set -euo pipefail

cd "$(dirname "$0")"
BIN_DIR="${SPEAK_INSTALL_DIR:-$HOME/.local/bin}"

echo "Building speak (release)..."
swift build -c release --product speak
BUILT="$(swift build -c release --show-bin-path)/speak"

identity="${SPEAK_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ { print $2; exit }')"
fi
if [[ -z "$identity" ]]; then
  identity="-"
  echo "No signing identity found; signing ad hoc."
fi

mkdir -p "$BIN_DIR"
cp -f "$BUILT" "$BIN_DIR/speak.new"
codesign --force --timestamp=none --options runtime --sign "$identity" "$BIN_DIR/speak.new"
mv -f "$BIN_DIR/speak.new" "$BIN_DIR/speak"
echo "Installed $BIN_DIR/speak (signed: $([[ "$identity" == "-" ]] && echo ad hoc || echo "$identity"))"

# A running server is still the old binary; ask it to exit so the next call starts the new one.
"$BIN_DIR/speak" --shutdown >/dev/null 2>&1 || true

case ":$PATH:" in
  *":$BIN_DIR:"*) echo "$BIN_DIR is on your PATH: run 'speak \"Hello\"'." ;;
  *) echo "$BIN_DIR is not on your PATH. Add this to your shell profile:"
     echo "  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
