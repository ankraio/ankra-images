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

Without these, those lanes cannot run on ARC at all -- baking them in is the
whole reason this image exists rather than the stock one (`ankra-n2cs1`).

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

## `pg-backup-tools`

The image the Psono password manager's backup and restore Jobs run on
`ankra-infrastructure` (ankra-production-values,
`stacks/psono-password-manager`). It is the official `postgres:16` Alpine
image, pinned by digest, plus `age`, `rclone` and `curl`:

| Tool | Used for |
| --- | --- |
| `pg_dump`, `psql` | the nightly logical dump and its per-table row counts |
| `age` | encrypting the dump at the source, and decrypting it on restore |
| `rclone` | the Hetzner Object Storage bucket |
| `curl` | uploading to the in-cluster backup sink |
| `initdb`, `pg_ctl`, `pg_restore`, `su-exec` | restore proofs into a throwaway PostgreSQL in pod memory |

Before this image existed, every Job ran `apk add age rclone curl` when it
started (ankra-wcne8). An Alpine mirror outage would have failed the backup,
and a new package version could have changed the backup tooling with no change
to any tracked file.

Every build runs `pg-backup-tools/smoke-test.sh` in the new image before
anything is pushed. The script does the same thing the Jobs do:
`pg_dump -Fc | age -r` and then `age -d | pg_restore`, restoring as a
non-superuser owner, against a throwaway database, and checking the row
count. You can also run it by hand: `docker run --rm <image>
pg-backup-tools-smoke-test`.

### Tags

Each build publishes an immutable `<postgres-version>-<short-sha>` tag, such as
`16.15-abc1234`. Pushes to `master` also move `16` and `latest`. The manifests
pin **the immutable tag plus its digest**:

```
ghcr.io/ankraio/pg-backup-tools:16.15-<sha>@sha256:<digest>
```

The workflow's job summary prints that exact string. The image is
multi-platform (`linux/amd64`, `linux/arm64`), and the digest is the index
digest.

### Moving PostgreSQL

`ARG PG_TAG` and `ARG PG_DIGEST` in the Dockerfile change together. The major
version must be at least the major version of every server the Jobs dump,
because `pg_dump` refuses a newer server. Psono runs PostgreSQL 16.
