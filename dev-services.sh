#!/usr/bin/env bash
# Dashboard backing services: brings up the DEDICATED MongoDB + Redis in Docker.
# Idempotent — safe to re-run. Data persists in the per-service volumes.
#
# The JacHammer dashboard keeps its OWN containers, isolated from the jac-ide app
# which owns jac-ide-mongo (:27017) and jac-ide-redis (:6379) on this host. So the
# dashboard uses OFFSET host ports to avoid clashing:
#   dash-mongo  ->  host 27018 -> container 27017   (MONGODB_URI=mongodb://localhost:27018)
#   dash-redis  ->  host 6380  -> container 6379    (REDIS_URL=redis://localhost:6380)
# Both persist in their own named volumes; wiping one never touches jac-ide's data.
# This script only sets up the services — after it, run the server yourself:
#   set -a; source .env; set +a; export JAC_BUN="$HOME/.bun/bin/bun"; jac start main.jac --port=8010
#
# Usage: ./dev-services.sh [--reset-db] [--flush-redis] [--clean]
#   --reset-db      Drop the dash-mongo jac_db before exit (fresh graph state)
#   --flush-redis   Flush all dash-redis keys (clears the metrics cache)
#   --clean         Full clean: jac cache + jac_db + redis
set -euo pipefail
cd "$(dirname "$0")"

MONGO_CONTAINER="dash-mongo"
MONGO_VOLUME="dash-mongo-data"
MONGO_PORT="27018"          # host port; container is always 27017
REDIS_CONTAINER="dash-redis"
REDIS_VOLUME="dash-redis-data"
REDIS_PORT="6380"           # host port; container is always 6379 (jac-ide-redis owns 6379)

RESET_DB=false
FLUSH_REDIS=false
CLEAN=false
for arg in "$@"; do
  case "${arg}" in
    --reset-db) RESET_DB=true ;;
    --flush-redis) FLUSH_REDIS=true ;;
    --clean) CLEAN=true ;;
    -h|--help) echo "Usage: $0 [--reset-db] [--flush-redis] [--clean]"; exit 0 ;;
    *) echo "unknown argument: ${arg}" >&2; exit 1 ;;
  esac
done

# The configured host port of a container (running OR stopped), "" if none.
port_of() {
  docker inspect -f '{{range $p,$c := .HostConfig.PortBindings}}{{(index $c 0).HostPort}}{{end}}' "$1" 2>/dev/null || true
}

# Idempotent: create if missing, start if stopped, RECREATE if the existing
# container is mapped to the wrong host port (self-heals the old portless dash-redis).
ensure_service() {
  local name="$1" vol="$2" hostport="$3" ctnport="$4" image="$5" datadir="$6"
  if docker ps -a --filter "name=^${name}$" --format '{{.Names}}' | grep -q "${name}"; then
    if [[ "$(port_of "${name}")" != "${hostport}" ]]; then
      echo "… ${name} exists on host port '$(port_of "${name}")' ≠ ${hostport} — recreating"
      docker rm -f "${name}" >/dev/null
    else
      docker start "${name}" >/dev/null 2>&1 || true
      echo "✓ ${name} up (:${hostport})"
      return
    fi
  fi
  docker run -d --name "${name}" --restart unless-stopped \
    -p "${hostport}:${ctnport}" -v "${vol}":"${datadir}" "${image}" >/dev/null
  echo "✓ ${name} created (:${hostport})"
}

# 1. Containers
ensure_service "${MONGO_CONTAINER}" "${MONGO_VOLUME}" "${MONGO_PORT}" 27017 "mongo:7"         "/data/db"
ensure_service "${REDIS_CONTAINER}" "${REDIS_VOLUME}" "${REDIS_PORT}" 6379  "redis:7-alpine"  "/data"

# 2. Wait for readiness
until docker exec "${MONGO_CONTAINER}" mongosh --quiet --eval "db.adminCommand('ping').ok" >/dev/null 2>&1; do
  sleep 1
done
echo "✓ mongo ready on localhost:${MONGO_PORT}"
until docker exec "${REDIS_CONTAINER}" redis-cli ping >/dev/null 2>&1; do
  sleep 1
done
echo "✓ redis ready on localhost:${REDIS_PORT}"

# 3. Optional resets (dashboard graph lives in dash-mongo's jac_db)
if [[ "${RESET_DB}" == "true" || "${CLEAN}" == "true" ]]; then
  docker exec "${MONGO_CONTAINER}" mongosh jac_db --quiet --eval 'db.dropDatabase()' >/dev/null
  echo "✓ jac_db dropped (re-seed admin on next start — see note below)"
fi
if [[ "${FLUSH_REDIS}" == "true" || "${CLEAN}" == "true" ]]; then
  docker exec "${REDIS_CONTAINER}" redis-cli FLUSHALL >/dev/null
  echo "✓ redis flushed"
fi
if [[ "${CLEAN}" == "true" ]] && command -v jac >/dev/null 2>&1; then
  jac clean --cache --force >/dev/null 2>&1 || true
  echo "✓ jac cache cleaned"
fi

# 4. Re-seed reminder (new jaclang auto-seeds a credential-less admin on a fresh DB)
if [[ "${RESET_DB}" == "true" || "${CLEAN}" == "true" ]]; then
  cat <<'NOTE'
ℹ  Fresh DB — jaclang auto-seeds a credential-less `admin`. After `jac start`, do:
   docker exec dash-mongo mongosh jac_db --quiet --eval 'db.users.deleteOne({"identities.value_normalized":"admin","requires_password_reset":true})'
   curl -X POST :8010/user/register -H 'Content-Type: application/json' \
     -d '{"identities":[{"type":"username","value":"admin"},{"type":"email","value":"admin@jaseci.org"}],"credential":{"type":"password","password":"jachammer"}}'
NOTE
fi

echo "✓ services ready — next: set -a; source .env; set +a; export JAC_BUN=\"\$HOME/.bun/bin/bun\"; jac start main.jac --port=8010"
