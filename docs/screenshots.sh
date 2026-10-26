#!/usr/bin/env bash
# Regenerates the README screenshots in docs/screenshots/ from the VHS tapes in docs/tapes/.
#
#   bash docs/screenshots.sh            # all tapes
#   bash docs/screenshots.sh popup      # only docs/tapes/popup.tape
#
# Needs herdr, go, git, jq, vhs (brew install vhs; pulls ttyd and ffmpeg), optionally pngquant/oxipng, and
# a checkout of https://github.com/baeroe/skilltri (default: ../skilltri, override with SKILLTRI_REPO). Its
# demo data (docs/demo in that repo: seed.go, httpmcp.go and the fake MCP server) is reused, so the
# screenshots match its README.
#
# Nothing touches your herdr or your skilltri: everything runs in a throwaway sandbox HOME with skilltri's
# default dirs below it, so the real ~/.config/skilltri, the keychain and your daemon are never used (the
# only secret reference in the demo sits on a disabled server and is never resolved). A sandboxed skilltri
# daemon serves the demo servers, and a separate herdr server runs with the same HOME (its own config,
# socket and sessions), with only this plugin linked. Everything is removed afterwards.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
app_repo=$(cd "${SKILLTRI_REPO:-$repo/../skilltri}" && pwd)
herdr_bin=$(command -v herdr || echo "$HOME/.local/bin/herdr")
jq_bin=$(command -v jq)

# short, resolved path: herdr's unix sockets live under $HOME/.config/herdr, and skilltri shortens $HOME to ~
sandbox=$(cd "$(mktemp -d /tmp/hs.XXXXXX)" && pwd -P)
home="$sandbox/h"
bin="$home/.local/bin"
pids=()
alive() { # any recorded pid or any process started from the sandbox still running
	local p
	for p in ${pids[@]+"${pids[@]}"}; do kill -0 "$p" 2>/dev/null && return 0; done
	pgrep -f "$sandbox/" >/dev/null 2>&1
}
cleanup() {
	local status=$? p
	trap - EXIT INT TERM HUP
	{ exec 3>&-; } 2>/dev/null || true
	[ -x "$sandbox/env.sh" ] && "$sandbox/env.sh" herdr server stop >/dev/null 2>&1 || true
	[ -x "$sandbox/env.sh" ] && "$sandbox/env.sh" skilltri daemon stop >/dev/null 2>&1 || true
	pkill -f "$sandbox/" 2>/dev/null || true
	for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null || true; done
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		alive || break
		sleep 0.2
	done
	if alive; then
		pkill -9 -f "$sandbox/" 2>/dev/null || true
		for p in ${pids[@]+"${pids[@]}"}; do kill -9 "$p" 2>/dev/null || true; done
	fi
	for p in ${pids[@]+"${pids[@]}"}; do wait "$p" 2>/dev/null || true; done
	rm -rf "$sandbox"
	[ -n "${KEEP_VHS:-}" ] || rm -rf "$repo/.vhs"
	exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# --- skilltri and its demo data ---
mkdir -p "$bin" "$sandbox/bin"
# build with the real HOME (Go caches); the binaries go under the sandbox HOME, so skilltri shows ~/.local/bin
(
	cd "$app_repo"
	go build -trimpath -o "$bin/skilltri" .
	go build -trimpath -o "$sandbox/bin/fakemcp" ./internal/testutil/fakemcp/cmd/fakemcp
	go build -trimpath -o "$sandbox/bin/httpmcp" docs/demo/httpmcp.go
	go build -trimpath -o "$sandbox/bin/seed" docs/demo/seed.go
)
ln -s "$herdr_bin" "$bin/herdr"
ln -s "$jq_bin" "$bin/jq" # the toggle needs jq; nothing else from the real PATH

# one wrapper per demo stdio server, as in skilltri's docs/screenshots.sh
server() { # name tools [prompts] [resources]
	cat >"$bin/$1-mcp" <<EOF
#!/bin/sh
FAKEMCP_NAME=$1 FAKEMCP_TOOLS=$2 FAKEMCP_PROMPTS=${3:-} FAKEMCP_RESOURCES=${4:-} exec "$sandbox/bin/fakemcp" 2>/dev/null
EOF
	chmod +x "$bin/$1-mcp"
}
server docs search_docs,get_page,list_versions,get_changelog "" guides
server browser navigate,click,type_text,screenshot,read_console,close_tab
server notes search_notes,read_note,create_note,link_notes daily-summary
server wiki search_pages,get_page,recent_changes

# the environment of everything in the sandbox: skilltri, the daemon, the herdr server and its panes
cat >"$sandbox/env.sh" <<EOS
#!/bin/sh
cd "$home/dev/acme-shop" 2>/dev/null || cd "$home"
exec env -i HOME="$home" PATH="$bin:/usr/bin:/bin:/usr/sbin:/sbin" \\
	TERM=xterm-256color SHELL=/bin/zsh LANG=en_US.UTF-8 SKILLTRI_DEMO_HOME="$home" "\$@"
EOS
chmod +x "$sandbox/env.sh"

"$sandbox/env.sh" "$sandbox/bin/seed"

"$sandbox/env.sh" "$sandbox/bin/httpmcp" 127.0.0.1:47391 >"$sandbox/httpmcp.log" 2>&1 &
pids+=($!)
sleep 0.5
kill -0 "${pids[0]}" 2>/dev/null || { cat "$sandbox/httpmcp.log" >&2; echo "the demo HTTP server could not start (another screenshots run?)" >&2; exit 1; }

"$sandbox/env.sh" skilltri daemon >"$sandbox/daemon.out" 2>&1 &
pids+=($!)
for _ in $(seq 50); do
	"$sandbox/env.sh" skilltri status >/dev/null 2>&1 && break
	sleep 0.2
done
"$sandbox/env.sh" skilltri update >/dev/null

# a real MCP session from ~/dev/acme-shop that stays open while the tapes run
mkfifo "$sandbox/mcp.in"
"$sandbox/env.sh" skilltri mcp <"$sandbox/mcp.in" >"$sandbox/mcp.out" 2>&1 &
pids+=($!)
exec 3<>"$sandbox/mcp.in" # read-write, so opening never blocks
send() { printf '%s\n' "$1" >&3; }
send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude-code","version":"2.1.308"}}}'
send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
send '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
sleep 2
send '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tickets_search_tickets","arguments":{"query":"checkout 502"}}}'
send '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"docs_search_docs","arguments":{"query":"payment webhooks"}}}'
sleep 1

# --- the sandboxed herdr ---
mkdir -p "$home/.config/herdr"
cat >"$home/.config/herdr/config.toml" <<'EOS'
onboarding = false

[theme]
name = "dracula"

[terminal]
new_cwd = "~/dev/acme-shop"

[update]
version_check = false
manifest_check = false

[[keys.command]]
key = "prefix+m"
type = "plugin_action"
command = "herdr-skilltri.open-skilltri"
description = "skilltri"

[[keys.command]]
key = "prefix+p"
type = "plugin_action"
command = "herdr-skilltri.open-skilltri-popup"
description = "skilltri popup"
EOS
# a neutral prompt for the shell panes
printf "PROMPT='%%F{cyan}%%~%%f %%F{magenta}❯%%f '\n" >"$home/.zshrc"

start_herdr() {
	"$sandbox/env.sh" herdr server >>"$sandbox/server.log" 2>&1 &
	for _ in $(seq 50); do
		"$sandbox/env.sh" herdr status server 2>/dev/null | grep -q 'status: running' && break
		sleep 0.2
	done
	"$sandbox/env.sh" herdr plugin link "$repo" >/dev/null
}
stop_herdr() {
	"$sandbox/env.sh" herdr server stop >/dev/null 2>&1 || true
	rm -rf "$home/.config/herdr/session.json" "$home/.config/herdr/session-snapshots"
	sleep 1
}

cd "$repo"
export HERDR_DEMO="$sandbox/env.sh"
tapes=("$@")
if [ ${#tapes[@]} -eq 0 ]; then
	for f in docs/tapes/*.tape; do
		[ "$(basename "$f")" = config.tape ] || tapes+=("$(basename "$f" .tape)")
	done
fi
for t in "${tapes[@]}"; do
	echo "== $t"
	start_herdr # a fresh herdr session per tape
	vhs "docs/tapes/$t.tape"
	stop_herdr
done

cd docs/screenshots
command -v pngquant >/dev/null && pngquant --force --skip-if-larger --quality 80-95 --ext .png ./*.png || true
command -v oxipng >/dev/null && oxipng -q -o 4 --strip safe ./*.png || true
ls -lh
