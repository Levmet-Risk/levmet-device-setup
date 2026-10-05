@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bootstrap.ps1" -LaunchCodex
if errorlevel 1 pause
