# Switchboard Logging

Standalone Docker Compose logging: Vector, VictoriaLogs, host-side discovery
and an optional private MCP. No Docker socket is mounted in the collector.

## Fresh install

On the Linux Docker host:

```bash
git clone https://github.com/onogai/agent-switchboard-logs.git
cd agent-switchboard-logs
cp .env.example .env
nano .env
./start-on-host.sh
```

Edit `LOGGING_COMPOSE_PROJECTS` (comma-separated Docker Compose projects
to collect) and `LOGGING_GATEWAY_NETWORK` (a network connected to Core).
Set `LOGGING_PRIVATE_NETWORK` to the current local-interactive Gateway
network when one exists. The installer reuses an existing private network
or creates it when absent. No application containers are restarted.

The `.env` contains non-secret identifiers and is parsed without evaluating
shell code. Exported environment variables take precedence. The new project
name and MCP alias default to `switchboard-logging` and
`switchboard-logging-mcp`.

## Check

```bash
systemctl --user status switchboard-logging-refresh.service
docker compose -f compose.yaml ps
curl -fsS http://127.0.0.1:19428/health
docker compose -f compose.yaml logs --tail=60 vector victorialogs mcp
```

VictoriaLogs binds only to loopback port 19428. The optional MCP has no
published port. The default Gateway source URL is
`http://switchboard-logging-mcp:8081/mcp`. Update the Registry source
URL in Manager if needed, and grant log queries only to the private
`local-interactive` profile.

## Replace an old installation without migrating data

Downtime and historical data loss are acceptable. Stop/disable only the
previous logging refresh systemd unit. Remove containers whose
`com.docker.compose.project` label matches the **old logging project**.
Optionally remove that project's old VictoriaLogs/Vector volumes.

Do not remove the existing private Docker network while Core's
`local-interactive` container is attached. Reuse it through
`LOGGING_PRIVATE_NETWORK`; the new collector uses separate Compose
containers and fresh data volumes.

Do not use broad `docker compose down -v`, `--remove-orphans` or
`docker system prune` across production projects. Core, Queue and
Telegram are independent and must not be stopped during logging cleanup.

## Operational limits

Vector reads Docker's JSON log files through read-only mounts. The host
refresh unit updates sources every 30 seconds. VictoriaLogs retention
is five days, with a 512 MiB soft disk limit. Collector memory buffers
are bounded and may drop excess events. Docker logs and query responses
can contain sensitive values; restrict access to the log UI and MCP.

The installer validates Compose, the Vector configuration and local
readiness; it does not modify application databases or secrets.
