#!/usr/bin/env bash
# Lantern Bay QA entry point.
#   tools/run_tests.sh              full suite (unit + data + economy + integration + self-tests)
#   tools/run_tests.sh fast=1       skip the slow process-per-self-test group
#   tools/run_tests.sh only=core/,data/   run tests whose name contains one of the substrings
# Steps: (1) import if scripts changed (class_name cache), (2) headless boot, forward_plus, grep for script errors,
# (3) headless boot with the Compatibility renderer (the web build), same grep, (4) the test runner.
# WINDOWED=1 additionally boots a real window with gl_compatibility (needs a display) and greps that log.
# The runner and the boots use a private HOME, so they never touch (or race with) the real save file.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
LOGDIR="${TMPDIR:-/tmp}/lantern_bay_qa"
mkdir -p "$LOGDIR"
export HOME_QA="$LOGDIR/home"
mkdir -p "$HOME_QA"
status=0
ERR_RE='SCRIPT ERROR|Parse Error|Invalid|^ERROR:'
IGNORE_RE='resources still in use at exit|ObjectDB instances were leaked|were leaked at exit'

# run a command with a hard timeout (macOS has no `timeout`)
with_timeout() { local secs="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }

echo "== 1. import (refresh the class_name cache when scripts changed)"
STAMP="$ROOT/.godot/qa_import.stamp"
if [ ! -f "$STAMP" ] || [ ! -f "$ROOT/.godot/global_script_class_cache.cfg" ] || \
   [ -n "$(find "$ROOT/scripts" "$ROOT/tests" "$ROOT/main.tscn" "$ROOT/project.godot" \( -name '*.gd' -o -name '*.tscn' -o -name 'project.godot' \) -newer "$STAMP" 2>/dev/null | head -1)" ]; then
  HOME="$HOME_QA" with_timeout 180 "$GODOT" --headless --path "$ROOT" --import > "$LOGDIR/import.log" 2>&1
  touch "$STAMP"
  echo "   imported (log: $LOGDIR/import.log)"
else
  echo "   up to date"
fi

boot() {   # $1 label, rest: extra godot args
  local label="$1"; shift
  local log="$LOGDIR/boot_${label}.log"
  HOME="$HOME_QA" with_timeout 120 "$GODOT" --headless --path "$ROOT" "$@" --quit-after 240 > "$log" 2>&1
  local code=$?
  local hits
  hits=$(grep -E "$ERR_RE" "$log" | grep -Ev "$IGNORE_RE" | head -20)
  if [ -n "$hits" ]; then
    echo "   FAIL boot [$label]: script errors in the log ($log)"
    echo "$hits" | sed 's/^/        /'
    status=1
  elif [ "$code" -ne 0 ] && [ "$code" -ne 142 ]; then
    echo "   FAIL boot [$label]: godot exited with code $code ($log)"
    status=1
  else
    echo "   ok   boot [$label]"
  fi
}

echo "== 2. headless boot (forward_plus)"
boot forward_plus
echo "== 3. headless boot (gl_compatibility: the web renderer)"
boot compatibility --rendering-method gl_compatibility
if [ "${WINDOWED:-0}" = "1" ]; then
  echo "== 3b. windowed boot (gl_compatibility, real renderer: catches shader / material problems the dummy driver hides)"
  log="$LOGDIR/boot_windowed.log"
  HOME="$HOME_QA" with_timeout 120 "$GODOT" --path "$ROOT" --rendering-method gl_compatibility --quit-after 240 > "$log" 2>&1
  hits=$(grep -E "$ERR_RE|^WARNING:.*(shader|Shader|compatib)" "$log" | grep -Ev "$IGNORE_RE" | head -20)
  if [ -n "$hits" ]; then echo "   FAIL windowed boot"; echo "$hits" | sed 's/^/        /'; status=1; else echo "   ok   windowed boot"; fi
fi

echo "== 4. test runner"
with_timeout 900 "$GODOT" --headless --path "$ROOT" -s res://tests/test_runner.gd -- "$@" 2>&1 | tee "$LOGDIR/runner.log" \
  | grep -vE "^\s+(at:|\[[0-9]+\]|GDScript backtrace)" 
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then status=1; fi
echo
if [ "$status" -eq 0 ]; then echo "ALL GREEN"; else echo "FAILURES (see above; full log $LOGDIR/runner.log)"; fi
exit "$status"
