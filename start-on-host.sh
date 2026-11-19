#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

# Load only the known non-secret identifiers; never evaluate shell code.
if [[ -f .env ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || "${line:0:1}" == "#" ]] && continue
    [[ $line == *=* ]] || { echo "Invalid .env line (expected KEY=value)" >&2; exit 2; }
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      LOGGING_COMPOSE_PROJECTS|LOGGING_GATEWAY_NETWORK|LOGGING_PRIVATE_NETWORK|LOGGING_PROJECT_NAME|LOGGING_MCP_ALIAS) ;;
      *) echo "Unknown .env setting: $key" >&2; exit 2 ;;
    esac
    [[ $value =~ ^[A-Za-z0-9_.,-]+$ ]] || {
      echo "Invalid value for $key (names only)" >&2; exit 2;
    }
    if [[ -z ${!key:-} ]]; then
      printf -v "$key" '%s' "$value"
      export "$key"
    fi
  done < .env
fi

: "${LOGGING_COMPOSE_PROJECTS:?Set the Compose projects in .env}"
: "${LOGGING_GATEWAY_NETWORK:?Set the Gateway Docker network in .env}"
: "${LOGGING_PRIVATE_NETWORK:=switchboard-logging-private}"
export LOGGING_PRIVATE_NETWORK

if [[ $(uname -s) != Linux ]]; then
  echo 'Run on the Linux Docker host.' >&2
  exit 2
fi
for command in docker python3 systemctl install curl sed; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

docker_root=$(docker info --format '{{.DockerRootDir}}')
containers_dir=${DOCKER_CONTAINERS_DIR:-$docker_root/containers}
[[ $containers_dir == "$docker_root/containers" ]] || {
  echo "DOCKER_CONTAINERS_DIR must be $docker_root/containers" >&2
  exit 1
}
export DOCKER_CONTAINERS_DIR="$containers_dir"

# Reuse the existing private network when the optional Core profile uses it.
# Otherwise create an isolated private network for this installation.
if ! docker network inspect "$LOGGING_PRIVATE_NETWORK" >/dev/null 2>&1; then
  docker network create "$LOGGING_PRIVATE_NETWORK" >/dev/null
fi

python3 refresh.py
docker compose -f compose.yaml config --quiet
docker compose -f compose.yaml run --rm --no-deps vector \
  validate --skip-healthchecks /etc/vector/vector.toml
docker compose -f compose.yaml up -d victorialogs vector
if docker network inspect "$LOGGING_GATEWAY_NETWORK" >/dev/null 2>&1; then
  docker compose -f compose.yaml --profile mcp up -d --no-deps mcp
else
  echo 'Gateway network absent; logging MCP backend remains stopped.'
fi

healthy=0
for attempt in {1..30}; do
  if curl --noproxy '*' --fail --silent --max-time 2 \
    http://127.0.0.1:19428/health >/dev/null; then
    healthy=1
    break
  fi
  sleep 1
done
[[ $healthy == 1 ]] || { echo 'VictoriaLogs did not become healthy' >&2; exit 1; }
[[ $(docker compose -f compose.yaml ps --status running --services vector) == vector ]] || {
  echo 'Vector is not running after startup' >&2
  exit 1
}

install -d -m 700 "$HOME/.config/systemd/user"
sed -e "s|@DEPLOY_ROOT@|$ROOT|g" \
    -e "s|@CONTAINERS_DIR@|$containers_dir|g" \
    -e "s|@PROJECTS@|$LOGGING_COMPOSE_PROJECTS|g" \
    switchboard-logging-refresh.service \
    > "$HOME/.config/systemd/user/switchboard-logging-refresh.service"
chmod 644 "$HOME/.config/systemd/user/switchboard-logging-refresh.service"
systemctl --user daemon-reload
systemctl --user enable switchboard-logging-refresh.service
# A running unit keeps its old Environment=PROJECTS until restarted.
# Restart only the lightweight host refresh watcher; Vector/Logs stay up.
systemctl --user restart switchboard-logging-refresh.service
systemctl --user is-active --quiet switchboard-logging-refresh.service

docker compose -f compose.yaml ps
echo 'VictoriaLogs UI: forward 127.0.0.1:19428 over SSH.'
