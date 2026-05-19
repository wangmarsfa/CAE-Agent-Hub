# Abaqus MCP

这个目录包含一个可移植的 MCP 服务器，以及一个运行在 Abaqus/CAE 内部的文件 IPC 插件。支持 MCP 的客户端可以通过它执行 Abaqus 脚本、查看模型信息、列出和提交作业、读取 ODB 元数据，并抓取视口图片。

本目录只包含可复用源码和配置模板，不包含运行时命令文件、结果、截图、日志、状态文件、求解输出或私有本机路径。

## 内容

- `mcp_server.py` 在 Abaqus 外部运行，并暴露 MCP 工具。
- `abaqus_mcp_plugin.py` 在 Abaqus/CAE 内部运行，负责处理文件队列命令。
- `abaqus_plugins/mcp_control/` 为 Abaqus 增加启动、停止和状态查看菜单。
- `stop_mcp.py` 写入 `stop.flag`，用于请求正在运行的插件循环停止。
- `abaqus_v6.env.example` 展示如何在 Abaqus 启动时自动加载插件。
- `.env.example` 说明服务器和插件使用的环境变量。
- `examples/mcp_config.example.json` 提供通用 MCP 客户端配置示例。

## 安装

在本目录下执行：

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -U pip
.\.venv\Scripts\python.exe -m pip install -e .
```

如果你的 MCP 客户端会读取环境文件，可以复制 `.env.example` 为 `.env`。否则请直接在 MCP 客户端配置里设置 `ABAQUS_MCP_HOME`。

## MCP 客户端安装提示词

把下面对应客户端的提示词复制到支持 MCP 的客户端里使用。请把 `<repo>` 替换成本目录的绝对路径，例如 `C:\path\to\text-to-cae\MCP\Abaqus`。

### Codex

```text
请为 Codex 安装这个本地 Abaqus MCP server。

项目目录：
<repo>

请在 Codex MCP 配置里添加一个名为 `abaqus-mcp-server` 的 stdio server：
- command: <repo>\.venv\Scripts\python.exe
- args: ["<repo>\mcp_server.py"]
- cwd: <repo>
- env:
  - ABAQUS_MCP_HOME=<repo>

如果虚拟环境还不存在，请先创建并安装依赖：
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -U pip
.\.venv\Scripts\python.exe -m pip install -e .

配置完成后，请通过列出 MCP tools 来验证。然后打开 Abaqus/CAE，加载 `abaqus_mcp_plugin.py`，运行 `mcp_start()` 或 `mcp_loop()`，再从 MCP 客户端运行 `get_model_info`。
```

### Claude Code

```text
请把这个本地 Abaqus MCP server 添加到 Claude Code。

项目目录：
<repo>

使用名为 `abaqus-mcp-server` 的 stdio MCP server：
- command: <repo>\.venv\Scripts\python.exe
- args: ["<repo>\mcp_server.py"]
- cwd: <repo>
- env:
  - ABAQUS_MCP_HOME=<repo>

如果依赖缺失，请创建 `.venv` 并运行 `pip install -e .`。然后重启 Claude Code，确认 Abaqus MCP tools 已可用；在 Abaqus/CAE 内启动插件后，用 `get_model_info` 做一次测试。
```

### Claude Desktop

```text
请帮我把这个本地 Abaqus MCP server 添加到 Claude Desktop。

项目目录：
<repo>

请创建或更新 Claude Desktop 的 MCP 配置，添加如下 stdio server：

"abaqus-mcp-server": {
  "command": "<repo>\\.venv\\Scripts\\python.exe",
  "args": ["<repo>\\mcp_server.py"],
  "cwd": "<repo>",
  "env": {
    "ABAQUS_MCP_HOME": "<repo>"
  }
}

如果虚拟环境还不存在，请先创建虚拟环境。然后重启 Claude Desktop，并确认 Abaqus MCP tools 出现在工具列表里。
```

### Cursor

```text
请在 Cursor 中配置这个本地 Abaqus MCP server。

项目目录：
<repo>

添加一个名为 `abaqus-mcp-server` 的 stdio MCP server：
- command: <repo>\.venv\Scripts\python.exe
- args: ["<repo>\mcp_server.py"]
- cwd: <repo>
- environment:
  - ABAQUS_MCP_HOME=<repo>

如果 `.venv` 不存在，请创建虚拟环境并安装依赖：`pip install -e .`。保存 MCP 设置后，重新加载 Cursor，并执行一次 tool discovery 检查。
```

### 通用 MCP Client

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

## 配置 Abaqus/CAE

### 方式 1：手动运行 kernel 插件

在 Abaqus/CAE 中：

1. 打开 `File > Run Script...`
2. 选择 `<repo>\abaqus_mcp_plugin.py`
3. 在 Abaqus Python console 中运行：

```python
mcp_start()       # 后台模式，使用方便，但稳定性可能受 Abaqus 版本影响
mcp_coop_loop()   # 协作循环模式
mcp_loop()        # 阻塞循环模式，最保守
```

### 方式 2：启动时自动加载

把 `abaqus_v6.env.example` 复制为你的 Abaqus 启动环境文件。如果项目没有安装在默认的 `~/.abaqus-mcp` 路径，请设置 `ABAQUS_MCP_HOME`。

Windows 示例：

```powershell
Copy-Item "<repo>\abaqus_v6.env.example" "$env:USERPROFILE\abaqus_v6.env"
```

### 方式 3：安装 GUI 菜单

把 `abaqus_plugins/mcp_control` 复制到 Abaqus 用户插件目录：

```powershell
Copy-Item -Recurse "<repo>\abaqus_plugins\mcp_control" "$env:USERPROFILE\abaqus_plugins\mcp_control"
```

然后可以在 Abaqus/CAE 中通过 `Plug-ins > MCP` 启动、停止或查看状态。

## MCP 工具

- `check_abaqus_connection`
- `execute_script`
- `get_model_info`
- `list_jobs`
- `submit_job`
- `get_odb_info`
- `get_viewport_image`
- `ping`

服务器还暴露资源：`abaqus://status`。

## 可靠性说明

如果 `check_abaqus_connection` 返回 unknown error，不要立刻判断桥接不可用。更可靠的验证方式是先调用 `get_model_info`，再运行一个最小 `execute_script`，例如 `print("ABAQUS_MCP_SCRIPT_OK")`。

## 说明

本项目需要用户机器上有可用且授权的 Abaqus/CAE 安装。它不包含 Abaqus 二进制文件、分析结果或私有本机配置。
