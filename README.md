# Switchboard Logging

An independent logging deployment for Docker Compose applications. The collector
discovers only projects named in `LOGGING_COMPOSE_PROJECTS`, reads the local
Docker JSON log files via read-only bind mounts, and ships them through Vector
to VictoriaLogs. An optional private MCP exposes queries.

## Configure

Export these values in the shell running the installation. Use the **existing**
Compose project/network/alias values when adopting an already deployed stack;
changing them unexpectedly creates parallel containers or disconnects Gateway.

```bash
export LOGGING_COMPOSE_PROJECTS=agent-switchboard,another-service
export LOGGING_GATEWAY_NETWORK=agent-switchboard_default
export LOGGING_PROJECT_NAME=switchboard-logging
export LOGGING_PRIVATE_NETWORK=switchboard-logging-private
export LOGGING_MCP_ALIAS=switchboard-logging-mcp
./start-on-host.sh
```

The Gateway source URL is `http://$LOGGING_MCP_ALIAS:8081/mcp` (substitute
the actual configured alias). The MCP port is never published. Use a
private local-interactive profile for log queries, not the public profiles.
VictoriaLogs listens on loopback `127.0.0.1:19428` only.

To inspect:
```bash
systemctl --user status switchboard-logging-refresh.service
docker compose -f compose.yaml ps
docker compose -f compose.yaml logs --tail=50 victorialogs vector
```

### Safe adoption of an existing logging deployment

The extraction contains source code but **does not migrate running containers,
volumes, network aliases, systemd units, or the Gateway's stored source URL**.
Before removing the original source checkout from the host:

1. Record the existing Compose project, mounted volumes, network names, MCP
   alias and running systemd unit; do not print secrets.
2. Copy this standalone checkout to a persistent directory.
3. Set all `LOGGING_*` variables to match the current deployment. Check
   `docker compose -f compose.yaml config`, including project/volumes/networks.
4. Disable the original refresh service *after* the new checkout is ready,
   then run `./start-on-host.sh`. Confirm the new unit and ingestion.
5. Confirm the Gateway log source still responds. Remove only the old unit and
   old source checkout after independent verification.

Never use broad `docker compose down -v` or orphan removal against either
project. Existing VictoriaLogs data and Vector checkpoints must survive.
The collector does not have the Docker socket and does not recreate applications.
The live log directory contains potentially sensitive data; restrict access.
