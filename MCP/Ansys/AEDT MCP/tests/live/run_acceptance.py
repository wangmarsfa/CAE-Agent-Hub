from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import time

from aedt_launcher import AedtLauncher, resolve_aedt_executable
from aedt_target import AedtTarget
from worker_client import WorkerClient


def run_operations(target: AedtTarget, client: WorkerClient, artifacts: Path) -> dict:
    probes = [client.execute(target, "ping", {}, timeout=30) for _ in range(10)]
    created = client.execute(
        target,
        "create_hfss_design",
        {
            "project_name": f"McpAcceptance{target.kind.title()}",
            "design_name": "McpAcceptanceHFSS",
            "solution_type": "DrivenModal",
        },
        timeout=60,
    )
    project_path = artifacts / f"McpAcceptance{target.kind.title()}.aedt"
    saved = client.execute(target, "save_project", {"path": str(project_path)}, timeout=60)
    return {
        "probe_count": len(probes),
        "all_connected": all(item.get("connected") for item in probes),
        "created": created,
        "saved": saved,
        "project_path": str(project_path),
    }


def wait_for_pid_probe(client: WorkerClient, pid: int, timeout: float = 120) -> None:
    deadline = time.monotonic() + timeout
    target = AedtTarget("pid", pid)
    last_error = None
    while time.monotonic() < deadline:
        try:
            client.execute(target, "ping", {}, timeout=10)
            return
        except Exception as exc:
            last_error = exc
            time.sleep(1)
    raise RuntimeError(f"PID {pid} did not become attachable: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("grpc", "pid"), required=True)
    parser.add_argument("--aedt-root", required=True)
    parser.add_argument("--port", type=int, default=50061)
    parser.add_argument("--result", type=Path, required=True)
    args = parser.parse_args()

    artifacts = args.result.parent
    artifacts.mkdir(parents=True, exist_ok=True)
    client = WorkerClient(log_dir=artifacts / "logs")
    if args.mode == "grpc":
        session = AedtLauncher(worker_client=client).launch(
            install_dir=args.aedt_root,
            port=args.port,
            timeout=120,
        )
        target = AedtTarget("port", session["port"])
    else:
        executable = resolve_aedt_executable(args.aedt_root)
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        session = {
            "pid": process.pid,
            "port": None,
            "version": "2026.1",
            "connection_mode": "pid",
        }
        wait_for_pid_probe(client, process.pid)
        target = AedtTarget("pid", process.pid)

    result = {"session": session, "operations": run_operations(target, client, artifacts)}
    args.result.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
