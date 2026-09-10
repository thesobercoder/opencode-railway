#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=8080}"
: "${OPENCODE_INTERNAL_PORT:=4096}"
: "${OPENCODE_SERVER_USERNAME:=opencode}"
: "${OPENCODE_WORKSPACE:=/data/workspace}"
export HOME="${HOME:-/data}"

# This service exposes an agent with shell access. Require a password before
# starting either server.
if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
	echo "FATAL: OPENCODE_SERVER_PASSWORD is not set." >&2
	echo "       The public code server requires authentication." >&2
	echo "       Set OPENCODE_SERVER_PASSWORD on this service and redeploy." >&2
	exit 1
fi

# Caddy cannot compute a basic-auth header, and no Railway variable can either —
# so it is derived here, at boot, and re-derives itself if the password changes.
OPENCODE_AUTH_HEADER="Basic $(printf '%s:%s' "$OPENCODE_SERVER_USERNAME" "$OPENCODE_SERVER_PASSWORD" | base64 -w0)"
export OPENCODE_AUTH_HEADER PORT OPENCODE_INTERNAL_PORT

mkdir -p "$OPENCODE_WORKSPACE" "$HOME/.config/opencode" "$HOME/.local/share/opencode" "$HOME/.cache"

# The volume mounts root-owned; git refuses to touch a tree whose owner differs
# from the caller, and the agent's first `git status` would fail with a
# dubious-ownership error that reads like a broken workspace.
git config --global --add safe.directory '*' || true
git config --global user.name "${GIT_AUTHOR_NAME:-opencode}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-opencode@localhost}"
git config --global committer.name "${GIT_COMMITTER_NAME:-${GIT_AUTHOR_NAME:-opencode}}"
git config --global committer.email "${GIT_COMMITTER_EMAIL:-${GIT_AUTHOR_EMAIL:-opencode@localhost}}"
git config --global init.defaultBranch main

# Reset inherited helpers for this host before consulting gh. Store only the
# helper command; gh reads the token from the environment when Git needs it.
git config --global --replace-all "credential.https://${GH_HOST:-github.com}.helper" ''
git config --global --add "credential.https://${GH_HOST:-github.com}.helper" '!gh auth git-credential'
gh config set git_protocol https --host "${GH_HOST:-github.com}"

if [ ! -d "$OPENCODE_WORKSPACE/.git" ]; then
	git init -q "$OPENCODE_WORKSPACE"
	echo "==> initialised an empty git workspace at $OPENCODE_WORKSPACE"
fi

cd "$OPENCODE_WORKSPACE"

# Refresh every configured skill on the mounted volume, including existing copies.
if ! timeout --kill-after=5s 180s /usr/local/bin/install-skills.sh; then
	echo "FATAL: Required global skills could not be installed or refreshed." >&2
	exit 1
fi

# MCP configuration is separate from skill installation.
if ! timeout --kill-after=5s 60s railway mcp install --agent opencode; then
	echo "WARNING: Railway MCP setup did not complete. Run 'railway mcp install --agent opencode' to retry." >&2
fi

# Register the remote browser alongside Railway without replacing other MCPs.
if [ -n "${PLAYWRIGHT_MCP_CDP_ENDPOINT:-}" ]; then
	mkdir -p "$HOME/browser-artifacts"
	node <<'NODE'
const fs = require('node:fs');
const path = `${process.env.HOME}/.config/opencode/opencode.json`;
const config = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : {};
const server = { type: 'local', command: ['playwright-mcp', '--caps', 'vision', '--output-dir', `${process.env.HOME}/browser-artifacts`] };
config.mcp ??= {};
if (config.mcp.servers) config.mcp.servers.browser = { ...server, disabled: false };
else config.mcp.browser = { ...server, enabled: true };
fs.writeFileSync(`${path}.tmp`, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
fs.renameSync(`${path}.tmp`, path);
NODE
fi

echo "==> opencode2 $(opencode2 --version 2>/dev/null || echo unknown)"
echo "==> workspace $OPENCODE_WORKSPACE, data $HOME/.local/share/opencode"
echo "==> caddy on :$PORT -> opencode on 127.0.0.1:$OPENCODE_INTERNAL_PORT"

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy_pid=$!

# Bound to loopback: Caddy is the only way in, so opencode is never directly
# reachable even from inside the Railway private network.
opencode2 serve --hostname 127.0.0.1 --port "$OPENCODE_INTERNAL_PORT" &
opencode_pid=$!

terminate() {
	kill -TERM "$caddy_pid" "$opencode_pid" 2>/dev/null || true
}
trap terminate TERM INT

# Exit as soon as either half dies so Railway restarts the container, rather than
# leaving a half-dead service reporting green.
wait -n "$caddy_pid" "$opencode_pid"
status=$?
terminate
exit "$status"
