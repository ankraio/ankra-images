# PostgreSQL backup and restore tools (ankra-wcne8).
#
# This is the official postgres:16 Alpine image plus three things the backup and
# restore Jobs need: age to encrypt at the source, rclone for object storage,
# and curl for the in-cluster upload sink. Those Jobs used to run
# `apk add --no-cache age rclone curl` every time they started. So an Alpine
# mirror outage broke the nightly backup, and a new package version could
# change the backup tooling silently, with no change to any tracked file.
# Built once here and pinned by digest, the tooling changes only when someone
# re-pins it.
#
# The image is the whole toolkit for the Psono password manager's backups on
# ankra-infrastructure (ankra-production-values,
# stacks/psono-password-manager):
#   backup    pg_dump -Fc | age -r <recipient>, then rclone (bucket) or curl
#             (sink)
#   restore   age -d | pg_restore, into psono-db or into a throwaway
#             PostgreSQL that lives in pod memory (initdb, pg_ctl and su-exec
#             come from the base image)
#
# The base is pinned by digest as well as by tag, so a rebuild of the same
# commit starts from the same PostgreSQL. To move to a new minor version, set
# both ARGs together:
#   docker buildx imagetools inspect postgres:<version>-alpine<alpine> | sed -n 3p
#
# The PostgreSQL major version must be at least the major version of every
# server these Jobs dump. pg_dump refuses to dump a newer server. Psono runs
# PostgreSQL 16 (CloudNativePG).
ARG PG_TAG=16.15-alpine3.24
ARG PG_DIGEST=sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea
FROM postgres:${PG_TAG}@${PG_DIGEST}

# The restore Jobs start their throwaway PostgreSQL with `su-exec postgres ...`.
# The base ships su-exec as an alias of gosu (/usr/local/bin), and the last line
# checks that it is still there.
RUN apk add --no-cache age rclone curl \
 && age --version \
 && rclone version \
 && curl --version \
 && pg_dump --version \
 && su-exec postgres true

COPY --chmod=0755 smoke-test.sh /usr/local/bin/pg-backup-tools-smoke-test
