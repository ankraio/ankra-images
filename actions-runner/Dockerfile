# Ankra ARC runner image.
#
# Base is the upstream GitHub Actions runner used by the gha-runner-scale-set
# chart. On top of it we preinstall the three toolchains that the stock image
# does not carry and that our CI lanes need, so that jobs run on the
# ankra-infrastructure ARC scale set without per-job `apt-get install`
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
# CLI tools the GitHub-hosted runner images ship as a baseline and that our
# workflows call bare, with no setup-* action. The stock ARC image has
# none of them, which is how cluster's helm-lint failed with "helm: command not
# found" the first time it ran on ARC (ankra-etutg). Pinned rather than
# floating, so a rebuild of the same tag produces the same tools.
#
# HELM stays on the 3.x line on purpose. Workflows call `helm lint --strict`
# with no version pin of their own, and helm 4 changes lint behaviour; moving
# that major is a deliberate decision for another change, not a side effect of
# giving ARC a helm at all.
#
# KUBECTL tracks the 1.36 line to match ankra-infrastructure (1.36.2) rather
# than newest-stable, keeping it inside the +/-1 minor skew for every cluster
# these workflows deploy to.
ARG HELM_VERSION=v3.21.4
ARG KUBECTL_VERSION=v1.36.4
ARG GH_VERSION=2.100.0
ARG YQ_VERSION=v4.53.6
ARG TARGETARCH

USER root

# One layer: apt metadata is dropped in the same step so it never reaches the
# image. build-essential brings cc/gcc/g++/make; python3.12-venv is the Ubuntu
# 24.04 package that restores ensurepip.
# Acquire::ForceIPv4 and the retry/timeout settings are not tuning, they are
# what makes this layer finish at all.
#
# archive.ubuntu.com publishes AAAA records alongside A, and from both the ARC
# scale sets and GitHub-hosted runners the IPv6 path to it is effectively
# dead-slow. Measured 2026-09-11:
#   from an arc runner:  254 kB in 18.9s  -> ~13 kB/s   (dl.google.com from the
#                                                        same runner: 117 MB/s)
#   inside buildkit:     96.2 MB of archives at ~18-20 kB/s, i.e. ~87 minutes;
#                        this build ran 47 min without finishing and was
#                        cancelled (ankra-1aefc)
# The same build took 0-1 minute on Depot, whose egress was IPv4-only.
#
# Forcing IPv4 sidesteps it. The timeout and retries are belt-and-braces so a
# slow mirror fails loudly instead of hanging a weekly cron nobody watches.
RUN printf 'Acquire::ForceIPv4 "true";\nAcquire::Retries "3";\nAcquire::http::Timeout "30";\n' \
        > /etc/apt/apt.conf.d/99-ankra-network \
    && apt-get update \
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
    curl -4 -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}"; \
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose

# helm, kubectl, gh and yq. Direct downloads rather than apt repos: each of
# these publishes a static binary, and adding four third-party apt sources to a
# CI runner image is a supply-chain surface for no benefit.
RUN set -eux; \
    ARCH="${TARGETARCH:-amd64}"; \
    case "${ARCH}" in \
        amd64|arm64) ;; \
        *) echo "unsupported TARGETARCH=${ARCH}" >&2; exit 1 ;; \
    esac; \
    curl -4 -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" \
        | tar -xz -C /tmp; \
    install -m 0755 "/tmp/linux-${ARCH}/helm" /usr/local/bin/helm; \
    rm -rf "/tmp/linux-${ARCH}"; \
    curl -4 -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"; \
    chmod 0755 /usr/local/bin/kubectl; \
    curl -4 -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
        | tar -xz -C /tmp; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/gh_${GH_VERSION}_linux_${ARCH}"; \
    curl -4 -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}"; \
    chmod 0755 /usr/local/bin/yq

# Fail the build rather than ship an image that silently lacks a toolchain the
# lanes depend on. Each line here corresponds to a measured gap in ankra-n2cs1.
RUN set -eux; \
    cc --version >/dev/null; \
    make --version >/dev/null; \
    docker compose version >/dev/null; \
    python3 -m venv /tmp/_venv_selftest; \
    /tmp/_venv_selftest/bin/pip --version >/dev/null; \
    rm -rf /tmp/_venv_selftest; \
    helm version --short >/dev/null; \
    kubectl version --client >/dev/null; \
    gh --version >/dev/null; \
    yq --version >/dev/null

USER runner
