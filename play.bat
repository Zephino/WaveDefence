@echo off
setlocal
cd /d "%~dp0"

echo Wave Defence - checking prerequisites and launching...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1" %*
set EXITCODE=%ERRORLEVEL%

if %EXITCODE% neq 0 (
  echo.
  echo Launcher failed with exit code %EXITCODE%.
  if exist "%~dp0godot_launch.log" (
    echo.
    echo --- godot_launch.log ---
    type "%~dp0godot_launch.log"
  )
  echo.
  pause
  exit /b %EXITCODE%
)

exit /b 0
