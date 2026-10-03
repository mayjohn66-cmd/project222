@echo off
rem Shows THIS folder's git state in one screen: folder, branch, last commit, ahead/behind remote, uncommitted changes.
rem Double-click or run in a terminal, then send a screenshot to the AI. Read-only: it changes nothing (fetch only updates remote info).
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
where git >nul 2>&1
if errorlevel 1 (
  echo [ERROR] git not found.
  pause
  exit /b 2
)
git fetch --quiet origin 2>nul
echo ==================== WHERE AM I ====================
echo Folder  : %CD%
for /f "delims=" %%b in ('git branch --show-current') do echo Branch  : %%b
for /f "delims=" %%c in ('git log -1 --format^="%%h %%s"') do echo Commit  : %%c
echo.
echo --- vs remote (origin/same-branch) ---
for /f "delims=" %%b in ('git branch --show-current') do (
  git rev-parse --verify --quiet origin/%%b >nul
  if errorlevel 1 (
    echo This branch is NOT on the remote yet ^(never pushed^).
  ) else (
    for /f "tokens=1,2" %%x in ('git rev-list --left-right --count origin/%%b...HEAD') do (
      echo Remote has %%x commit^(s^) you do not have  ^(-^> git pull origin %%b^)
      echo You have  %%y commit^(s^) not pushed        ^(-^> ask the AI or git push^)
    )
  )
)
echo.
echo --- uncommitted changes (first 15) ---
git status --short | findstr /n "^" | findstr /r "^[1-9]: ^1[0-5]:"
echo (blank above = clean)
echo.
echo --- other branches updated recently on remote ---
git for-each-ref --sort=-committerdate --count=6 --format="%%(refname:short)  %%(committerdate:relative)" refs/remotes/origin
echo ====================================================
pause
