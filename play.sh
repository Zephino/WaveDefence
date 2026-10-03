#!/usr/bin/env bash
# Wave Defence launcher for Git Bash / WSL-like environments on Windows.
# Prefer play.bat / play.ps1 on native Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/project.godot" ]]; then
  echo "project.godot not found in $ROOT" >&2
  exit 1
fi

if command -v powershell.exe >/dev/null 2>&1; then
  echo "Delegating to play.ps1 via PowerShell..."
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ROOT/play.ps1" "$@"
fi

if command -v pwsh >/dev/null 2>&1; then
  echo "Delegating to play.ps1 via pwsh..."
  exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$ROOT/play.ps1" "$@"
fi

echo "PowerShell not found. Install Godot 4 and run:" >&2
echo "  godot --path \"$ROOT\"" >&2
exit 1
