#!/bin/sh
# Start skilltri in the folder of the pane you were working in.
#
# herdr starts plugin panes in the plugin's own folder, but skilltri's Preview
# tab shows what a session in the current folder gets. So change to the focused
# pane's folder first (focused_pane_cwd from HERDR_PLUGIN_CONTEXT_JSON);
# SKILLTRI_PANE_CWD overrides it. If neither names a folder, stay where we are.
#
# The herdr server may run without the Homebrew prefix or ~/.local/bin on PATH,
# so fall back to the usual install locations (SKILLTRI_SEARCH_DIRS, space
# separated, overrides that list). SKILLTRI_PATH overrides everything.
dir="${SKILLTRI_PANE_CWD:-}"
if [ -z "$dir" ] && [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
  if command -v jq >/dev/null 2>&1; then
    dir="$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.focused_pane_cwd // empty' 2>/dev/null)"
  else
    # without jq: only plain paths (no quotes or backslashes)
    dir="$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | sed -n 's/.*"focused_pane_cwd":"\([^"\\]*\)".*/\1/p')"
  fi
fi
if [ -n "$dir" ] && [ -d "$dir" ]; then
  cd "$dir" || true
fi

if [ -n "${SKILLTRI_PATH:-}" ]; then
  exec "$SKILLTRI_PATH" "$@"
fi
if command -v skilltri >/dev/null 2>&1; then
  exec skilltri "$@"
fi
for bindir in ${SKILLTRI_SEARCH_DIRS:-/opt/homebrew/bin /usr/local/bin $HOME/.local/bin}; do
  if [ -x "$bindir/skilltri" ]; then
    exec "$bindir/skilltri" "$@"
  fi
done
printf 'skilltri not found. Install it with: brew install baeroe/tap/skilltri\n' >&2
printf '(see https://github.com/baeroe/skilltri)\n\nPress Enter to close.' >&2
read -r _
exit 127
