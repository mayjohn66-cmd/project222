@echo off
rem Story autopilot (Windows, run on YOUR PC, in the story-only clone on branch feature/story-script).
rem Leave this window open: every N seconds it fetches, finds NEW/CHANGED requests, has Gemini write them, validates,
rem and (with --auto-accept) merges + commits + pushes ONLY the text files to feature/story-script.
rem Usage:
rem   dev\gemini\run_story_autopilot.bat                        draft only, notify (default, safest)
rem   dev\gemini\run_story_autopilot.bat --auto-accept          merge validated drafts, commit and push automatically
rem   dev\gemini\run_story_autopilot.bat --once                 one pass then exit
rem   options: --interval 600  --no-push  --source-branch NAME  (or set STORY_SOURCE_BRANCH)
rem Needs GODOT_EXE and GEMINI_API_KEY (setx once, then open a NEW terminal).
chcp 65001 >nul
setlocal
cd /d "%~dp0..\.."
echo Project root: %CD%
if "%GODOT_EXE%"=="" (
  echo [ERROR] GODOT_EXE is not set. Example:  setx GODOT_EXE "C:\path\to\Godot_v4.7.1-stable_win64_console.exe"
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
"%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/request_text.tscn -- --mode autopilot %*
endlocal
