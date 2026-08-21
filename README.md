# opencode-railway

Deployment image for [opencode](https://github.com/sst/opencode), the open-source
AI coding agent, running as a hosted code server on [Railway](https://railway.com).

Upstream publishes no runtime container image — only the `opencode-ai` npm
package, which pulls a compiled per-platform binary. This repo wraps it into a
container that is safe and useful to expose on a public URL.

## What this adds

| | Why |
|---|---|
| A toolchain (`git`, Node, Python, `build-essential`, `ripgrep`, …) | The agent runs shell commands. A bare binary in an empty image cannot build or test anything. |
| A Caddy front on `$PORT` | opencode requires basic auth on every route bar three static manifest files, so Railway's anonymous health-check prober gets a `401` — which fails a deployment exactly like a `503`. Caddy answers `/healthz` by replaying it as an *authenticated* request to opencode's `/global/health`, so a green health check means opencode is genuinely up and accepting the credential. |
| An entrypoint that refuses to boot without `OPENCODE_SERVER_PASSWORD` | Upstream prints a warning and serves anyway. This is an agent with shell access; unauthenticated means a public remote shell. |
| `HOME=/data` | Config, sessions, `auth.json`, cache and the workspace all hang off `$HOME`, so a single Railway volume covers every one of them. |
| `tini -s` | opencode spawns LSP servers, MCP servers and the agent's own shells. |

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `OPENCODE_SERVER_PASSWORD` | — | **Required.** HTTP basic auth password. The container exits if it is unset. |
| `OPENCODE_SERVER_USERNAME` | `opencode` | Basic auth username. |
| `PORT` | `8080` | Caddy's listen port; set by Railway. |
| `OPENCODE_INTERNAL_PORT` | `4096` | Loopback port opencode listens on. |
| `OPENCODE_WORKSPACE` | `/data/workspace` | Working directory, `git init`ed on first boot. |
| `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` | `opencode` / `opencode@localhost` | Identity for commits the agent makes. |

Provider credentials are ordinary environment variables — set
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY` or whichever your
model needs, or sign in from the UI, which persists to `auth.json` on the volume.

Build arg `OPENCODE_VERSION` (default `latest`) pins the opencode release.

## Licence

MIT, matching upstream. opencode itself is © the opencode authors.
