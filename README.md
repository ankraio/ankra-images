# ankra-images

Container images Ankra builds for its own infrastructure.

## `actions-runner`

The runner image for the `arc-runner-set` GitHub Actions scale set on the
`ankra-infrastructure` cluster. It is `ghcr.io/actions/actions-runner` plus the
toolchains the stock image does not carry:

| Tool | Stock image | Needed by |
| --- | --- | --- |
| `cc` / `gcc` / `g++` / `make` | missing | `go test -race` (cgo) — cluster `go-test` matrix, `go-ydoceval` |
| `docker compose` CLI plugin | missing (only `docker-buildx`) | cluster `platform-e2e` (`system_test/run_e2e.sh`) |
| `python3 -m venv`, `pip3` | `venv` fails, no `pip3` | the alembic migration venv in `run_e2e.sh` |

Without these, those lanes cannot run on ARC at all, which is what kept them on
Depot (`ankra-n2cs1`).

Language runtimes (Go, Node, …) are deliberately **not** baked in — workflows
pin those with `actions/setup-go` / `actions/setup-node`, and duplicating them
here would create a second, silently diverging source of version truth.

### Tags

Every build publishes an immutable `<runner-version>-<short-sha>` tag; pushes to
`master` additionally move `<runner-version>` and `latest`. **Pin the immutable
tag** in the scale set values — `latest` on a CI runner means the runner version
can change under a running scale set with no change to any tracked file.

```
ghcr.io/ankraio/actions-runner:2.337.0-<sha>
```

The workflow prints the exact tag to pin in its job summary.

### Architecture

`linux/amd64` only. The `build` node group on `ankra-infrastructure` is amd64;
publishing an arm64 variant would mean emulating every `apt-get` in QEMU for a
platform nothing currently schedules on.

### Rebuilds

A weekly scheduled rebuild picks up base-image and apt security updates. It
publishes a new immutable tag and does not disturb anything already deployed —
the scale set only moves when its values file is repinned.
