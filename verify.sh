#!/usr/bin/env bash
# M4 verification: build the package with the rc2 backend, run the single
# test runner (pure core, generation, combat, inventory, M4 content and UI),
# measure the frame path, and smoke-test the executable on a PTY.
set -euo pipefail
cd "$(dirname "$0")"

# Prefer the compiler installed into the Idris prefix; a stale wrapper in
# ~/.local/bin can otherwise shadow it and mismatch the support headers.
if [ -z "${IDRIS2:-}" ] && [ -x "$HOME/.idris2/bin/idris2-rc2" ]; then
  IDRIS2="$HOME/.idris2/bin/idris2-rc2"
fi
IDRIS2="${IDRIS2:-idris2-rc2}"
CG="${IDRIS2_CG:-rc2}"

# Clang 19 diagnoses the rc2 backend's generated `if ((a == b))` as
# `-Wparentheses-equality`, and the backend passes `-Werror` unconditionally.
# The parenthesised comparison comes from linked library code (for example
# Prelude's pair `Ord` instance), not from lambda-rogue.  Disable just that
# warning when the selected C compiler is Clang.
cc_bin="${IDRIS2_CC:-${CC:-cc}}"
if "$cc_bin" --version 2>/dev/null | grep -qi clang; then
  export IDRIS2_CFLAGS="${IDRIS2_CFLAGS:-} -Wno-parentheses-equality"
fi

# The test package has one source root; this symlink exposes the library
# modules to it without duplicating the sources.
ln -sfn ../src/LambdaRogue tests/LambdaRogue

# Idris 2's incremental check does not always notice a changed dependency in
# this rc2 build, and it can leave an executable from a previous run behind.
# Removing both build trees and the old executables makes the verification
# trustworthy; the build is still small enough to do from scratch.
echo "== clean =="
rm -rf build/ttc build/tests
rm -f build/exec/lambda-rogue build/exec/lambda-rogue-tests

# Keep the smoke test away from the player's save, autosave, scores and
# settings.  The application resolves these below $XDG_DATA_HOME/lambda-rogue.
export XDG_DATA_HOME="$PWD/build/verify-data"
rm -rf "$XDG_DATA_HOME"
mkdir -p "$XDG_DATA_HOME"

echo "== build ($IDRIS2) =="
"$IDRIS2" --codegen "$CG" --build lambda-rogue.ipkg
if [ ! -x build/exec/lambda-rogue ]; then
  echo "build failed: build/exec/lambda-rogue was not produced" >&2
  exit 1
fi

echo "== tests =="
"$IDRIS2" --codegen "$CG" --build lambda-rogue-tests.ipkg
if [ ! -x build/exec/lambda-rogue-tests ]; then
  echo "test build failed: build/exec/lambda-rogue-tests was not produced" >&2
  exit 1
fi
./build/exec/lambda-rogue-tests

echo "== smoke =="
if command -v script >/dev/null 2>&1; then
  # Let the first frame reach the PTY before sending the quit key.  Save
  # recovery and the session lock add startup I/O, and an immediately queued
  # key can otherwise be handled before the initial draw.
  (sleep 1; printf 'Q') | timeout 15 script -qec './build/exec/lambda-rogue' /dev/null \
    > /tmp/lambda-rogue-smoke.out 2>&1
  if ! grep -q "Dlvl 1" /tmp/lambda-rogue-smoke.out; then
    echo "smoke failed: the status line was not drawn" >&2
    exit 1
  fi
  echo "ok   starts, draws and quits on a PTY"
else
  echo "skip (script(1) is not installed)"
fi

echo "== verify: ok =="
