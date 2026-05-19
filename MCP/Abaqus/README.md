# Abaqus MCP

This folder contains a portable MCP server plus an Abaqus/CAE file-based IPC plugin. It lets MCP-capable clients execute scripts, inspect models, list and submit jobs, inspect ODB files, and capture viewport images through a running Abaqus/CAE session.

Only reusable source files and templates are included. Runtime command files, results, screenshots, logs, status files, solver outputs, and private local paths are intentionally excluded.

## Contents

- `mcp_server.py` runs outside Abaqus and exposes MCP tools.
- `abaqus_mcp_plugin.py` runs inside Abaqus/CAE and processes file-based commands.
- `abaqus_plugins/mcp_control/` adds Abaqus GUI menu entries for start, stop, and status.
- `stop_mcp.py` writes `stop.flag` to request a running plugin loop to stop.
- `abaqus_v6.env.example` shows how to auto-load the plugin on Abaqus startup.
- `.env.example` documents the environment variables used by the server and plugin.
- `examples/mcp_config.example.json` shows a generic MCP client configuration.

## Install

From this folder:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -U pip
.\.venv\Scripts\python.exe -m pip install -e .
```

Copy `.env.example` to `.env` if your MCP client loads environment files. Otherwise set `ABAQUS_MCP_HOME` directly in the MCP client configuration.

## MCP Client Setup Prompts

Copy one of these prompts into the MCP-capable client you want to use. Replace `<repo>` with the absolute path to this folder, for example `C:\path\to\text-to-cae\MCP\Abaqus`.

### Codex

```text
Install this local Abaqus MCP server for Codex.

Project folder:
<repo>

Please configure Codex MCP with a stdio server named `abaqus-mcp-server`:
- command: <repo>\.venv\Scripts\python.exe
- args: ["<repo>\mcp_server.py"]
- cwd: <repo>
- env:
  - ABAQUS_MCP_HOME=<repo>

If the virtual environment does not exist, create it and install the project with:
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -U pip
.\.venv\Scripts\python.exe -m pip install -e .

After configuring the server, verify it by listing MCP tools. Then open Abaqus/CAE, load `abaqus_mcp_plugin.py`, run `mcp_start()` or `mcp_loop()`, and run `get_model_info` from the MCP client.
```

### Claude Code

```text
Add this local Abaqus MCP server to Claude Code.

Project folder:
<repo>

Use a stdio MCP server named `abaqus-mcp-server`:
- command: <repo>\.venv\Scripts\python.exe
- args: ["<repo>\mcp_server.py"]
- cwd: <repo>
- env:
  - ABAQUS_MCP_HOME=<repo>

Create `.venv` and run `pip install -e .` if dependencies are missing. Restart Claude Code, confirm the Abaqus MCP tools are available, then test with `get_model_info` after starting the plugin inside Abaqus/CAE.
```

### Claude Desktop

```text
Help me add this local Abaqus MCP server to Claude Desktop.

Project folder:
<repo>

Create or update Claude Desktop's MCP configuration with a stdio server:

"abaqus-mcp-server": {
  "command": "<repo>\\.venv\\Scripts\\python.exe",
  "args": ["<repo>\\mcp_server.py"],
  "cwd": "<repo>",
  "env": {
    "ABAQUS_MCP_HOME": "<repo>"
  }
}

Create the virtual environment first if needed, then restart Claude Desktop and verify that the Abaqus MCP tools appear.
```

### Cursor

```text
Configure this local Abaqus MCP server in Cursor.

Project folder:
<repo>

Add a stdio MCP server named `abaqus-mcp-server` using:
- command: <repo>\.venv\Scripts\python.exe
- args: ["<repo>\mcp_server.py"]
- cwd: <repo>
- environment:
  - ABAQUS_MCP_HOME=<repo>

If `.venv` is missing, create it and install dependencies with `pip install -e .`. Reload Cursor and run a tool discovery check.
```

### Generic MCP Client

```json
{
  "mcpServers": {
    "abaqus-mcp-server": {
      "command": "<repo>\\.venv\\Scripts\\python.exe",
      "args": ["<repo>\\mcp_server.py"],
      "cwd": "<repo>",
      "env": {
        "ABAQUS_MCP_HOME": "<repo>"
      }
    }
  }
}
```

## Configure Abaqus/CAE

### Option 1: Run the kernel plugin manually

In Abaqus/CAE:

1. Open `File > Run Script...`
2. Select `<repo>\abaqus_mcp_plugin.py`
3. In the Abaqus Python console, run one of:

```python
mcp_start()       # background mode, convenient but may depend on Abaqus build stability
mcp_coop_loop()   # cooperative loop
mcp_loop()        # blocking loop, most conservative
```

### Option 2: Auto-load on startup

Copy `abaqus_v6.env.example` to your Abaqus startup environment file and set `ABAQUS_MCP_HOME` if this project is not installed at the default `~/.abaqus-mcp` path.

Windows example:

```powershell
Copy-Item "<repo>\abaqus_v6.env.example" "$env:USERPROFILE\abaqus_v6.env"
```

### Option 3: Install the GUI menu

Copy `abaqus_plugins/mcp_control` into your Abaqus user plugins directory:

```powershell
Copy-Item -Recurse "<repo>\abaqus_plugins\mcp_control" "$env:USERPROFILE\abaqus_plugins\mcp_control"
```

Then use `Plug-ins > MCP` in Abaqus/CAE to start, stop, or check status.

## MCP Tools

- `check_abaqus_connection`
- `execute_script`
- `get_model_info`
- `list_jobs`
- `submit_job`
- `get_odb_info`
- `get_viewport_image`
- `ping`

The server also exposes the resource `abaqus://status`.

## Reliability Note

If `check_abaqus_connection` reports an unknown error, do not assume the bridge is unusable. A stronger validation is to call `get_model_info`, then run a minimal `execute_script` such as `print("ABAQUS_MCP_SCRIPT_OK")`.

## Notes

This project requires a licensed Abaqus/CAE installation on the user's machine. It does not include Abaqus binaries, analysis results, or private local configuration.
