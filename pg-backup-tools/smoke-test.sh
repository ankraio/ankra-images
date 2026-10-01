#!/bin/sh
# Smoke test for the pg-backup-tools image (ankra-wcne8). CI runs it on every
# build before anything is pushed, and it can also be run inside the image by
# hand.
#
# It runs the same pipelines the backup and restore Jobs use, end to end, on a
# throwaway PostgreSQL inside the container. The dump is
# pg_dump -Fc | age -r <recipient>. The restore is
# age -d -i <key> | pg_restore --exit-on-error, as a non-superuser database
# owner, into a database whose extensions a superuser created first (the
# CloudNativePG shape). The restored row count must match. Nothing leaves the
# container.
set -eu

work=$(mktemp -d)
export PGDATA="$work/data" PGHOST="$work"
mkdir -p "$PGDATA"
chown -R postgres:postgres "$work"
chmod 700 "$PGDATA"
su-exec postgres initdb -D "$PGDATA" -U postgres --auth=trust >/dev/null
su-exec postgres pg_ctl -D "$PGDATA" -w -l "$work/log" \
  -o "-c listen_addresses= -c unix_socket_directories=$work -c fsync=off" start >/dev/null
trap 'su-exec postgres pg_ctl -D "$PGDATA" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

psql -U postgres -q -v ON_ERROR_STOP=1 \
  -c "create database src" -c "create role app login" -c "create database dst owner app"
psql -U postgres -q -v ON_ERROR_STOP=1 -d src \
  -c "create extension ltree" -c "create extension pgcrypto" \
  -c "create table t (id int primary key, path ltree, h bytea)" \
  -c "insert into t select g, 'a.b.c', digest(g::text, 'sha256') from generate_series(1, 1000) g"
psql -U postgres -q -v ON_ERROR_STOP=1 -d dst \
  -c "create extension ltree" -c "create extension pgcrypto"

age-keygen -o "$work/key" 2>/dev/null
pg_dump -U postgres -Fc --no-owner --no-privileges src \
  | age -r "$(age-keygen -y "$work/key")" -o "$work/dump.age"
# The restore Jobs drop the COMMENT ON EXTENSION entries, because only the
# extension's owner (a superuser) may run them.
{ age -d -i "$work/key" "$work/dump.age" || true; } | pg_restore -l \
  | grep -v ' COMMENT - EXTENSION ' > "$work/toc"
age -d -i "$work/key" "$work/dump.age" \
  | pg_restore -L "$work/toc" --no-owner --no-privileges --exit-on-error -U app -d dst

rows=$(psql -U app -d dst -Atc "select count(*) from t")
[ "$rows" = 1000 ] || { echo "smoke FAILED: restored $rows rows, expected 1000"; exit 1; }

echo "postgres $(pg_dump --version | awk '{print $NF}')"
echo "age $(age --version)"
echo "rclone $(rclone version | awk 'NR==1 {print $2}')"
echo "curl $(curl --version | awk 'NR==1 {print $2}')"
echo "smoke_ok"
