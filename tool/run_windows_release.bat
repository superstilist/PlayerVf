@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_windows_release.ps1" %*
exit /b %ERRORLEVEL%
