#!/usr/bin/env bash
# Idempotent bootstrap for mas-go-dev shared SIT PostgreSQL + Garage.
# Secrets stay on the server; this script never prints them.
set -euo pipefail

ROOT=/opt/shared-sit
TS_IP=100.109.223.53
PG_DIR="$ROOT/postgres"
S3_DIR="$ROOT/s3"
BACKUP="$ROOT/backup-before-$(date +%Y%m%d-%H%M%S)"

umask 077

sudo mkdir -p "$ROOT"
sudo chown ec2-user:ec2-user "$ROOT"
chmod 750 "$ROOT"
mkdir -p "$PG_DIR/tenants" "$S3_DIR" "$BACKUP"

{
  date -u +'%Y-%m-%dT%H:%M:%SZ'
  echo '=== free ==='
  free -h
  echo '=== docker ps ==='
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  echo '=== compose ls ==='
  docker compose ls
  echo '=== networks ==='
  docker network ls
  echo '=== listen ==='
  ss -tlnp
} >"$BACKUP/state.txt"

if ! docker network inspect shared-sit >/dev/null 2>&1; then
  docker network create --driver bridge shared-sit
fi

if [[ ! -f "$PG_DIR/.env" ]]; then
  PG_PASS=$(openssl rand -hex 16)
  cat >"$PG_DIR/.env" <<EOF
POSTGRES_USER=postgres
POSTGRES_DB=postgres
POSTGRES_PASSWORD=${PG_PASS}
POSTGRES_INITDB_ARGS=--data-checksums
EOF
  chmod 600 "$PG_DIR/.env"
fi

if [[ ! -f "$S3_DIR/garage.toml" ]]; then
  RPC_SECRET=$(openssl rand -hex 32)
  cat >"$S3_DIR/garage.toml" <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"
replication_factor = 1
rpc_bind_addr = "127.0.0.1:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "${RPC_SECRET}"
[s3_api]
s3_region = "ap-southeast-1"
api_bind_addr = "0.0.0.0:3900"
EOF
  chmod 600 "$S3_DIR/garage.toml"
fi

docker compose -f "$PG_DIR/docker-compose.yml" --project-directory "$PG_DIR" up -d
docker compose -f "$S3_DIR/docker-compose.yml" --project-directory "$S3_DIR" up -d

for i in $(seq 1 30); do
  if docker exec shared-sit-postgres pg_isready -U postgres -d postgres >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec shared-sit-postgres pg_isready -U postgres -d postgres >/dev/null

if [[ ! -f "$PG_DIR/tenants/evp.env" ]]; then
  EVP_PASS=$(openssl rand -hex 16)
  cat >"$PG_DIR/tenants/evp.env" <<EOF
DATABASE_URL=postgres://evp:${EVP_PASS}@${TS_IP}:5432/evp?sslmode=disable
PGHOST=${TS_IP}
PGPORT=5432
PGUSER=evp
PGDATABASE=evp
PGPASSWORD=${EVP_PASS}
EOF
  chmod 600 "$PG_DIR/tenants/evp.env"
fi

# shellcheck disable=SC1091
source "$PG_DIR/tenants/evp.env"
ROLE_SQL=$(mktemp)
trap 'rm -f "$ROLE_SQL"' EXIT
cat >"$ROLE_SQL" <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'evp') THEN
    CREATE ROLE evp LOGIN PASSWORD '${PGPASSWORD}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 40;
  END IF;
END
\$\$;
EOF
docker exec -i -u postgres shared-sit-postgres psql -v ON_ERROR_STOP=1 -d postgres <"$ROLE_SQL"
if [[ -z "$(docker exec -u postgres shared-sit-postgres psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='evp'")" ]]; then
  docker exec -u postgres shared-sit-postgres psql -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE evp OWNER evp"
fi
docker exec -u postgres shared-sit-postgres psql -v ON_ERROR_STOP=1 -d postgres -c "REVOKE CONNECT ON DATABASE postgres FROM PUBLIC; REVOKE CONNECT ON DATABASE template1 FROM PUBLIC; REVOKE CONNECT ON DATABASE evp FROM PUBLIC; GRANT CONNECT ON DATABASE evp TO evp;"
docker exec -u postgres shared-sit-postgres psql -v ON_ERROR_STOP=1 -d evp -c "REVOKE ALL ON SCHEMA public FROM PUBLIC; GRANT ALL ON SCHEMA public TO evp; ALTER SCHEMA public OWNER TO evp;"

for i in $(seq 1 30); do
  if docker exec shared-sit-s3 /garage status >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec shared-sit-s3 /garage status >/dev/null

if [[ ! -f "$S3_DIR/evp-key.secret.txt" ]]; then
  KEY_OUT=$(docker exec shared-sit-s3 /garage key create evp-sit)
  docker exec shared-sit-s3 /garage bucket create evp >/dev/null
  docker exec shared-sit-s3 /garage bucket allow evp --read --write --key evp-sit >/dev/null
  KEY_ID=$(printf '%s\n' "$KEY_OUT" | awk '/Key ID:/ {print $3; exit}')
  KEY_SECRET=$(printf '%s\n' "$KEY_OUT" | awk '/Secret key:/ {print $3; exit}')
  if [[ -z "$KEY_ID" || -z "$KEY_SECRET" ]]; then
    echo "garage key create did not return expected fields" >&2
    printf '%s\n' "$KEY_OUT" | sed 's/Secret key:.*/Secret key: <redacted>/'
    exit 1
  fi
  cat >"$S3_DIR/evp-key.secret.txt" <<EOF
S3_ENDPOINT=http://${TS_IP}:3900
S3_REGION=ap-southeast-1
S3_BUCKET=evp
S3_ACCESS_KEY=${KEY_ID}
S3_SECRET_KEY=${KEY_SECRET}
S3_FORCE_PATH_STYLE=true
EOF
  chmod 600 "$S3_DIR/evp-key.secret.txt"
fi

echo 'bootstrap ok'
docker compose ls | grep shared-sit
docker ps --filter name=shared-sit --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
ss -tlnp | grep -E '5432|3900' || true
