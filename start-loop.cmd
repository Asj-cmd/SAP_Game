@echo off
rem Starts the CashGrab autobuild loop in its own window. Does nothing if a loop is already running.
set GODOT_BIN=C:\Godot\Godot_v4.7.1-stable_win64_console.exe
set PLANNER_MODEL=opus
set WORKER_MODEL=opus
set MAX_TURNS=120
cd /d C:\Users\Jampa\cashgrab-auto
node autobuild\lock.mjs --check
if %ERRORLEVEL%==0 (
  echo Loop already running
  exit /b 0
)
start "CashGrab loop" cmd /k node autobuild/loop.mjs
