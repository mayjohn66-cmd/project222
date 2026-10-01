@echo off
rem Story draft runner (Windows, run on YOUR PC only).
rem Usage:  dev\gemini\run_story_draft.bat "topic text" [count]
rem Needs two environment variables (set them once with setx, then open a NEW terminal):
rem   GODOT_EXE        full path of the Godot console exe, e.g. C:\Tools\Godot\Godot_v4.7.1-stable_win64_console.exe
rem   GEMINI_API_KEY   your AI Studio key (never paste it in chat or commit it)
chcp 65001 >nul
setlocal
rem Project root = two folders above this file (dev\gemini -> project root)
cd /d "%~dp0..\.."
echo Project root: %CD%

if "%GODOT_EXE%"=="" (
  echo [ERROR] GODOT_EXE is not set. Example:
  echo   setx GODOT_EXE "C:\path\to\Godot_v4.7.1-stable_win64_console.exe"
  echo then open a NEW terminal and run this again.
  exit /b 2
)
if not exist "%GODOT_EXE%" (
  echo [ERROR] GODOT_EXE file not found: %GODOT_EXE%
  exit /b 2
)
if "%GEMINI_API_KEY%"=="" (
  echo [ERROR] GEMINI_API_KEY is not set. Run:  setx GEMINI_API_KEY "your-key"  then open a NEW terminal.
  exit /b 2
)

set "TOPIC=%~1"
set "COUNT=%~2"
if "%TOPIC%"=="" set "TOPIC=first customer talk"
if "%COUNT%"=="" set "COUNT=1"

echo Topic: %TOPIC% / Count: %COUNT%
"%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/story_draft.tscn -- --topic "%TOPIC%" --count %COUNT%
if errorlevel 1 (
  echo [ERROR] draft generation failed. See the message above.
  exit /b 1
)

rem Validate the newest draft with Godot (no Python needed)
for /f "delims=" %%f in ('dir /b /o-d docs\drafts\story\story_beats_gemini_*.csv') do (
  echo Validating docs\drafts\story\%%f
  "%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/validate_story.tscn -- --file "docs/drafts/story/%%f"
  goto :done
)
echo [WARN] no draft file found.
:done
)
echo [WARN] no draft file found.
:done
endlocal
