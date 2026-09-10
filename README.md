# OpenCode 2 on Railway

Run OpenCode 2 beta as an authenticated web service on Railway, with a persistent
workspace, GitHub and Railway tooling, and global programming skills.

The image includes:

- OpenCode 2 from `@opencode/cli@beta`, started with `opencode2 serve`.
- Git, GitHub CLI (`gh`), Railway CLI (`railway`), and the npm `skills` CLI.
- Node.js 22, Python 3, pip, virtual environments, and a C/C++ build toolchain.
- Shell utilities including curl, jq, ripgrep, and an SSH client.
- Caddy for the public HTTP port and Railway health checks, plus `tini` for child-process cleanup.

## Deploy on Railway

1. Create a service from this repository. [`railway.json`](railway.json) selects
   the Dockerfile, one replica, and restart-on-failure behavior with up to 10 retries.
2. Attach a persistent volume at `/data`.
3. Set the service variables below. Replace every placeholder with your own value.
4. Generate a Railway domain. Its target port must match `PORT`, which defaults to `8080`.
5. Keep the health-check path at `/healthz`. The repository config sets a 300-second timeout.
6. Deploy, open the domain, and sign in with `opencode` and your server password.
   Connect a model provider in OpenCode or supply its supported credential variables.

```dotenv
OPENCODE_SERVER_PASSWORD=replace-with-your-password
GH_TOKEN=replace-with-your-github-token
GIT_AUTHOR_NAME=Soham Dasgupta
GIT_AUTHOR_EMAIL=replace-with-your-github-commit-email
RAILWAY_API_TOKEN=replace-with-your-railway-token
```

Only `OPENCODE_SERVER_PASSWORD` is required to start the server. The other values
configure commit attribution and authenticated GitHub or Railway access. Use a
verified GitHub email or your GitHub noreply address for commit attribution.

## Variables and defaults

Defaults are supplied by the image or startup script. You do not need to repeat
them in Railway unless you want a different value.

| Variable | Default | Purpose |
|---|---|---|
| `OPENCODE_SERVER_PASSWORD` | None | Required password for the web UI and API. |
| `OPENCODE_SERVER_USERNAME` | `opencode` | Web UI and API username. |
| `PORT` | `8080` | Caddy's public HTTP port. Match the Railway domain target port. |
| `OPENCODE_INTERNAL_PORT` | `4096` | OpenCode's port, bound to `127.0.0.1`. |
| `OPENCODE_WORKSPACE` | `/data/workspace` | Initial working directory; initialized as a Git repository if needed. |
| `GIT_AUTHOR_NAME` | `opencode` | Author name and global Git `user.name`. |
| `GIT_AUTHOR_EMAIL` | `opencode@localhost` | Author email and global Git `user.email`. |
| `GIT_COMMITTER_NAME` | Author name | Global Git committer name. |
| `GIT_COMMITTER_EMAIL` | Author email | Global Git committer email. |
| `GH_TOKEN` | None | GitHub CLI and HTTPS Git authentication. |
| `GH_HOST` | `github.com` | GitHub host. Enterprise hosts use `GH_ENTERPRISE_TOKEN`. |
| `GIT_TERMINAL_PROMPT` | `0` | Prevent interactive Git credential prompts. |
| `GH_PROMPT_DISABLED` | `1` | Disable GitHub CLI prompts. |
| `RAILWAY_API_TOKEN` | None | Account/workspace token for Railway CLI and the default MCP connection. |
| `FIRECRAWL_API_KEY` | None | Credential for the configured Firecrawl web-search provider. |
| `OPENCODE_CONFIG_CONTENT` | `{"websearch":{"provider":"firecrawl"}}` | Inline OpenCode configuration supplied by the image. |

`RAILWAY_DOCKERFILE_PATH` is unnecessary because `railway.json` already selects
`Dockerfile`. The `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0`, and `GIT_CONFIG_VALUE_0`
credential-helper overrides are also unnecessary; startup configures the helper
globally. Remove those three together if they were set for this purpose.

## Authentication

### Web access

OpenCode enforces HTTP Basic authentication. Railway terminates HTTPS, and Caddy
forwards requests from `$PORT` to OpenCode on `127.0.0.1:$OPENCODE_INTERNAL_PORT`.
The startup script refuses to run without a server password.

Railway probes `/healthz` without credentials. Caddy forwards that request to
OpenCode's `/api/health` with the configured credentials. A successful probe
therefore checks OpenCode's JSON health endpoint, rather than only Caddy or an
HTML fallback. This endpoint does not check model-provider, GitHub, or Railway MCP access.

### GitHub

Startup writes the author defaults, committer identity, and
`!gh auth git-credential` helper to `/data/.gitconfig`. GitHub CLI reads `GH_TOKEN`
from the environment; the token is not written to Git config. Authentication
does not automatically set the commit name or email.

Use HTTPS remotes such as `https://github.com/OWNER/REPO.git`. SSH remotes still
need SSH credentials. The token must permit the requested repository operation;
branch rules still apply. See the [GitHub CLI environment reference](https://cli.github.com/manual/gh_help_environment).

### Railway

Create an account/workspace token at [Railway Account → Tokens](https://railway.com/account/tokens)
and set it as `RAILWAY_API_TOKEN`. Selecting a workspace limits the token to that
workspace; selecting “No workspace” gives account-wide access.

Alternatively, run `railway login --browserless` in the container terminal.
The login persists under `/data/.railway`. `GH_TOKEN` does not authenticate Railway,
and a project-scoped `RAILWAY_TOKEN` is not sufficient for the default hosted MCP
connection. See [Railway's token documentation](https://docs.railway.com/integrations/api#creating-a-token).

## Web search

The image explicitly selects Firecrawl for OpenCode's built-in web search:

```json
{"websearch":{"provider":"firecrawl"}}
```

This is supplied through `OPENCODE_CONFIG_CONTENT`; it does not rewrite files
on the volume. Keep `FIRECRAWL_API_KEY` in Railway's service variables. The key
is read at runtime and is not included in the image.

Selecting a provider ID disables automatic provider switching. A usable
Firecrawl credential is therefore needed for searches. If you override
`OPENCODE_CONFIG_CONTENT` in Railway, include the `websearch` setting in your
replacement JSON to retain this selection. This configures OpenCode's built-in
search default; it does not force independent MCP tools or explicit API
provider overrides to use Firecrawl. See the
[OpenCode 2 search configuration](https://opencode.ai/v2/docs/config#web-search).

## Skills and Railway MCP

Every startup runs these steps after the volume is mounted and before OpenCode starts:

| Step | Command | Failure behavior |
|---|---|---|
| Refresh all configured skills | `install-skills.sh` | Failure or a 180-second timeout stops startup. |
| Configure Railway MCP | `railway mcp install --agent opencode` | Failure or a 60-second timeout logs a warning; startup continues. |

The single [skill installer](install-skills.sh) defines all automatically installed
skills: the 37 PStack skills selected in the personal script and Railway's `use-railway` skill. Each source has an `install_skill_group` call. Add names to
an existing group or add another call to install more skills on every startup.
PStack comes from [`cursor/plugins`, under `pstack`](https://github.com/cursor/plugins/tree/main/pstack).

The installer fetches the current source and overwrites existing copies,
including local edits. It never skips installation because a file already exists.
All selected skills use the universal global location, `/data/.agents/skills`,
which OpenCode 2 discovers. Startup needs network access to refresh the configured skills even
when older copies are on the volume.

Railway MCP is configured separately from skills. It runs `railway mcp` over
stdio, which connects to Railway's hosted MCP service using CLI credentials.
The Railway MCP installer writes a V1-compatible MCP entry to OpenCode's global config;
OpenCode 2 accepts that format. Without Railway credentials, the skill is still
available but authenticated MCP operations fail. See the [Railway MCP documentation](https://docs.railway.com/cli/mcp).

Install another global skill from the container terminal:

```sh
skills add owner/repo -g -a universal --skill "skill-name" -y
skills list -g
```

Replace `owner/repo` and `skill-name` with the desired source and name. Additional
skills persist, but startup only refreshes skills listed in `install-skills.sh`. Run `install-skills.sh` to refresh all configured skills manually, or repeat
an individual `skills add` command to refresh that skill.

## Persistent data

With the default `HOME=/data`, the volume retains:

| Path | Contents |
|---|---|
| `/data/workspace` | Working repository and files. |
| `/data/.agents/skills` | Universal global skills. |
| `/data/.config/opencode` | OpenCode configuration, including Railway MCP. |
| `/data/.local/share/opencode` | OpenCode database and application data. |
| `/data/.local/state/opencode` | OpenCode state. |
| `/data/.cache` | Application caches. |
| `/data/.gitconfig` | Global Git configuration. |
| `/data/.config/gh` | GitHub CLI configuration. |
| `/data/.railway` | Railway CLI configuration and saved login. |

OpenCode 2 reuses existing configuration locations, but its server and plugin
APIs differ from V1. Check existing plugins against the
[V1 migration guide](https://opencode.ai/v2/docs/migrate-v1/).

## Build and update

```sh
docker build -t opencode-railway .
```

| Build argument | Default | Package |
|---|---|---|
| `OPENCODE_VERSION` | `beta` | `@opencode/cli` |
| `RAILWAY_CLI_VERSION` | `latest` | `@railway/cli` |
| `SKILLS_CLI_VERSION` | `latest` | `skills` |

Pass exact npm versions with `--build-arg` to pin tools. Floating tags are resolved
when their installation layers run; a cached Docker layer can retain an older
version. Use `docker build --no-cache` for a local build that fetches fresh packages.
Restarting a container refreshes the selected skills, but does not upgrade the
installed CLI binaries.

## Verify a deployment

Run these commands inside the container:

```sh
opencode2 --version
railway --version
skills --version
skills list -g
curl --fail "http://127.0.0.1:${PORT:-8080}/healthz"
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
gh api user --jq .login
```

To check GitHub repository read access, replace `OWNER/REPO` below with a private
repository accessible to your token:

```sh
git ls-remote https://github.com/OWNER/REPO.git HEAD
```

These checks do not verify Git push permission, model responses, or authenticated
Railway MCP tool calls. Check the Railway MCP connection in OpenCode after setting
its credentials. If startup fails before the web server starts, inspect the
service logs for a missing password or a failed required skill refresh.

## Licence

MIT. OpenCode and the installed tools and skills retain their respective licences.
