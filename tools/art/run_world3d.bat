@echo off
rem 3D village art helper (Windows, run on YOUR PC). Opens the terminal menu: progress / next prompt / ingest art / import+validate / regenerate requests.
rem Needs Python + Pillow (pip install pillow). Menu item 5 also needs GODOT_EXE (setx GODOT_EXE "C:\path\Godot_v4.7.1-stable_win64_console.exe", then open a NEW terminal).
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
where python >nul 2>&1
if errorlevel 1 (
  echo [ERROR] python not found. Install Python 3 and run: pip install pillow
  exit /b 2
)
python tools\art\world3d_menu.py %*
