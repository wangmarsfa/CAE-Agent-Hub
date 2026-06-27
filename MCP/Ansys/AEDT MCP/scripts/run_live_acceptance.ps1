#Requires -Version 5.1
param(
    [ValidateSet("grpc", "pid", "both")]
    [string]$Mode = "both",
    [string]$AedtRoot = "G:\ANSYS206\ANSYS Inc\v261\AnsysEM",
    [int]$Port = 50061
)

$ErrorActionPreference = "Stop"
$ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$Python = Join-Path $ModuleRoot ".venv\Scripts\python.exe"
$Runner = Join-Path $ModuleRoot "tests\live\run_acceptance.py"
$Artifacts = Join-Path $ModuleRoot "test-artifacts"
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class AedtAcceptanceWindows {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    public static string Text(IntPtr hWnd) { var b = new StringBuilder(2048); GetWindowText(hWnd, b, b.Capacity); return b.ToString(); }
}
'@

function Get-AedtWindowTexts {
    param([int]$ProcessId)
    $texts = New-Object System.Collections.Generic.List[string]
    $callback = [AedtAcceptanceWindows+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$state)
        [uint32]$owner = 0
        [void][AedtAcceptanceWindows]::GetWindowThreadProcessId($hWnd, [ref]$owner)
        if ($owner -eq $ProcessId) {
            $text = [AedtAcceptanceWindows]::Text($hWnd)
            if ($text) { $texts.Add($text) }
            $child = [AedtAcceptanceWindows+EnumWindowsProc]{
                param([IntPtr]$childHwnd, [IntPtr]$childState)
                $childText = [AedtAcceptanceWindows]::Text($childHwnd)
                if ($childText) { $texts.Add($childText) }
                return $true
            }
            [void][AedtAcceptanceWindows]::EnumChildWindows($hWnd, $child, [IntPtr]::Zero)
        }
        return $true
    }
    [void][AedtAcceptanceWindows]::EnumWindows($callback, [IntPtr]::Zero)
    return $texts
}

function Invoke-NormalCloseCheck {
    param([int]$ProcessId)
    $process = Get-Process -Id $ProcessId -ErrorAction Stop
    if ($process.MainWindowHandle -eq 0) { throw "AEDT PID $ProcessId has no main window handle." }
    [void][AedtAcceptanceWindows]::PostMessage($process.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }
        $text = (Get-AedtWindowTexts -ProcessId $ProcessId) -join "`n"
        if ($text -match "being used by another application, script or extension wizard") {
            throw "AEDT busy dialog detected for PID $ProcessId. The process was left running for inspection."
        }
        Start-Sleep -Milliseconds 250
    }
    throw "AEDT PID $ProcessId did not exit after normal WM_CLOSE. It was left running for inspection."
}

$modes = if ($Mode -eq "both") { @("grpc", "pid") } else { @($Mode) }
foreach ($currentMode in $modes) {
    $resultPath = Join-Path $Artifacts "$currentMode-result.json"
    & $Python $Runner --mode $currentMode --aedt-root $AedtRoot --port $Port --result $resultPath
    if ($LASTEXITCODE -ne 0) { throw "$currentMode acceptance operations failed." }
    $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
    Invoke-NormalCloseCheck -ProcessId ([int]$result.session.pid)
    Write-Host "[AEDT MCP] $currentMode acceptance passed for PID $($result.session.pid)."
}
