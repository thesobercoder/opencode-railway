# opencode on Railway — https://github.com/sst/opencode
#
# Upstream publishes no runtime container image, only an npm package that pulls a
# per-platform compiled binary. This image adds the three things a hosted code
# server needs that `npm i -g opencode-ai` does not provide: a real toolchain for
# the agent to build and test with, a Caddy front so Railway can health-check an
# endpoint that opencode's basic auth would otherwise 401, and an entrypoint that
# refuses to start unauthenticated.

FROM node:22-bookworm-slim

# Caddy fronts opencode on $PORT. Static Go binary, so it copies onto Debian.
COPY --from=caddy:2-alpine /usr/bin/caddy /usr/bin/caddy

# node:*-slim ends its build with `apt-get purge --auto-remove`, which takes
# ca-certificates with it. Node has a built-in root store so the app looks fine,
# but git and every other non-Node HTTPS caller in here would fail.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        openssh-client \
        curl \
        wget \
        unzip \
        zip \
        ripgrep \
        jq \
        less \
        nano \
        procps \
        tini \
        python3 \
        python3-pip \
        python3-venv \
        build-essential \
    && rm -rf /var/lib/apt/lists/*
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Floating by default: opencode ships several releases a week and `latest` is its
# stable line (dev/next/beta are separate dist-tags). Override to pin a build.
ARG OPENCODE_VERSION=latest
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force \
    && opencode --version

COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Every path opencode writes hangs off $HOME — ~/.config/opencode (config,
# plugins), ~/.local/share/opencode (auth.json, sessions, logs) and ~/.cache.
# Pointing HOME at the mount lets one volume cover all of them plus the
# workspace, which is all Railway's 1:1 volume rule allows.
ENV HOME=/data \
    OPENCODE_WORKSPACE=/data/workspace \
    OPENCODE_INTERNAL_PORT=4096 \
    TINI_KILL_PROCESS_GROUP=1

WORKDIR /data/workspace

# opencode spawns LSP servers, MCP servers and the shells the agent runs, so the
# container needs a real reaper. -s registers a child subreaper because Railway's
# runtime, not this process, holds PID 1.
ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/entrypoint.sh"]
