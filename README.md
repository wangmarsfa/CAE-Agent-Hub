# Text to CAE 使用教程

这是一个本地运行的 Text-to-CAE 工作区，用浏览器界面展示 Abaqus/CAE 案例、参数、模型树、结果云图和动态过程。项目包含前端 viewer、多个 Abaqus 示例脚本，以及已导出的部分结果数据。

GitHub 仓库：

```text
https://github.com/Cai-aa/text-to-cae
```

## 1. 环境准备

需要安装：

- Windows
- Node.js 18 或更高版本
- npm
- Abaqus/CAE，可选；只查看已导出的结果不需要 Abaqus，重新求解才需要
- Git，可选；从 GitHub 拉取项目时需要

Abaqus 默认命令路径是：

```text
G:\SIMULIA\Commands\abaqus.bat
```

如果你的 Abaqus 安装路径不同，启动 viewer 前需要设置 `ABAQUS_COMMAND`。

## 2. 获取项目

如果从 GitHub 克隆：

```powershell
git clone https://github.com/Cai-aa/text-to-cae.git
Set-Location .\text-to-cae
```

如果使用当前本地目录：

```powershell
Set-Location E:\Users\Cai\Downloads\text-to-cae
```

## 3. 安装前端依赖

进入 viewer 目录并安装依赖：

```powershell
Set-Location .\viewer
npm.cmd install
```

本地当前机器如果已经有 `viewer\node_modules`，可以跳过安装。

## 4. 启动浏览器 viewer

在 `viewer` 目录运行：

```powershell
npm.cmd run dev
```

默认打开：

```text
http://127.0.0.1:4178/
```

如果端口被占用，可以指定端口：

```powershell
$env:VIEWER_PORT = "4181"
npm.cmd run dev
```

然后打开：

```text
http://127.0.0.1:4181/
```

## 5. 打开指定案例

可以通过 URL 参数直接进入某个 CAE 案例：

```text
http://127.0.0.1:4178/?case=cantilever
http://127.0.0.1:4178/?case=hole-plate
http://127.0.0.1:4178/?case=hole-plate-modal
http://127.0.0.1:4178/?case=sphere-impact
http://127.0.0.1:4178/?case=milling-3d
http://127.0.0.1:4178/?case=bullet-plate
```

加上 `mode=cae` 可以直接进入 Abaqus 风格界面：

```text
http://127.0.0.1:4178/?case=sphere-impact&mode=cae
```

## 6. 界面说明

页面主要分为三块：

- 左侧模型树：展示项目、零件、材料、装配、分析步、载荷、边界条件、网格、作业和结果。
- 中间三维视窗：显示 Abaqus 风格的结果云图、网格边线、动态帧、刀具/球/弹体等对象。
- 右侧参数和结果面板：显示状态、结果指标、可编辑参数和运行按钮。

顶部工具条包含：

- `播放`：播放动态结果帧。
- `速度 0.5x / 1x / 2x`：调整播放速度。
- 时间帧滑条：手动查看某一时刻。
- `Abaqus / 深色 / 浅色`：切换显示风格。

鼠标操作：

- 左键拖动：旋转模型。
- 中键拖动：平移模型。
- 滚轮：缩放模型。

## 7. 编辑参数并重新求解

支持在浏览器里编辑参数的案例会显示“可编辑参数”区域。常见参数包括：

- 几何尺寸，例如长度、宽度、厚度、孔半径、球半径。
- 材料参数，例如弹性模量和泊松比。
- 冲击速度、切削速度、刀具直径、网格种子等。

修改参数后，点击运行按钮会调用 Abaqus：

```text
viewer -> /__cae/run -> Abaqus noGUI -> 导出 result_mesh.json -> 浏览器刷新结果
```

如果 Abaqus 不在默认路径，先设置：

```powershell
$env:ABAQUS_COMMAND = "C:\SIMULIA\Commands\abaqus.bat"
npm.cmd run dev
```

运行完成后，右侧结果指标会更新，三维窗口会读取新的 `result_mesh.json`。

## 8. 案例说明

### 悬臂梁

目录：

```text
models/text-to-cae
```

用途：静力学入门案例，展示悬臂梁位移和应力云图。

主要文件：

- `cantilever_beam_abaqus.py`
- `export_result_mesh.py`
- `cae_project.json`
- `result_mesh.json`

### 带孔板拉伸

目录：

```text
models/text-to-cae-hole-plate
```

用途：展示带圆孔板在拉伸载荷下的应力集中。

### 带孔板模态

目录：

```text
models/text-to-cae-hole-plate-modal
```

用途：展示模态分析结果，可以在 viewer 中查看不同阶振型。

### 球冲击板材

目录：

```text
models/text-to-cae-sphere-impact
```

用途：展示钢球冲击固支板材的显式动力学过程。

当前版本采用更真实的球-板接触显示：

- 钢球以初速度冲击板面。
- 板材中心出现连续圆形压痕。
- 接触核和外圈弯曲区域有应力集中。
- 回弹阶段球与板材不穿模。

关键文件：

- `sphere_impact_abaqus.py`：Abaqus 显式接触建模脚本。
- `export_dynamic_mesh.py`：从 ODB 导出动态结果。
- `refresh_contact_result.mjs`：重新生成当前 viewer 展示用的接触可视化结果。

单独刷新展示数据：

```powershell
Set-Location E:\Users\Cai\Downloads\text-to-cae
node models\text-to-cae-sphere-impact\refresh_contact_result.mjs
```

### 三维铣削动力学

目录：

```text
models/text-to-cae-milling-3d
```

用途：展示端铣刀切削工件的三维动态过程。

当前版本对可视化做了修正：

- 工件尺寸更大。
- 网格更细。
- 切削槽按刀具直径生成。
- 切削后槽为长方形平底槽。
- 不再用分层变形假装材料去除。

由于 `result_mesh.json` 超过 GitHub 单文件限制，仓库中不上传该文件。克隆仓库后如果要查看铣削结果，需要重新导出或运行刷新脚本：

```powershell
Set-Location E:\Users\Cai\Downloads\text-to-cae
node models\text-to-cae-milling-3d\refresh_visual_result.mjs
```

### 弹体侵彻板材

目录：

```text
models/text-to-cae-bullet-plate
```

用途：展示弹体高速侵彻板材的三维显式动力学过程。

注意：大型 `.odb` 文件没有上传到 GitHub，需要本地 Abaqus 重新求解才能获得完整 ODB。

## 9. 直接运行 Abaqus 脚本

也可以不通过浏览器，直接在命令行运行某个案例。

示例：球冲击板材

```powershell
Set-Location E:\Users\Cai\Downloads\text-to-cae
& "G:\SIMULIA\Commands\abaqus.bat" cae noGUI=models\text-to-cae-sphere-impact\sphere_impact_abaqus.py
& "G:\SIMULIA\Commands\abaqus.bat" cae noGUI=models\text-to-cae-sphere-impact\export_dynamic_mesh.py
```

示例：三维铣削

```powershell
Set-Location E:\Users\Cai\Downloads\text-to-cae
& "G:\SIMULIA\Commands\abaqus.bat" cae noGUI=models\text-to-cae-milling-3d\milling_abaqus.py
& "G:\SIMULIA\Commands\abaqus.bat" cae noGUI=models\text-to-cae-milling-3d\export_milling_mesh.py
```

## 10. 文件结构

```text
text-to-cae/
  README.md
  models/
    text-to-cae/
    text-to-cae-hole-plate/
    text-to-cae-hole-plate-modal/
    text-to-cae-sphere-impact/
    text-to-cae-milling-3d/
    text-to-cae-bullet-plate/
  viewer/
    package.json
    vite.config.mjs
    main.jsx
    components/
      CaeResultViewer.js
      TextToCaeWorkspace.js
```

每个 `models/text-to-cae-*` 案例通常包含：

- `cae_parameters.json`：可编辑参数。
- `cae_project.json`：项目说明、模型树、结果指标。
- `*_abaqus.py`：Abaqus 建模和求解脚本。
- `export_*.py`：ODB 结果导出脚本。
- `result_mesh.json`：浏览器读取的结果网格和云图数据。

## 11. GitHub 上传说明

仓库已经上传为私有仓库：

```text
https://github.com/Cai-aa/text-to-cae
```

没有上传的内容：

- `viewer/node_modules/`
- `viewer/dist/`
- Abaqus `.odb`
- Abaqus `.inp`
- Abaqus 中间文件，例如 `.sim`、`.dat`、`.msg`、`.sta`
- Python `__pycache__`
- 正交切削旧案例目录
- 超过 100MB 的铣削 `result_mesh.json`

这些文件可以通过安装依赖或重新运行 Abaqus 脚本生成。

后续更新并推送：

```powershell
Set-Location E:\Users\Cai\Downloads\text-to-cae
git status
git add -A
git commit -m "Update CAE viewer"
git push
```

## 12. 常见问题

### 页面打不开

确认 dev server 是否启动：

```powershell
Set-Location E:\Users\Cai\Downloads\text-to-cae\viewer
npm.cmd run dev
```

然后使用终端显示的端口访问，例如：

```text
http://127.0.0.1:4178/
```

### 修改了结果文件但页面没变

点击右侧“刷新”，或直接刷新浏览器页面。`result_mesh.json` 是运行时读取的，旧页面可能还缓存着上一帧数据。

### 点击运行后 Abaqus 不启动

检查 `ABAQUS_COMMAND` 是否指向正确的 Abaqus 命令脚本：

```powershell
$env:ABAQUS_COMMAND
```

如果为空或路径不对，重新设置：

```powershell
$env:ABAQUS_COMMAND = "G:\SIMULIA\Commands\abaqus.bat"
npm.cmd run dev
```

### GitHub clone 后缺少某些结果

大型 ODB、INP 和超大 `result_mesh.json` 没有上传。需要重新运行对应 Abaqus 脚本或刷新脚本。

### 构建前端

```powershell
Set-Location E:\Users\Cai\Downloads\text-to-cae\viewer
npm.cmd run build
```

构建产物会写入 `viewer/dist/`，该目录不会提交到 Git。
