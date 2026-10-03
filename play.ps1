#Requires -Version 5.1
<#
.SYNOPSIS
  Installs Wave Defence prerequisites (Godot 4 via winget) and launches the game.

.EXAMPLE
  .\play.ps1
  .\play.ps1 -Editor
#>
param(
    [switch]$Editor,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$LaunchLog = Join-Path $ProjectRoot "godot_launch.log"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Find-Godot {
    $candidates = @()

    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }

    $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\godot.exe"
    if (Test-Path $wingetLinks) { $candidates += $wingetLinks }

    $pkgRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $pkgRoot) {
        $found = Get-ChildItem $pkgRoot -Recurse -Filter "Godot*.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "console|mono" -and $_.Name -match "Godot_v|godot\.exe|Godot\.exe" } |
            Select-Object -ExpandProperty FullName
        $candidates += $found
    }

    foreach ($path in $candidates | Select-Object -Unique) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }
    return $null
}

function Install-Godot {
    Write-Step "Checking for winget"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget was not found. Install Godot 4 from https://godotengine.org/ then re-run this script."
    }

    Write-Step "Installing Godot Engine (GodotEngine.GodotEngine) via winget"
    & winget install --id GodotEngine.GodotEngine -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Host "winget exit code: $LASTEXITCODE (continuing if Godot is available)" -ForegroundColor Yellow
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Test-GodotProject([string]$GodotPath) {
    # Validate the project path (spaces must remain one argument).
    $output = & $GodotPath --path $ProjectRoot --headless --quit-after 1 2>&1 | Out-String
    Set-Content -Path $LaunchLog -Value $output -Encoding UTF8
    if ($output -match "Invalid project path") {
        throw "Godot rejected the project path. Details in godot_launch.log"
    }
}

function Start-GodotGame([string]$GodotPath, [bool]$OpenEditor) {
    # IMPORTANT: folder name contains a space ("Wave Defence").
    # Pass one quoted argument string so the path is not split.
    $argLine = if ($OpenEditor) {
        "--path `"$ProjectRoot`" --editor"
    } else {
        "--path `"$ProjectRoot`""
    }

    Write-Host "Command: `"$GodotPath`" $argLine"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GodotPath
    $psi.Arguments = $argLine
    $psi.WorkingDirectory = $ProjectRoot
    $psi.UseShellExecute = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $proc) {
        throw "Failed to start Godot process."
    }

    Start-Sleep -Seconds 2
    try {
        $proc.Refresh()
        if ($proc.HasExited) {
            throw "Godot exited immediately (code $($proc.ExitCode)). See godot_launch.log"
        }
    } catch [InvalidOperationException] {
        # Process object may not track shim child; fall back to process name search.
        $running = Get-Process | Where-Object {
            $_.ProcessName -match "Godot|godot"
        }
        if (-not $running) {
            throw "Godot did not stay running. See godot_launch.log"
        }
    }
}

function Main {
    if (-not (Test-Path $ProjectFile)) {
        throw "project.godot not found in $ProjectRoot"
    }

    Write-Host "Wave Defence launcher" -ForegroundColor Green
    Write-Host "Project: $ProjectRoot"

    $godot = Find-Godot
    if (-not $godot -and -not $SkipInstall) {
        Install-Godot
        $godot = Find-Godot
    }

    if (-not $godot) {
        throw "Godot was not found after install. Open a new terminal, or install from https://godotengine.org/ then re-run."
    }

    Write-Step "Using Godot at: $godot"
    try {
        $ver = & $godot --version 2>&1
        Write-Host "Version: $ver"
    } catch {
        Write-Host "Could not read Godot version (continuing)" -ForegroundColor Yellow
    }

    Write-Step "Checking project loads"
    Test-GodotProject -GodotPath $godot

    if ($Editor) {
        Write-Step "Opening project in Godot editor"
    } else {
        Write-Step "Starting game"
    }

    Start-GodotGame -GodotPath $godot -OpenEditor:$Editor

    Write-Host ""
    Write-Host "Game is running. You can close this window." -ForegroundColor Green
}

try {
    Main
    exit 0
} catch {
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    if (Test-Path $LaunchLog) {
        Write-Host ""
        Write-Host "--- godot_launch.log ---" -ForegroundColor Yellow
        Get-Content $LaunchLog
    }
    exit 1
}
