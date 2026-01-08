@echo off
REM Quick Git Commit and Push Script
REM Usage: quick-commit.bat "your commit message"

if "%~1"=="" (
    echo Error: Please provide a commit message
    echo Usage: quick-commit.bat "your commit message"
    exit /b 1
)

echo Staging all changes...
git add -A

echo Creating commit...
git commit -m "%~1" -m "Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

echo Pushing to remote...
git push

echo.
echo Done! Changes committed and pushed.
