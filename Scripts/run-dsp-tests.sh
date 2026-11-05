#!/bin/zsh
# Builds and runs the standalone DSP tests (no Xcode project needed).
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="${TMPDIR:-/tmp}/ember-dsp-tests"
clang++ -std=c++20 -O2 -Wall -Wextra "$ROOT/Tests/DSPTests.cpp" -o "$OUT"
"$OUT"
