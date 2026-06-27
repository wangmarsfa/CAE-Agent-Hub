# PyAEDT-based AEDT MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-AEDT raw TCP bridge with an external, short-lived PyAEDT worker architecture that supports explicit PID attachment and visible gRPC-launched AEDT 2026 R1 sessions without preventing normal AEDT shutdown.

**Architecture:** The FastMCP server validates an explicit target and launches one JSON-speaking worker subprocess per operation. The worker connects through PyAEDT, performs one command, releases Desktop without closing projects or AEDT, emits one JSON response, and exits; the MCP process never retains an Automation object.

**Tech Stack:** Python 3.10+, FastMCP, PyAEDT, psutil, unittest/pytest, Windows subprocess and TCP APIs, AEDT 2026 R1 gRPC.

---

## File map

- Create `MCP/Ansys/AEDT MCP/aedt_target.py`: explicit PID/port target model and validation.
- Create `MCP/Ansys/AEDT MCP/worker_protocol.py`: JSON request/response envelopes and stable errors.
- Create `MCP/Ansys/AEDT MCP/pyaedt_backend.py`: PyAEDT connection lifecycle and supported commands.
- Create `MCP/Ansys/AEDT MCP/pyaedt_worker.py`: one-request stdin/stdout worker entry point.
- Create `MCP/Ansys/AEDT MCP/worker_client.py`: subprocess execution, timeout, logging, and target locks.
- Create `MCP/Ansys/AEDT MCP/session_discovery.py`: read-only AEDT PID and listener discovery.
- Create `MCP/Ansys/AEDT MCP/aedt_launcher.py`: visible AEDT gRPC launcher and readiness checks.
- Rewrite `MCP/Ansys/AEDT MCP/mcp_server.py`: structured MCP tools backed by workers.
- Modify `MCP/Ansys/AEDT MCP/pyproject.toml`: PyAEDT and psutil dependencies plus new modules.
- Rewrite `MCP/Ansys/AEDT MCP/.env.example`, `README.md`, `README.zh-CN.md`, and `examples/mcp_config.example.json`.
- Create focused tests under `MCP/Ansys/AEDT MCP/tests/` and replace obsolete bridge tests.
- Remove the supported raw bridge modules and scripts after the new tests pass.

### Task 1: Explicit target model and package dependencies

**Files:**
- Create: `MCP/Ansys/AEDT MCP/aedt_target.py`
- Create: `MCP/Ansys/AEDT MCP/tests/test_aedt_target.py`
- Modify: `MCP/Ansys/AEDT MCP/pyproject.toml`

- [ ] **Step 1: Write target validation tests**

```python
from aedt_target import AedtTarget, TargetValidationError


def test_pid_target_is_normalized():
    target = AedtTarget.from_values(pid=66276, port=None)
    assert target.kind == "pid"
    assert target.value == 66276
    assert target.key == "pid:66276"


def test_exactly_one_target_is_required():
    for values in ({"pid": None, "port": None}, {"pid": 1, "port": 50051}):
        try:
            AedtTarget.from_values(**values)
        except TargetValidationError:
            pass
        else:
            raise AssertionError("invalid target was accepted")
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `cd "MCP/Ansys/AEDT MCP"; .\.venv\Scripts\python.exe -m pytest tests/test_aedt_target.py -q`

Expected: collection fails because `aedt_target` does not exist.

- [ ] **Step 3: Implement the immutable target model**

```python
from dataclasses import dataclass


class TargetValidationError(ValueError):
    pass


@dataclass(frozen=True)
class AedtTarget:
    kind: str
    value: int

    @property
    def key(self) -> str:
        return f"{self.kind}:{self.value}"

    @classmethod
    def from_values(cls, pid: int | None, port: int | None) -> "AedtTarget":
        if (pid is None) == (port is None):
            raise TargetValidationError("provide exactly one of pid or port")
        kind, value = ("pid", pid) if pid is not None else ("port", port)
        if not isinstance(value, int) or value <= 0 or (kind == "port" and value > 65535):
            raise TargetValidationError(f"invalid AEDT {kind}: {value!r}")
        return cls(kind, value)
```

- [ ] **Step 4: Add dependencies and module declarations**

Set runtime dependencies to `mcp>=1.0`, `pyaedt==1.1.0`, and `psutil>=5.9,<8`. PyAEDT 1.1.0 is the current stable release and the PyPI compatibility matrix states that PyAEDT 0.27.0 and newer is tested with AEDT 2026 R1. Add all new Python modules to `tool.setuptools.py-modules`; remove raw bridge modules only in Task 8.

- [ ] **Step 5: Run the focused tests**

Run: `cd "MCP/Ansys/AEDT MCP"; .\.venv\Scripts\python.exe -m pytest tests/test_aedt_target.py -q`

Expected: `3 passed` after adding a positive port case.

- [ ] **Step 6: Commit**

```powershell
git add -- "MCP/Ansys/AEDT MCP/aedt_target.py" "MCP/Ansys/AEDT MCP/tests/test_aedt_target.py" "MCP/Ansys/AEDT MCP/pyproject.toml"
git commit -m "Add explicit AEDT target model"
```

### Task 2: Stable worker protocol

**Files:**
- Create: `MCP/Ansys/AEDT MCP/worker_protocol.py`
- Create: `MCP/Ansys/AEDT MCP/tests/test_worker_protocol.py`

- [ ] **Step 1: Write envelope round-trip and error tests**

```python
from worker_protocol import WorkerRequest, WorkerResponse


def test_request_round_trip():
    request = WorkerRequest.create("ping", {"kind": "port", "value": 50051}, {}, 30.0)
    restored = WorkerRequest.from_json(request.to_json())
    assert restored == request


def test_error_response_has_stable_code():
    response = WorkerResponse.failure("abc", "session_not_found", "AEDT target is unavailable")
    assert response.to_dict()["error"]["code"] == "session_not_found"
```

- [ ] **Step 2: Verify failure**

Run: `cd "MCP/Ansys/AEDT MCP"; .\.venv\Scripts\python.exe -m pytest tests/test_worker_protocol.py -q`

Expected: import failure for `worker_protocol`.

- [ ] **Step 3: Implement protocol dataclasses**

Implement `WorkerRequest` fields `request_id`, `command`, `target`, `arguments`, and `timeout_seconds`; reject unknown top-level fields, non-object arguments, unsupported target kinds, and non-positive timeouts. Implement `WorkerResponse.success()` and `WorkerResponse.failure()` with one-line JSON output using UTF-8 and `ensure_ascii=False`.

- [ ] **Step 4: Test malformed input and JSON-only output**

Add tests that reject a missing request ID and verify that response JSON contains no Python object representations. Run the focused test file and expect all cases to pass.

- [ ] **Step 5: Commit**

```powershell
git add -- "MCP/Ansys/AEDT MCP/worker_protocol.py" "MCP/Ansys/AEDT MCP/tests/test_worker_protocol.py"
git commit -m "Define AEDT worker protocol"
```

### Task 3: PyAEDT backend and guaranteed release

**Files:**
- Create: `MCP/Ansys/AEDT MCP/pyaedt_backend.py`
- Create: `MCP/Ansys/AEDT MCP/tests/test_pyaedt_backend.py`

- [ ] **Step 1: Write fake-Desktop lifecycle tests**

```python
from aedt_target import AedtTarget
from pyaedt_backend import PyAedtBackend


class FakeDesktop:
    def __init__(self):
        self.releases = []

    def project_list(self):
        return ["Demo"]

    def release_desktop(self, close_projects=False, close_on_exit=False):
        self.releases.append((close_projects, close_on_exit))
        return True


def test_backend_releases_after_success():
    desktop = FakeDesktop()
    backend = PyAedtBackend(desktop_factory=lambda **kwargs: desktop)
    result = backend.execute(AedtTarget("port", 50051), "list_projects", {})
    assert result["projects"] == ["Demo"]
    assert desktop.releases == [(False, False)]


def test_backend_releases_after_command_failure():
    desktop = FakeDesktop()
    backend = PyAedtBackend(desktop_factory=lambda **kwargs: desktop)
    try:
        backend.execute(AedtTarget("pid", 1234), "unknown", {})
    except ValueError:
        pass
    assert desktop.releases == [(False, False)]
```

- [ ] **Step 2: Verify the tests fail**

Run the focused test file and expect import failure.

- [ ] **Step 3: Implement connection arguments and release**

For PID targets call `Desktop(version="2026.1", non_graphical=False, new_desktop=False, close_on_exit=False, aedt_process_id=pid)`. For port targets call `Desktop(version="2026.1", non_graphical=False, new_desktop=False, close_on_exit=False, machine="localhost", port=port)`. Put `release_desktop(close_projects=False, close_on_exit=False)` in `finally` and never call `close_desktop` or terminate a process.

- [ ] **Step 4: Implement structured commands**

Implement dispatch for `ping`, `project_info`, `create_hfss_design`, `save_project`, `start_analysis`, and `analysis_status`. Use PyAEDT `Desktop` for session/project queries and PyAEDT `Hfss` for HFSS operations. Require explicit project, design, and setup names for analysis; return JSON-compatible strings, numbers, booleans, lists, and dictionaries only.

- [ ] **Step 5: Add command contract tests**

Use fake Desktop and HFSS factories to verify connection keyword arguments, no silent project/design substitution, non-blocking `analyze_setup(..., blocking=False)`, and `are_there_simulations_running` status output.

- [ ] **Step 6: Run focused tests and commit**

Run: `cd "MCP/Ansys/AEDT MCP"; .\.venv\Scripts\python.exe -m pytest tests/test_pyaedt_backend.py -q`

Expected: all backend tests pass without starting AEDT.

```powershell
git add -- "MCP/Ansys/AEDT MCP/pyaedt_backend.py" "MCP/Ansys/AEDT MCP/tests/test_pyaedt_backend.py"
git commit -m "Add short-lived PyAEDT backend"
```

### Task 4: Worker entry point and subprocess isolation

**Files:**
- Create: `MCP/Ansys/AEDT MCP/pyaedt_worker.py`
- Create: `MCP/Ansys/AEDT MCP/worker_client.py`
- Create: `MCP/Ansys/AEDT MCP/tests/test_worker_process.py`

- [ ] **Step 1: Write worker client tests**

Create fixture worker scripts in pytest temporary directories: one returns a valid response, one sleeps beyond the timeout, one writes diagnostics to stderr, and one emits invalid stdout. Assert that `WorkerClient.execute()` returns the valid result, raises `WorkerTimeoutError` after terminating only the worker, preserves stderr in the diagnostic log, and rejects malformed stdout.

- [ ] **Step 2: Verify failure**

Run the focused test file and expect imports for `worker_client` and `pyaedt_worker` to fail.

- [ ] **Step 3: Implement `pyaedt_worker.py`**

Read exactly one line from stdin, parse `WorkerRequest`, execute `PyAedtBackend`, and print exactly one `WorkerResponse` line to stdout. Configure PyAEDT logging to stderr or the request log path before creating Desktop. Map validation, connection, command, and unexpected exceptions to stable error codes; return a nonzero exit status for failed responses.

- [ ] **Step 4: Implement `WorkerClient`**

Use `subprocess.Popen` with stdin/stdout/stderr pipes, UTF-8 text mode, the MCP virtual-environment interpreter, hidden Windows console flags, and a sanitized environment. Use `communicate(request_json, timeout=...)`; on timeout call `terminate`, wait briefly, then `kill` only the worker if needed. Parse one response line and write stderr to `AEDT_LOG_DIR`.

- [ ] **Step 5: Implement per-target locking**

Add an `asyncio.Lock` registry keyed by `AedtTarget.key`. `execute_async()` must hold the target lock around `asyncio.to_thread(execute, ...)`. Add a test that two commands for one target do not overlap while commands for distinct targets can overlap.

- [ ] **Step 6: Run focused tests and commit**

```powershell
git add -- "MCP/Ansys/AEDT MCP/pyaedt_worker.py" "MCP/Ansys/AEDT MCP/worker_client.py" "MCP/Ansys/AEDT MCP/tests/test_worker_process.py"
git commit -m "Isolate PyAEDT commands in worker processes"
```

### Task 5: Read-only session discovery

**Files:**
- Create: `MCP/Ansys/AEDT MCP/session_discovery.py`
- Create: `MCP/Ansys/AEDT MCP/tests/test_session_discovery.py`

- [ ] **Step 1: Write process and listener discovery tests**

Inject fake process records and TCP listener records. Verify only `ansysedt.exe` processes are returned, listeners are associated by PID, candidates are sorted only for stable output, and the result has no `selected` or `default` field.

- [ ] **Step 2: Verify failure**

Run the focused test file and expect import failure.

- [ ] **Step 3: Implement discovery**

Use `psutil.process_iter(["pid", "name", "exe", "create_time"])` and `psutil.net_connections(kind="tcp")`. Return records containing `pid`, `version` inferred from the executable path when available, `executable`, `started_at`, and a list of localhost listening ports. Treat access-denied process fields as unavailable rather than failing the whole query.

- [ ] **Step 4: Add optional health enrichment**

For a caller-specified candidate only, allow `probe_session(pid=...)` or `probe_session(port=...)` to call the worker `ping` command. Do not probe every discovered process automatically because an Automation attach is not read-only at the lifecycle level.

- [ ] **Step 5: Run focused tests and commit**

```powershell
git add -- "MCP/Ansys/AEDT MCP/session_discovery.py" "MCP/Ansys/AEDT MCP/tests/test_session_discovery.py"
git commit -m "Discover AEDT sessions without auto-selection"
```

### Task 6: Visible gRPC AEDT launcher

**Files:**
- Create: `MCP/Ansys/AEDT MCP/aedt_launcher.py`
- Create: `MCP/Ansys/AEDT MCP/tests/test_aedt_launcher.py`

- [ ] **Step 1: Write launcher tests with injected process/socket functions**

Verify that port `0` selects an unused localhost port, an explicit occupied port is rejected, the command is `ansysedt.exe -grpcsrv <port>`, readiness requires both a live process and a successful worker ping, and timeout does not terminate the AEDT process.

- [ ] **Step 2: Verify failure**

Run the focused test file and expect import failure.

- [ ] **Step 3: Implement installation and port resolution**

Resolve `ansysedt.exe` from `AEDT_INSTALL_DIR`, then `ANSYSEM_ROOT261`, then the known installed-version registry information exposed by PyAEDT. Validate the executable path. Reserve an unused localhost port before launch and release the reservation immediately before `Popen`.

- [ ] **Step 4: Implement visible launch and readiness**

Start `[ansysedt.exe, "-grpcsrv", str(port)]` without non-graphical flags. Poll process state and TCP readiness until `AEDT_LAUNCH_TIMEOUT`, then run worker `ping` against that exact port. Return `pid`, `port`, `version`, and `connection_mode="grpc"`.

- [ ] **Step 5: Run focused tests and commit**

```powershell
git add -- "MCP/Ansys/AEDT MCP/aedt_launcher.py" "MCP/Ansys/AEDT MCP/tests/test_aedt_launcher.py"
git commit -m "Launch visible AEDT gRPC sessions"
```

### Task 7: Rewrite the FastMCP tool layer

**Files:**
- Rewrite: `MCP/Ansys/AEDT MCP/mcp_server.py`
- Create: `MCP/Ansys/AEDT MCP/tests/test_mcp_tools.py`

- [ ] **Step 1: Write tool tests against fake collaborators**

Test `list_aedt_sessions`, `launch_aedt`, `check_aedt_connection`, `release_connection`, `get_project_info`, `create_hfss_design`, `save_project`, `start_analysis`, and `get_analysis_status`. Every targeted tool must reject missing or double targets before invoking a worker. Assert that tool outputs include the explicit target.

- [ ] **Step 2: Verify the new tests fail**

Run the focused test file against the existing bridge server and expect missing collaborator/tool contract failures.

- [ ] **Step 3: Rewrite `mcp_server.py`**

Remove raw socket imports, host/token/bridge settings, `atexit`, arbitrary `run_script`, and `stop_bridge`. Construct `AedtTarget` for every targeted call and route commands through `WorkerClient.execute_async`. Keep `aedt://status`, but make it return discovered sessions and `connected: false` until the caller probes an explicit target.

- [ ] **Step 4: Add actionable errors and instructions**

Errors must tell the caller to use `list_aedt_sessions` and then provide one PID or port. Agent instructions must state that no target is implicit and that gRPC port targeting is preferred for MCP-launched sessions.

- [ ] **Step 5: Run MCP tests and commit**

```powershell
git add -- "MCP/Ansys/AEDT MCP/mcp_server.py" "MCP/Ansys/AEDT MCP/tests/test_mcp_tools.py"
git commit -m "Route AEDT MCP tools through PyAEDT workers"
```

### Task 8: Remove the legacy bridge and rewrite documentation

**Files:**
- Delete: `MCP/Ansys/AEDT MCP/aedt_mcp_bridge.py`
- Delete: `MCP/Ansys/AEDT MCP/aedt_socket_protocol.py`
- Delete: `MCP/Ansys/AEDT MCP/cleanup_aedt_mcp_state_in_aedt.py`
- Delete: `MCP/Ansys/AEDT MCP/reload_bridge_in_aedt.py`
- Delete: `MCP/Ansys/AEDT MCP/stop_bridge_in_aedt.py`
- Delete: `MCP/Ansys/AEDT MCP/stop_mcp.py`
- Delete: `MCP/Ansys/AEDT MCP/scripts/dismiss_aedt_dialog.ps1`
- Delete: `MCP/Ansys/AEDT MCP/scripts/install_aedt_mcp_autostart.ps1`
- Delete: `MCP/Ansys/AEDT MCP/scripts/install_aedt_toolkit_button.ps1`
- Delete: `MCP/Ansys/AEDT MCP/scripts/launch_aedt_with_mcp_bridge.ps1`
- Delete: `MCP/Ansys/AEDT MCP/scripts/probe_scriptenv_release.py`
- Delete: `MCP/Ansys/AEDT MCP/scripts/run_cleanup_in_aedt.ps1`
- Delete: `MCP/Ansys/AEDT MCP/scripts/run_cleanup_via_aedt_ui.ps1`
- Delete: `MCP/Ansys/AEDT MCP/scripts/start_aedt_mcp_bridge_in_aedt.py`
- Delete: `MCP/Ansys/AEDT MCP/scripts/stop_aedt_mcp_bridge_in_aedt.py`
- Delete: `MCP/Ansys/AEDT MCP/scripts/uninstall_aedt_toolkit_button.ps1`
- Delete/replace: `tests/test_protocol.py`, `tests/test_bridge_idle_timeout.py`, `tests/test_mcp_server_cleanup.py`, `tests/test_autostart_scripts.py`
- Rewrite: `MCP/Ansys/AEDT MCP/README.md`
- Rewrite: `MCP/Ansys/AEDT MCP/README.zh-CN.md`
- Rewrite: `MCP/Ansys/AEDT MCP/.env.example`
- Rewrite: `MCP/Ansys/AEDT MCP/examples/mcp_config.example.json`
- Create: `MCP/Ansys/AEDT MCP/scripts/remove_legacy_aedt_mcp_toolbar.ps1`

- [ ] **Step 1: Add documentation assertions**

Create `tests/test_package_migration.py` asserting that supported docs contain `PyAEDT`, `pid`, `port`, and `release_desktop`, and do not instruct users to start an in-AEDT bridge. Assert obsolete raw bridge modules are absent.

- [ ] **Step 2: Run the migration test and verify failure**

Expected: failures identify the remaining bridge files and instructions.

- [ ] **Step 3: Remove obsolete bridge implementation**

Delete only files owned by the legacy AEDT MCP bridge. Preserve the existing toolbar backup in the AEDT installation directory; the migration script may remove active legacy toolbar entries but must not delete backups or unrelated Toolkit configuration.

- [ ] **Step 4: Rewrite configuration and bilingual documentation**

Document installation, explicit PID/port targeting, visible launch, supported tools, worker isolation, logs, graceful release, and the absence of any in-AEDT resident code. Configure `AEDT_VERSION`, `AEDT_INSTALL_DIR`, `AEDT_WORKER_TIMEOUT`, `AEDT_LAUNCH_TIMEOUT`, and `AEDT_LOG_DIR`.

- [ ] **Step 5: Run the full offline test suite**

Run: `cd "MCP/Ansys/AEDT MCP"; .\.venv\Scripts\python.exe -m pytest -q`

Expected: all unit and fake integration tests pass without AEDT running.

- [ ] **Step 6: Commit**

```powershell
git add -A -- "MCP/Ansys/AEDT MCP"
git commit -m "Remove the resident AEDT bridge"
```

### Task 9: Install PyAEDT and run live AEDT 2026 R1 acceptance tests

**Files:**
- Create: `MCP/Ansys/AEDT MCP/tests/live/test_aedt_2026r1.py`
- Create: `MCP/Ansys/AEDT MCP/scripts/run_live_acceptance.ps1`
- Modify: `MCP/Ansys/AEDT MCP/README.md`
- Modify: `MCP/Ansys/AEDT MCP/README.zh-CN.md`

- [ ] **Step 1: Install the selected stable PyAEDT dependency**

Use the MCP virtual environment and the package constraint recorded in `pyproject.toml`. Verify with `python -c "import ansys.aedt.core; print(ansys.aedt.core.__version__)"` and record the resolved version in the acceptance log.

- [ ] **Step 2: Write opt-in live tests**

Mark tests with `pytest.mark.live_aedt`. Require `RUN_AEDT_LIVE_TESTS=1`. The tests must launch a disposable visible gRPC session, use only a disposable project directory under the repository test artifacts folder, perform ten sequential worker calls, create/save a minimal HFSS design, start a bounded analysis or validate setup submission, and verify all workers have exited.

- [ ] **Step 3: Add a normal-close dialog detector**

The PowerShell harness must request normal window close for only the disposable AEDT PID and wait for exit. It must detect the exact busy-dialog text and fail if the dialog appears. On failure it leaves AEDT running for inspection; it must not force-kill AEDT.

- [ ] **Step 4: Run gRPC launch-mode acceptance**

Run the live harness with AEDT 2026 R1. Expected: visible GUI, explicit PID/port telemetry, successful structured operations, no remaining workers, and normal close without the busy dialog.

- [ ] **Step 5: Run PID attach-mode acceptance**

Launch a second disposable graphical AEDT normally, pass its exact PID to read-only/project-save workers, release after each call, and request normal close. Expected: no busy dialog and no connection to any other AEDT process.

- [ ] **Step 6: Run two-session targeting acceptance**

Keep two disposable AEDT sessions open. Verify missing target is rejected and a request for each explicit PID/port reports the matching process and project only.

- [ ] **Step 7: Run final verification**

Run offline tests, live tests, `git diff --check`, and a process scan proving no `pyaedt_worker.py` remains. Save sanitized logs under `MCP/Ansys/AEDT MCP/test-artifacts/` and exclude volatile project/result data through `.gitignore`.

- [ ] **Step 8: Commit**

```powershell
git add -- "MCP/Ansys/AEDT MCP/tests/live" "MCP/Ansys/AEDT MCP/scripts/run_live_acceptance.ps1" "MCP/Ansys/AEDT MCP/README.md" "MCP/Ansys/AEDT MCP/README.zh-CN.md" "MCP/Ansys/AEDT MCP/.gitignore"
git commit -m "Verify PyAEDT MCP against AEDT 2026 R1"
```

## Final verification checklist

- [ ] `pytest -q` passes without requiring AEDT.
- [ ] PyAEDT imports from the MCP virtual environment.
- [ ] No supported module starts code inside AEDT.
- [ ] Every targeted MCP tool requires exactly one PID or port.
- [ ] The MCP process owns no live PyAEDT Desktop object.
- [ ] Worker timeout affects only the worker process.
- [ ] gRPC-launched graphical AEDT passes normal-close testing.
- [ ] PID-attached graphical AEDT passes normal-close testing.
- [ ] Two simultaneous AEDT sessions cannot be confused.
- [ ] English and Chinese documentation match the implemented behavior.
