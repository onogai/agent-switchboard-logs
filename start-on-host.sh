#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"
: "${LOGGING_COMPOSE_PROJECTS:?Export comma-separated Compose project names}"
: "${LOGGING_GATEWAY_NETWORK:?Export the existing private Gateway network}"

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
systemctl --user enable --now switchboard-logging-refresh.service
systemctl --user is-active --quiet switchboard-logging-refresh.service

docker compose -f compose.yaml ps
echo 'VictoriaLogs UI: forward 127.0.0.1:19428 over SSH.'
