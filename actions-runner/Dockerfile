# Ankra ARC runner image.
#
# Base is the upstream GitHub Actions runner used by the gha-runner-scale-set
# chart. On top of it we preinstall the three toolchains that the stock image
# does not carry and that our CI lanes need, so that jobs can move from Depot
# onto the ankra-infrastructure ARC scale set without per-job `apt-get install`
# preambles (measured on ghcr.io/actions/actions-runner:latest, see ankra-n2cs1):
#
#   * cc / gcc / g++ / make  -- absent upstream. `go test -race` needs cgo and
#     therefore a C compiler, so cluster ci.yml `go-test` (4-way matrix) and
#     `go-ydoceval` cannot run on the stock image at all.
#   * docker compose plugin  -- absent upstream (/usr/local/lib/docker/cli-plugins
#     ships docker-buildx only). cluster nightly.yml `platform-e2e` drives
#     system_test/run_e2e.sh, which is `docker compose` end to end.
#   * python3 venv + pip     -- python3 is present but `python3 -m venv` fails
#     with "ensurepip is not available"; run_e2e.sh builds its alembic
#     migration venv that way.
#
# Deliberately NOT installed: Go, Node, and other language runtimes. Workflows
# pin those through actions/setup-go and actions/setup-node, and baking them in
# would make this image a second, silently-diverging source of version truth.
#
# The base tag is pinned rather than floating on :latest. The arc-runner-set
# values.yaml pinned :latest, which means the runner version could change under
# a running scale set with no change to any tracked file.

ARG RUNNER_VERSION=2.337.0
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

# Pinned so a rebuild of the same tag produces the same plugin.
ARG COMPOSE_VERSION=v5.5.1
ARG TARGETARCH

USER root

# One layer: apt metadata is dropped in the same step so it never reaches the
# image. build-essential brings cc/gcc/g++/make; python3.12-venv is the Ubuntu
# 24.04 package that restores ensurepip.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        python3-venv \
        python3-pip \
        python3-dev \
        rsync \
        zip \
    && rm -rf /var/lib/apt/lists/*

# docker compose as a CLI plugin, alongside the docker-buildx the base already
# ships. Installed by direct download rather than by adding Docker's apt repo:
# the repo would also pull in a docker-ce-cli that conflicts with the base
# image's own docker client.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
        amd64) COMPOSE_ARCH=x86_64 ;; \
        arm64) COMPOSE_ARCH=aarch64 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}"; \
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose

# Fail the build rather than ship an image that silently lacks a toolchain the
# lanes depend on. Each line here corresponds to a measured gap in ankra-n2cs1.
RUN set -eux; \
    cc --version >/dev/null; \
    make --version >/dev/null; \
    docker compose version >/dev/null; \
    python3 -m venv /tmp/_venv_selftest; \
    /tmp/_venv_selftest/bin/pip --version >/dev/null; \
    rm -rf /tmp/_venv_selftest

USER runner
