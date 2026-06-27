# PyAEDT-based AEDT MCP redesign

## Status

Approved architecture, pending implementation planning.

## Context

The current AEDT MCP runs a raw TCP server inside the Ansys Electronics Desktop
(AEDT) scripting process. That server retains Automation state and background
threads in the AEDT process. In AEDT 2026 R1, a session that has used this bridge
can remain marked as busy after the bridge port is closed, which prevents the
user from closing AEDT normally.

The replacement must preserve Codex control of a visible AEDT session without
installing or running a persistent script, extension, socket server, or toolbar
bridge inside AEDT.

## Goals

- Use PyAEDT as the only supported AEDT automation API.
- Keep the AEDT 2026 R1 graphical interface visible during modeling and solving.
- Support both attaching to an existing AEDT process and launching a new AEDT
  gRPC session.
- Require an explicit AEDT process ID or gRPC port whenever a tool targets a
  session. Discovery must never silently select a session.
- Isolate every AEDT operation in a short-lived worker process.
- Release PyAEDT references after every operation without closing the user's
  projects or AEDT process.
- Allow a timed-out or failed worker to be terminated without terminating AEDT.
- Preserve the useful structured tools from the current MCP and add asynchronous
  analysis status monitoring.
- Verify that AEDT can close normally after MCP operations.

## Non-goals

- Do not emulate mouse clicks or menu interactions.
- Do not keep a persistent PyAEDT object in the MCP server.
- Do not automatically choose the newest or foreground AEDT process.
- Do not terminate a user-owned AEDT process as error recovery.
- Do not expose unrestricted Python execution by default.
- Do not support AEDT versions older than the installed 2026 R1 release in the
  first implementation.

## Architecture

```text
Codex
  -> FastMCP stdio server
  -> worker subprocess (one command)
  -> PyAEDT
  -> explicit PID or gRPC port
  -> graphical AEDT 2026 R1
```

The FastMCP process owns MCP protocol handling, validation, target-level locking,
worker timeouts, and JSON result normalization. It does not import or retain a
live PyAEDT `Desktop` object.

For each MCP operation, the server launches one worker subprocess. The worker
connects to exactly one AEDT target, performs exactly one command, returns one
JSON response, releases PyAEDT in a `finally` block, and exits. The release call
must preserve the running AEDT instance and its open projects:

```python
desktop.release_desktop(close_projects=False, close_on_exit=False)
```

The gRPC transport is preferred for sessions launched by the MCP. PID attachment
is provided for user-launched graphical sessions. Both paths use the same worker
command contract and release policy.

## Components

### `mcp_server.py`

- Defines the public MCP tools and resources.
- Validates that each targeted operation receives exactly one of `pid` or
  `port`.
- Serializes mutating calls per target while allowing independent AEDT sessions
  to run concurrently.
- Starts workers with a bounded timeout and captures stdout, stderr, and exit
  status.
- Converts worker failures into concise MCP errors without leaking protocol data
  onto stdio.

### `pyaedt_worker.py`

- Accepts one JSON request through stdin and emits one JSON response through
  stdout.
- Imports PyAEDT only inside the worker process.
- Connects using an explicit PID or gRPC port.
- Resolves the requested project, design, and setup without silently creating a
  different target unless the command explicitly requests creation.
- Executes one command and serializes only JSON-compatible output.
- Releases Desktop references in `finally` and exits.

### `session_discovery.py`

- Discovers AEDT 2026 R1 processes and available gRPC sessions using supported
  PyAEDT/session APIs and read-only operating-system metadata.
- Returns PID, port when known, AEDT version, connection mode, and basic project
  metadata when it can be obtained safely.
- Returns all candidates; it never marks one as implicitly selected.

### `aedt_launcher.py`

- Selects or validates an unused localhost gRPC port.
- Starts AEDT 2026 R1 in graphical gRPC server mode.
- Waits for the port and a PyAEDT health probe before reporting success.
- Returns the PID and port needed by all later tool calls.
- Does not close the launched AEDT when the MCP server exits.

### Target locks

The MCP server keeps an in-memory lock per normalized target (`pid:<id>` or
`port:<port>`). A mutating operation cannot overlap another operation on the same
target. Read-only status polling may run concurrently only after live testing
shows that AEDT 2026 R1 handles it reliably; the initial implementation will
serialize all calls per target.

## Public MCP tools

### Session tools

- `list_aedt_sessions()` returns all discoverable AEDT sessions.
- `launch_aedt(version="2026.1", port=0)` launches a visible gRPC session and
  returns its PID and selected port.
- `check_aedt_connection(pid=None, port=None)` runs a real PyAEDT health probe.
- `release_connection(pid=None, port=None)` performs an explicit attach/release
  smoke test. It never closes projects or AEDT.

### Project and HFSS tools

- `get_project_info(pid=None, port=None)` returns active project, design, type,
  setups, sweeps, and solution state.
- `create_hfss_design(pid=None, port=None, project_name, design_name,
  solution_type="DrivenModal")` creates or activates the requested design.
- `save_project(pid=None, port=None, path="")` saves the active project or saves
  it to an explicit path.

### Analysis tools

- `start_analysis(pid=None, port=None, project_name, design_name, setup_name,
  blocking=False)` starts analysis in the graphical AEDT session. The default is
  non-blocking so Codex can continue polling.
- `get_analysis_status(pid=None, port=None, project_name, design_name,
  setup_name="")` returns running state and available setup/solution metadata.

The first implementation will not expose arbitrary Python execution. Additional
structured PyAEDT tools can be added after the lifecycle and shutdown acceptance
tests pass. An unsafe script tool, if ever needed, must be opt-in through a
separate environment flag and is outside this initial scope.

## Worker protocol

The MCP server sends a single request:

```json
{
  "request_id": "uuid",
  "command": "get_project_info",
  "target": {"kind": "port", "value": 50051},
  "timeout_seconds": 30,
  "arguments": {}
}
```

The worker writes exactly one response to stdout:

```json
{
  "request_id": "uuid",
  "ok": true,
  "result": {}
}
```

PyAEDT logs and diagnostics must go to stderr or a log file. A failed response
uses `ok: false` and contains a stable error code, human-readable message, and
optional diagnostic detail. Tracebacks are retained in logs but are not returned
by default.

## Session lifecycle

### Attach to an existing AEDT process

1. The caller obtains candidates from `list_aedt_sessions`.
2. The caller supplies a specific PID.
3. A worker attaches with `new_desktop=False` and that process ID.
4. The worker executes one command.
5. The worker releases Desktop without closing projects or AEDT and exits.

If PID attachment is unsupported or ambiguous in the installed PyAEDT version,
the worker returns an explicit `unsupported_attach` error. It must not fall back
to another running process.

### Launch and use a gRPC session

1. `launch_aedt` chooses or validates a localhost port.
2. AEDT starts visibly in gRPC server mode.
3. A health worker verifies the exact port and reports PID plus port.
4. Later tools target that port explicitly.
5. Each worker releases its client connection after the operation.
6. AEDT remains open until the user closes it or a future explicit close tool is
   requested. The initial implementation will not provide a force-close tool.

## Error handling

- Invalid or missing target: reject before starting a worker.
- Multiple possible sessions: return candidates and require explicit selection.
- Connection failure: report the requested PID/port and do not try another one.
- Worker timeout: terminate only the worker process, collect diagnostics, and
  leave AEDT running.
- PyAEDT exception: release in `finally`, return a normalized error, and exit
  nonzero.
- Analysis already running: return a conflict result rather than start a second
  solve on the same target.
- Lost AEDT process: return `session_not_found`; do not relaunch automatically.
- MCP shutdown: no AEDT cleanup request is needed because no live Desktop object
  is retained in the MCP process.

## Configuration

The package will depend on a stable PyAEDT release compatible with AEDT 2026 R1.
Configuration will replace the raw bridge variables with:

- `AEDT_VERSION=2026.1`
- `AEDT_INSTALL_DIR` for explicit installation discovery when needed.
- `AEDT_WORKER_TIMEOUT=60`
- `AEDT_LAUNCH_TIMEOUT=120`
- `AEDT_LOG_DIR` for worker diagnostics.

Host, raw TCP bridge port, token, idle timeout, and stop-on-exit variables will be
removed. A gRPC port is a per-session target returned by `launch_aedt`, not a
hidden global default.

## Migration

- Replace the raw socket client in `mcp_server.py` with worker orchestration.
- Add the worker, discovery, launcher, target validation, and structured command
  modules.
- Remove `aedt_mcp_bridge.py`, raw socket protocol code, bridge launch/reload/stop
  scripts, toolbar installers, and bridge cleanup utilities from the supported
  package.
- Keep one migration note explaining how to remove any previously installed AEDT
  toolbar entries. Do not reinstall a PyAEDT toolbar extension for MCP operation.
- Rewrite the English and Chinese documentation and MCP configuration example.
- Replace bridge-specific tests instead of preserving obsolete behavior.

Existing unrelated workspace changes must not be reverted during migration.

## Testing

### Unit tests

- Target validation accepts exactly one PID or port.
- Worker request and response envelopes are stable and JSON-only.
- Worker release executes on success, command failure, and serialization failure.
- MCP timeouts terminate the worker but never call an AEDT termination API.
- Per-target locking serializes calls to the same target.
- Session discovery never auto-selects a candidate.
- Tool result and error normalization is deterministic.

### Integration tests with fakes

- Fake PyAEDT verifies PID and port connection arguments.
- Project/design lookup does not silently switch targets.
- Non-blocking analysis returns and can be followed by status polling.
- Launcher waits for both process and port readiness.

### Live AEDT 2026 R1 acceptance tests

1. Launch a disposable graphical gRPC AEDT session through MCP.
2. Verify PID, port, version, active project, and active design.
3. Create and save a disposable HFSS project.
4. Start a small non-blocking analysis and poll until completion or a bounded
   timeout.
5. Perform at least ten sequential worker operations and confirm no worker or
   Automation client remains afterward.
6. Close the disposable AEDT session through the normal window close control and
   confirm no "being used by another application, script or extension wizard"
   dialog appears.
7. Start a second disposable graphical AEDT normally, attach by explicit PID,
   perform read-only and save operations, release, and repeat the normal close
   test.
8. Run two sessions concurrently and verify that tools reject missing targets and
   operate only on the explicitly selected PID or port.

The redesign is not complete until both gRPC launch mode and PID attach mode pass
the normal-close acceptance test.

## Completion criteria

- The MCP package no longer requires any code to run persistently inside AEDT.
- Both connection modes work against AEDT 2026 R1 with explicit targeting.
- Modeling changes and analysis progress remain visible in graphical AEDT.
- Every worker releases PyAEDT and exits after one command.
- Codex can query project state and run the supported HFSS workflow end to end.
- AEDT closes normally after both connection modes without the busy dialog.
- Unit, fake integration, and live acceptance tests are documented and pass.
