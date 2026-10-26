#!/usr/bin/env bash
# Hermetic test suite: HERDR_BIN_PATH points at a fake herdr that serves
# fixture `pane list` JSON and records every other call's argv. No running
# herdr needed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/toggle-skilltri.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)" # resolved, so pwd output compares as is
trap 'rm -rf "$TMP"' EXIT

FAKE="$TMP/herdr"
LOG="$TMP/calls.log"
LIST="$TMP/list.json"
NOJQ="$TMP/nojq-bin"
mkdir -p "$NOJQ"

TESTS=0
FAILURES=0
pass() { TESTS=$((TESTS + 1)); printf 'ok   %s\n' "$1"; }
fail() { TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); printf 'FAIL %s\n' "$1"; }

# Absolute paths only, so the fake also works with an empty PATH (jq missing).
cat > "$FAKE" <<'FAKE'
#!/bin/bash
if [ "$1" = pane ] && [ "$2" = list ]; then
  [ "${FAKE_LIST_FAIL:-0}" = 1 ] && exit 1
  /bin/cat "$FAKE_LIST"
  exit 0
fi
printf '%s\n' "$*" >> "$FAKE_LOG"
FAKE
chmod +x "$FAKE"

OPEN_SPLIT="plugin pane open --plugin herdr-skilltri --entrypoint skilltri --placement split --direction right --focus"
OPEN_TAB="plugin pane open --plugin herdr-skilltri --entrypoint skilltri --placement tab --focus"

# run_case NAME MODE LIST_JSON EXPECTED_CALLS [ENV...]
# EXPECTED_CALLS is the exact newline-separated argv log (pane list excluded).
run_case() {
  local name="$1" mode="$2" list="$3" expect="$4"
  shift 4
  printf '%s' "$list" > "$LIST"
  : > "$LOG"
  env FAKE_LIST="$LIST" FAKE_LOG="$LOG" HERDR_BIN_PATH="$FAKE" "$@" \
    /bin/bash "$SCRIPT" "$mode" >/dev/null 2>&1
  local got
  got="$(/bin/cat "$LOG")"
  if [ "$got" = "$expect" ]; then
    pass "$name"
  else
    fail "$name"
    printf '     expected: %s\n     got:      %s\n' "$(printf '%s' "$expect" | tr '\n' ';')" "$(printf '%s' "$got" | tr '\n' ';')"
  fi
}

# --- fixtures ----------------------------------------------------------------

p() { printf '{"pane_id":"%s","tab_id":"%s","label":%s,"focused":%s}' "$1" "$2" "$3" "$4"; }
list() { local IFS=,; printf '{"id":"cli:pane:list","result":{"panes":[%s]}}' "$*"; }

NONE="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p2 w1:t1 null false)")"
HERE_UNFOCUSED="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p2 w1:t1 '"skilltri"' false)")"
HERE_FOCUSED="$(list "$(p w1:p1 w1:t1 null false)" "$(p w1:p2 w1:t1 '"skilltri"' true)")"
OTHER_TAB="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p3 w1:t2 '"skilltri"' false)")"
OTHER_WS="$(list "$(p w1:p1 w1:t1 null true)" "$(p w2:p1 w2:t1 '"skilltri"' false)")"
UNSAFE="$(list "$(p w1:p1 w1:t1 null true)" "$(p -rf w1:t1 '"skilltri"' false)")"
UNSAFE_TAB="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p3 --all '"skilltri"' false)")"
OTHER_LABEL="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p2 w1:t1 '"lazygit"' false)")"
NO_FOCUS="$(list "$(p w1:p1 w1:t1 null false)" "$(p w1:p2 w1:t1 '"skilltri"' false)")"

# --- static checks -----------------------------------------------------------

if bash -n "$SCRIPT"; then pass "script passes bash -n"; else fail "script passes bash -n"; fi

# tomllib needs Python 3.11+; skip on older interpreters (e.g. macOS /usr/bin/python3).
if ! python3 -c 'import tomllib' 2>/dev/null; then
  printf 'skip herdr-plugin.toml is valid TOML (python3 without tomllib)\n'
elif python3 -c 'import tomllib, sys; tomllib.load(open(sys.argv[1], "rb"))' "$ROOT/herdr-plugin.toml"; then
  pass "herdr-plugin.toml is valid TOML"
else
  fail "herdr-plugin.toml is valid TOML"
fi

: > "$LOG"
if ! FAKE_LIST="$LIST" FAKE_LOG="$LOG" HERDR_BIN_PATH="$FAKE" bash "$SCRIPT" bogus >/dev/null 2>&1 && [ ! -s "$LOG" ]; then
  pass "rejects unknown mode without calling herdr"
else
  fail "rejects unknown mode without calling herdr"
fi

# --- split -------------------------------------------------------------------

run_case "split: no skilltri pane -> open split" split "$NONE" "$OPEN_SPLIT"
run_case "split: skilltri in focused tab, unfocused -> focus" split "$HERE_UNFOCUSED" $'pane zoom w1:p2 --on\npane zoom w1:p2 --off'
run_case "split: skilltri focused -> close" split "$HERE_FOCUSED" "pane close w1:p2"
run_case "split: skilltri only in another tab -> open split" split "$OTHER_TAB" "$OPEN_SPLIT"
run_case "split: other label is not skilltri -> open split" split "$OTHER_LABEL" "$OPEN_SPLIT"
run_case "split: unsafe pane id -> open split" split "$UNSAFE" "$OPEN_SPLIT"
run_case "split: no focused pane -> open split" split "$NO_FOCUS" "$OPEN_SPLIT"
run_case "split: jq missing -> open split" split "$HERE_FOCUSED" "$OPEN_SPLIT" PATH="$NOJQ"
run_case "split: pane list fails -> open split" split "$HERE_FOCUSED" "$OPEN_SPLIT" FAKE_LIST_FAIL=1
run_case "split: garbage pane list -> open split" split "not json" "$OPEN_SPLIT"

# --- tab ---------------------------------------------------------------------

run_case "tab: no skilltri pane -> open tab" tab "$NONE" "$OPEN_TAB"
run_case "tab: skilltri in focused tab, unfocused -> focus" tab "$HERE_UNFOCUSED" $'pane zoom w1:p2 --on\npane zoom w1:p2 --off'
run_case "tab: skilltri focused -> close" tab "$HERE_FOCUSED" "pane close w1:p2"
run_case "tab: skilltri in another tab of same workspace -> tab focus" tab "$OTHER_TAB" "tab focus w1:t2"
run_case "tab: skilltri in another workspace -> open tab" tab "$OTHER_WS" "$OPEN_TAB"
run_case "tab: unsafe pane id -> open tab" tab "$UNSAFE" "$OPEN_TAB"
run_case "tab: unsafe tab id -> open tab" tab "$UNSAFE_TAB" "$OPEN_TAB"
run_case "tab: jq missing -> open tab" tab "$OTHER_TAB" "$OPEN_TAB" PATH="$NOJQ"
run_case "tab: pane list fails -> open tab" tab "$OTHER_TAB" "$OPEN_TAB" FAKE_LIST_FAIL=1

# --- run-skilltri.sh ---------------------------------------------------------

RUN="$ROOT/scripts/run-skilltri.sh"
FAKEBIN="$TMP/fakebin"
FAKEHOME="$TMP/home"
mkdir -p "$FAKEBIN" "$FAKEHOME/.local/bin" "$TMP/brew/bin"
printf '#!/bin/sh\necho "path-skilltri $*"\n' > "$FAKEBIN/skilltri"
printf '#!/bin/sh\necho "brew-skilltri $*"\n' > "$TMP/brew/bin/skilltri"
printf '#!/bin/sh\necho "home-skilltri $*"\n' > "$FAKEHOME/.local/bin/skilltri"
printf '#!/bin/sh\necho "override-skilltri $*"\n' > "$TMP/override"
chmod +x "$FAKEBIN/skilltri" "$TMP/brew/bin/skilltri" "$FAKEHOME/.local/bin/skilltri" "$TMP/override"

# variables of the launcher a surrounding herdr pane or shell may have set
CLEAN="-u HERDR_PLUGIN_CONTEXT_JSON -u SKILLTRI_PANE_CWD -u SKILLTRI_PATH -u SKILLTRI_SEARCH_DIRS"

check_run() {
  local name="$1" expect="$2" got
  shift 2
  # shellcheck disable=SC2086 # CLEAN is a list of flags
  got="$(env $CLEAN "$@" /bin/sh "$RUN" --tab preview </dev/null 2>/dev/null)"
  if [ "$got" = "$expect" ]; then pass "$name"; else fail "$name"; printf '     expected: %s\n     got:      %s\n' "$expect" "$got"; fi
}
check_run "run: skilltri on PATH" "path-skilltri --tab preview" PATH="$FAKEBIN:/usr/bin:/bin" HOME="$FAKEHOME"
check_run "run: falls back to the Homebrew prefix first" "brew-skilltri --tab preview" \
  PATH="/usr/bin:/bin" HOME="$FAKEHOME" SKILLTRI_SEARCH_DIRS="$TMP/brew/bin $FAKEHOME/.local/bin"
check_run "run: falls back to ~/.local/bin" "home-skilltri --tab preview" \
  PATH="/usr/bin:/bin" HOME="$FAKEHOME" SKILLTRI_SEARCH_DIRS="$TMP/nothing $FAKEHOME/.local/bin"
check_run "run: SKILLTRI_PATH wins" "override-skilltri --tab preview" \
  PATH="$FAKEBIN:/usr/bin:/bin" HOME="$FAKEHOME" SKILLTRI_PATH="$TMP/override"
# shellcheck disable=SC2086 # CLEAN is a list of flags
if env $CLEAN PATH="/usr/bin:/bin" HOME="$TMP/empty" SKILLTRI_SEARCH_DIRS="$TMP/nothing" /bin/sh "$RUN" </dev/null >/dev/null 2>&1; then
  fail "run: missing skilltri exits non-zero"
else
  pass "run: missing skilltri exits non-zero"
fi

# --- run-skilltri.sh: working directory --------------------------------------

# skilltri's Preview tab uses its working directory, so the launcher changes to
# the focused pane's folder. The fake skilltri prints where it was started.
mkdir -p "$TMP/start" "$TMP/project" "$TMP/my project" "$TMP/override-dir" "$TMP/sedonly"
printf '#!/bin/sh\npwd\n' > "$TMP/pwd-skilltri"
chmod +x "$TMP/pwd-skilltri"
ln -s "$(command -v sed)" "$TMP/sedonly/sed"
ctx() { printf '{"workspace_id":"w1","tab_id":"w1:t1","focused_pane_id":"w1:p1","focused_pane_cwd":"%s","invocation_source":"keybinding"}' "$1"; }

check_cwd() {
  local name="$1" expect="$2" got
  shift 2
  # shellcheck disable=SC2086 # CLEAN is a list of flags
  got="$(cd "$TMP/start" && env $CLEAN SKILLTRI_PATH="$TMP/pwd-skilltri" "$@" /bin/sh "$RUN" </dev/null 2>/dev/null)"
  if [ "$got" = "$expect" ]; then pass "$name"; else fail "$name"; printf '     expected: %s\n     got:      %s\n' "$expect" "$got"; fi
}
check_cwd "cwd: starts in the focused pane's folder" "$TMP/project" HERDR_PLUGIN_CONTEXT_JSON="$(ctx "$TMP/project")"
check_cwd "cwd: folder with a space" "$TMP/my project" HERDR_PLUGIN_CONTEXT_JSON="$(ctx "$TMP/my project")"
check_cwd "cwd: works without jq" "$TMP/project" PATH="$TMP/sedonly" HERDR_PLUGIN_CONTEXT_JSON="$(ctx "$TMP/project")"
check_cwd "cwd: SKILLTRI_PANE_CWD wins" "$TMP/override-dir" SKILLTRI_PANE_CWD="$TMP/override-dir" HERDR_PLUGIN_CONTEXT_JSON="$(ctx "$TMP/project")"
check_cwd "cwd: missing folder -> stays put" "$TMP/start" HERDR_PLUGIN_CONTEXT_JSON="$(ctx "$TMP/gone")"
check_cwd "cwd: no context -> stays put" "$TMP/start"
check_cwd "cwd: garbage context -> stays put" "$TMP/start" HERDR_PLUGIN_CONTEXT_JSON="not json"
check_cwd "cwd: context without focused pane -> stays put" "$TMP/start" HERDR_PLUGIN_CONTEXT_JSON='{"workspace_id":"w1"}'

# --- popup action ------------------------------------------------------------

# The manifest's popup action command, executed against the fake herdr.
: > "$LOG"
popup_cmd="$(sed -n '/^id = "open-skilltri-popup"/,/^command/p' "$ROOT/herdr-plugin.toml" | sed -n 's/^command = \["sh", "-c", "\(.*\)"\]$/\1/p' | sed 's/\\"/"/g')"
FAKE_LIST="$LIST" FAKE_LOG="$LOG" HERDR_BIN_PATH="$FAKE" sh -c "$popup_cmd" >/dev/null 2>&1
if [ "$(/bin/cat "$LOG")" = "plugin pane open --plugin herdr-skilltri --entrypoint popup --focus" ]; then
  pass "popup action opens the popup entrypoint"
else
  fail "popup action opens the popup entrypoint"
  printf '     got: %s\n' "$(/bin/cat "$LOG")"
fi
if sed -n '/^id = "popup"/,/^command/p' "$ROOT/herdr-plugin.toml" | grep -q 'placement = "popup"'; then
  pass "popup entrypoint has popup placement"
else
  fail "popup entrypoint has popup placement"
fi
# the toggle finds its pane by the label "skilltri"; the popup must not carry it
if [ "$(grep -c '^title = "skilltri"$' "$ROOT/herdr-plugin.toml")" = 1 ]; then
  pass "only the split/tab pane is titled skilltri"
else
  fail "only the split/tab pane is titled skilltri"
fi

# --- summary -----------------------------------------------------------------

printf '\n%d tests, %d failures\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
