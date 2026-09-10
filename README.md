# opencode-railway

Deployment image for [OpenCode 2 beta](https://github.com/anomalyco/opencode), the open-source
AI coding agent, running as a hosted code server on [Railway](https://railway.com).

Upstream publishes no runtime container image — only the `@opencode/cli@beta` npm
package, which pulls a compiled per-platform binary. This repo wraps it into a
container that is safe and useful to expose on a public URL.

## What this adds

| | Why |
|---|---|
| A toolchain (`git`, `gh`, `railway`, `skills`, Node, Python, `build-essential`, `ripgrep`, …) | The agent runs shell commands. A bare binary in an empty image cannot build or test anything. |
| A Caddy front on `$PORT` | OpenCode requires basic auth for the web UI and API, so Railway's anonymous health-check prober gets a `401` — which fails a deployment exactly like a `503`. Caddy answers `/healthz` by replaying it as an *authenticated* request to opencode's `/api/health`, so a green health check means opencode is genuinely up and accepting the credential. |
| An entrypoint that refuses to boot without `OPENCODE_SERVER_PASSWORD` | The password is checked before either server starts. This is an agent with shell access; unauthenticated means a public remote shell. |
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
| `GIT_COMMITTER_NAME` / `GIT_COMMITTER_EMAIL` | Author identity | Written to global `committer.name` / `committer.email` at startup. |
| `GH_TOKEN` | — | GitHub token for `gh` and Git over HTTPS. Set as a Railway service secret. |
| `GH_HOST` | `github.com` | Host for the Git credential helper and `gh`. Enterprise hosts use `GH_ENTERPRISE_TOKEN`. |
| `GIT_TERMINAL_PROMPT` | `0` | Disable Git terminal credential prompts. |
| `GH_PROMPT_DISABLED` | `1` | Disable interactive GitHub CLI prompts. |
| `RAILWAY_API_TOKEN` | — | Railway account or workspace token for the CLI and default Railway MCP connection. Alternatively, use a persisted `railway login`. |

### GitHub authentication

Set these Railway service variables before deploying:

```dotenv
GH_TOKEN=<your-github-token>
GH_HOST=github.com
GIT_AUTHOR_NAME=Soham Dasgupta
GIT_AUTHOR_EMAIL=your@email.com
GIT_COMMITTER_NAME=Soham Dasgupta
GIT_COMMITTER_EMAIL=your@email.com
GIT_TERMINAL_PROMPT=0
```

Replace the example email with your GitHub email or GitHub noreply address.
Startup writes the identity and `!gh auth git-credential` helper to
`/data/.gitconfig`. The token stays in the environment; it is not written to
Git config. GitHub CLI reads `GH_TOKEN` without `gh auth login`, as described in
the [GitHub CLI environment reference](https://cli.github.com/manual/gh_help_environment).

The following overrides are supported but optional because startup configures
the same helper globally. Use the literal key below, without Markdown links:

```dotenv
GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=credential.https://github.com.helper
GIT_CONFIG_VALUE_0=!gh auth git-credential
```

Use HTTPS remotes such as `https://github.com/OWNER/REPO.git`. Existing SSH
remotes still require SSH credentials. The token must have access to the target
repository and write permission to push; branch rules still apply.

After deployment, check authentication and repository read access in the
container, replacing `OWNER/REPO` with a private repository your token can access:

```sh
gh api user --jq .login
git ls-remote https://github.com/OWNER/REPO.git HEAD
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
```

These checks do not verify push permission or change the remote repository.

### Global skills

The npm `skills` CLI is installed globally. Install a named skill for all
projects using the universal agent target:

```sh
skills add owner/repo -g -a universal --skill <name> -y
```

Replace `owner/repo` and `<name>` with the repository and skill name. The `-y`
flag skips confirmation prompts for agent-driven installs. Global universal
skills live in `/data/.agents/skills`, which OpenCode 2 discovers and the
Railway volume preserves across deployments.

Use `skills list -g` to list installed global skills. Build arg
`SKILLS_CLI_VERSION` defaults to `latest` and accepts an exact npm version.
See the [skills CLI documentation](https://github.com/vercel-labs/skills).

### Railway agent integration

At startup, after the volume is mounted, the image installs the Railway skill
with the skills CLI if `/data/.agents/skills/use-railway/SKILL.md` is missing:

```sh
skills add railwayapp/railway-skills -g -a universal --skill use-railway -y
```

Existing skills are left intact on restart. No OpenCode-specific skill copy is
created. The separate command `railway mcp install --agent opencode` configures
the Railway MCP connection and preserves unrelated configuration entries. Its
generated configuration uses the V1-compatible MCP format accepted by OpenCode 2.

The default MCP command is `railway mcp`, which connects to Railway's hosted
MCP service through the CLI. Set `RAILWAY_API_TOKEN` as a Railway service secret,
or run `railway login --browserless` in the container terminal once. Login state
persists under `/data/.railway`. `GH_TOKEN` does not authenticate Railway, and
project-scoped `RAILWAY_TOKEN` is not sufficient for this default MCP connection.

Both setup commands are non-interactive and do not log in automatically. If
either fails or exceeds 60 seconds, startup logs a warning and continues. The
next boot retries missing setup. Re-run the skills command above to update or
repair the Railway skill explicitly. Restart OpenCode after manual setup so it
loads the integration.

Build arg `RAILWAY_CLI_VERSION` defaults to `latest` and accepts an exact CLI
version. See Railway's [agent setup documentation](https://docs.railway.com/cli/setup)
and [MCP documentation](https://docs.railway.com/cli/mcp).

Provider credentials are ordinary environment variables — set
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY` or whichever your
model needs, or sign in from the UI, which persists to `auth.json` on the volume.

Build arg `OPENCODE_VERSION` defaults to `beta` and accepts an exact
`@opencode/cli` beta version to pin a build. The server runs as `opencode2 serve`.
See the [OpenCode 2 installation guide](https://opencode.ai/v2/docs/).

The `/data` volume and existing configuration paths are retained. V2 changes
the server and plugin APIs; review existing plugins against the
[V1 migration guide](https://opencode.ai/v2/docs/migrate-v1/).

## Licence

MIT, matching upstream. opencode itself is © the opencode authors.
