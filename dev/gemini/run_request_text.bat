@echo off
rem Request text tool runner (Windows, run on YOUR PC only).
rem Usage:
rem   dev\gemini\run_request_text.bat draft [kind]     ask Gemini to write request texts, then validate
rem   dev\gemini\run_request_text.bat validate file    validate a CSV (path relative to the project root)
rem   dev\gemini\run_request_text.bat export           export current texts as the baseline CSV
rem   dev\gemini\run_request_text.bat sync [--dry]    find NEW or CHANGED requests (no text yet) and have Gemini write only those; --dry = list only, no API call
rem   dev\gemini\run_request_text.bat polish file  polish a draft CSV with the main model (gemini-3.8-flash; --model name to change); saves <file>_polished.csv
rem   dev\gemini\run_request_text.bat accept file     merge a reviewed draft into the text CSV and update the state
rem   extra option for draft: --chunk N  (items per Gemini call, default 2), e.g.  draft resident_request --chunk 3
rem   --ids a,b,c  (draft only these item ids, comma separated, no spaces), e.g.  draft resident_request --ids settle_naru,settle_doyun --chunk 3
rem kind = resident_request | community_request | resident_greeting (optional)
rem Needs GODOT_EXE (and GEMINI_API_KEY for draft). Set them once with setx, then open a NEW terminal.
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

rem Refresh Godot's global class cache first (new class_name scripts pulled from git are unknown until then).
echo Refreshing Godot project cache (first run takes a while)...
"%GODOT_EXE%" --headless --path "%CD%" --import >nul 2>&1
set "MODE=%~1"
if "%MODE%"=="" set "MODE=draft"

if "%MODE%"=="draft" (
  if "%GEMINI_API_KEY%"=="" (
    echo [ERROR] GEMINI_API_KEY is not set. Run:  setx GEMINI_API_KEY "your-key"  then open a NEW terminal.
    exit /b 2
  )
  if "%~2"=="" (
    "%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/request_text.tscn -- --mode draft
  ) else (
    "%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/request_text.tscn -- --mode draft --kind %~2 %~3 %~4 %~5 %~6
  )
  goto :done
)
if "%MODE%"=="validate" (
  "%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/request_text.tscn -- --mode validate --file "%~2"
  goto :done
)
if "%MODE%"=="sync" (
  if not "%~2"=="--dry" (
    if "%GEMINI_API_KEY%"=="" (
      echo [ERROR] GEMINI_API_KEY is not set. Use "sync --dry" to only list what is new or changed.
      exit /b 2
    )
  )
  "%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/request_text.tscn -- --mode sync %~2
  goto :done
)
if "%MODE%"=="polish" (
  if "%GEMINI_API_KEY%"=="" (
    echo [ERROR] GEMINI_API_KEY is not set.
    exit /b 2
  )
  "%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/request_text.tscn -- --mode polish --file "%~2" %~3 %~4 %~5 %~6
  goto :done
)
if "%MODE%"=="accept" (
  "%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/request_text.tscn -- --mode accept --file "%~2"
  goto :done
)
if "%MODE%"=="export" (
  "%GODOT_EXE%" --headless --path "%CD%" res://dev/gemini/request_text.tscn -- --mode export
  goto :done
)
echo [ERROR] unknown mode: %MODE%  (draft, validate, export, sync, polish, accept)
:done
endlocal
