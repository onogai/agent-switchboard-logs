"""Guard the log collector's selection and generated topology."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tomllib
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "refresh.py"
spec = importlib.util.spec_from_file_location("logging_refresh", SCRIPT)
assert spec and spec.loader
refresh = importlib.util.module_from_spec(spec)
with patch.dict(os.environ, {"LOGGING_COMPOSE_PROJECTS": "core-stack,coches-collector"}):
    spec.loader.exec_module(refresh)


def inspect_row(cid: str, project: str, service: str, *, path: str | None = None) -> str:
    path = path or f"/var/lib/docker/containers/{cid}/{cid}-json.log"
    return f"{cid}\t/{project}-{service}-1\tjson-file\t{path}\t{project}\t{service}"


class LoggingRefreshTests(unittest.TestCase):
    def test_selected_projects_only_and_new_container_gets_own_source(self) -> None:
        old, new, other = "a" * 64, "b" * 64, "c" * 64
        rows = "\n".join(
            [inspect_row(old, "core-stack", "mcp"),
             inspect_row(new, "coches-collector", "mcp"),
             inspect_row(other, "adguardhome", "adguardhome")]
        )

        def docker(*args: str) -> str:
            if args[0] == "ps":
                return old + "\n" if "core-stack" in args[-1] else new + "\n"
            return rows

        with patch.object(refresh, "docker", side_effect=docker):
            selected = refresh.discover()
        self.assertEqual({item["id"] for item in selected}, {old, new})

        config = tomllib.loads(refresh.render(selected, "docker-host"))
        self.assertEqual(set(config["sources"]), {f"docker_{old}", f"docker_{new}"})
        self.assertEqual(len(config["sinks"]["victorialogs"]["inputs"]), 2)
        self.assertNotIn(other, str(config))
        self.assertEqual(config["sources"][f"docker_{new}"]["read_from"], "beginning")

    def test_rejects_log_path_outside_expected_container_directory(self) -> None:
        cid = "a" * 64
        bad = inspect_row(cid, "core-stack", "mcp", path="/tmp/other.log")

        def docker(*args: str) -> str:
            return cid if args[0] == "ps" else bad

        with patch.object(refresh, "docker", side_effect=docker):
            with self.assertRaisesRegex(ValueError, "Unexpected log path"):
                refresh.discover()

    def test_generated_config_keeps_stream_and_docker_timestamp(self) -> None:
        cid = "a" * 64
        selected = [{"id": cid, "name": "core-service", "project": "core-stack",
                     "service": "mcp", "path": f"/var/lib/docker/containers/{cid}/{cid}-json.log"}]
        config = tomllib.loads(refresh.render(selected, "docker-host"))
        transform = config["transforms"][f"normalize_{cid}"]["source"]
        self.assertIn(".message = string!(entry.log)", transform)
        self.assertIn(".stream = string!(entry.stream)", transform)
        self.assertIn(".docker_time = string!(entry.time)", transform)
        self.assertIn("_time_field=docker_time", config["sinks"]["victorialogs"]["uri"])


if __name__ == "__main__":
    unittest.main()
